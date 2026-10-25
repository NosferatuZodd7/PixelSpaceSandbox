class_name PresetLoader
extends RefCounted
## Builds a StarSystem from a preset data file (data/presets/*.json).
##
## Like the other data parsers it never prints: it returns
## {"system": StarSystem, "errors": PackedStringArray} so a broken preset (or
## a mod's) can be reported instead of crashing the game.

const KINDS: Dictionary[String, CelestialBody.Kind] = {
	"star": CelestialBody.Kind.STAR,
	"planet": CelestialBody.Kind.PLANET,
	"dwarf_planet": CelestialBody.Kind.DWARF_PLANET,
	"moon": CelestialBody.Kind.MOON,
	"black_hole": CelestialBody.Kind.BLACK_HOLE,
}
const JPL_ELEMENTS: Array[String] = ["a", "e", "i", "L", "peri", "node"]


static func load_file(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data == null:
		var errors: PackedStringArray = ["cannot read or parse '%s'" % path]
		return {"system": StarSystem.new(), "errors": errors}
	return parse(data)


static func parse(data: Variant) -> Dictionary:
	var system: StarSystem = StarSystem.new()
	var errors: PackedStringArray = []
	if not data is Dictionary or not (data as Dictionary).get("bodies") is Array:
		errors.append("a preset needs a 'bodies' list")
		return {"system": system, "errors": errors}
	var root: Dictionary = data
	system.name_key = str(root.get("name_key", ""))
	var partners: Dictionary[int, String] = {}
	for entry: Variant in root["bodies"]:
		if not entry is Dictionary:
			errors.append("every body must be an object")
			continue
		var fields: Dictionary = entry
		var body_errors: PackedStringArray = []
		var b: CelestialBody = _body(fields, system, body_errors)
		if body_errors.is_empty():
			var index: int = system.add(b)
			if fields.has("barycenter_partner"):
				partners[index] = str(fields["barycenter_partner"])
		for message: String in body_errors:
			errors.append("%s: %s" % [fields.get("id", "?"), message])
	for index: int in partners:
		var partner: int = system.index_of(StringName(partners[index]))
		if partner == -1 or system.body(partner).parent != index:
			errors.append("%s: barycenter partner '%s' must be one of its moons" % [system.body(index).id, partners[index]])
		else:
			system.body(index).barycenter_partner = partner
	if system.size() == 0 or not system.body(0).is_star():
		errors.append("the first body must be a star")
	for entry: Variant in root.get("belts", []):
		var belt_errors: PackedStringArray = SmallBodies.check_belt(entry, system)
		if belt_errors.is_empty():
			system.belts.append(entry)
		for message: String in belt_errors:
			errors.append("belt %s: %s" % [(entry as Dictionary).get("id", "?") if entry is Dictionary else "?", message])
	for entry: Variant in root.get("comets", []):
		var comet_errors: PackedStringArray = SmallBodies.check_comet(entry, system)
		if comet_errors.is_empty():
			system.comets.append(entry)
		for message: String in comet_errors:
			errors.append("comet %s: %s" % [(entry as Dictionary).get("id", "?") if entry is Dictionary else "?", message])
	return {"system": system, "errors": errors}


static func _body(fields: Dictionary, system: StarSystem, errors: PackedStringArray) -> CelestialBody:
	var b: CelestialBody = CelestialBody.new()
	var id: String = str(fields.get("id", ""))
	if not id.is_valid_ascii_identifier():
		errors.append("invalid id")
	elif system.index_of(StringName(id)) != -1:
		errors.append("duplicate id")
	b.id = StringName(id)
	b.name_key = str(fields.get("name_key", id))
	var kind_name: String = str(fields.get("kind", ""))
	if not KINDS.has(kind_name):
		errors.append("unknown kind '%s'" % kind_name)
	else:
		b.kind = KINDS[kind_name]
	b.mass = Units.solar_masses_from_kg(_number(fields, "mass_kg", 0.0))
	b.radius = Units.au_from_km(_number(fields, "radius_km", 0.0))
	if b.mass <= 0.0 or b.radius <= 0.0:
		errors.append("mass_kg and radius_km must be positive")
	b.luminosity = _number(fields, "luminosity_lsun", 0.0)
	b.temperature = _number(fields, "temperature_k", 0.0)
	b.albedo = clampf(_number(fields, "albedo", 0.3), 0.0, 1.0)
	b.rotation_hours = _number(fields, "rotation_hours", 24.0)
	b.axial_tilt_deg = _number(fields, "axial_tilt_deg", 0.0)
	b.look = StringName(str(fields.get("look", id)))
	var pole: Variant = fields.get("pole")
	if pole is Array and (pole as Array).size() == 2:
		b.pole_ra_deg = float((pole as Array)[0])
		b.pole_dec_deg = float((pole as Array)[1])
	if b.is_star() and b.luminosity <= 0.0:
		errors.append("a star needs a positive luminosity_lsun")

	if fields.has("parent"):
		b.parent = system.index_of(StringName(str(fields["parent"])))
		if b.parent == -1:
			errors.append("parent '%s' must be listed before it" % fields["parent"])
	if b.parent != -1:
		var orbit_fields: Variant = fields.get("orbit")
		if not orbit_fields is Dictionary:
			errors.append("a body with a parent needs an orbit")
		else:
			b.orbit = _orbit(orbit_fields, b, system.body(b.parent), errors)
			b.approximate_phase = bool((orbit_fields as Dictionary).get("approximate_phase", false))

	var rings: Variant = fields.get("rings", [])
	if rings is Array:
		for ring: Variant in rings:
			if ring is Dictionary:
				var r: Dictionary = ring
				var inner: float = Units.au_from_km(_number(r, "inner_km", 0.0))
				var outer: float = Units.au_from_km(_number(r, "outer_km", 0.0))
				if inner <= 0.0 or outer <= inner:
					errors.append("a ring needs 0 < inner_km < outer_km")
				else:
					b.rings.append({
						"inner": inner, "outer": outer,
						"color": StringName(str(r.get("color", "dust"))),
						"density": clampf(_number(r, "density", 0.5), 0.0, 1.0),
					})
	return b


static func _orbit(fields: Dictionary, b: CelestialBody, parent: CelestialBody, errors: PackedStringArray) -> OrbitModel:
	match str(fields.get("model", "")):
		"jpl_approx":
			var values: Dictionary[String, PackedFloat64Array] = {}
			for key: String in JPL_ELEMENTS:
				var pair: Variant = fields.get(key)
				if not pair is Array or (pair as Array).size() != 2:
					errors.append("jpl_approx orbit needs %s = [value, rate per century]" % key)
					return null
				values[key] = PackedFloat64Array(pair as Array)
			var orbit: KeplerOrbit = KeplerOrbit.from_mean_longitude(
				values["a"][0], values["e"][0], values["i"][0], values["L"][0],
				values["peri"][0], values["node"][0], 0.0, values["L"][1]
			)
			orbit.a_rate = values["a"][1]
			orbit.e_rate = values["e"][1]
			orbit.inclination_rate = values["i"][1]
			orbit.periapsis_rate = values["peri"][1]
			orbit.node_rate = values["node"][1]
			_check_shape(orbit.a, orbit.e, errors)
			return orbit
		"elements":
			var a: float = _number(fields, "a_au", 0.0)
			if fields.has("a_km"):
				a = Units.au_from_km(_number(fields, "a_km", 0.0))
			var e: float = _number(fields, "e", 0.0)
			_check_shape(a, e, errors)
			if not errors.is_empty():
				return null
			var period_years: float = Kepler.period_years(a, parent.mass + b.mass)
			if fields.has("period_days"):
				period_years = _number(fields, "period_days", 1.0) / Units.YEAR_DAYS
			var orbit: KeplerOrbit = KeplerOrbit.from_anomaly(
				a, e, _number(fields, "i_deg", 0.0), _number(fields, "node_deg", 0.0),
				_number(fields, "arg_peri_deg", 0.0), _number(fields, "mean_anomaly_deg", 0.0),
				Units.years_from_julian_date(_number(fields, "epoch_jd", Units.J2000_JD)),
				360.0 * Units.CENTURY_YEARS / period_years
			)
			match str(fields.get("frame", "ecliptic")):
				"ecliptic":
					pass
				"parent_equator":
					orbit.frame = KeplerOrbit.equator_frame(parent.pole_ra_deg, parent.pole_dec_deg)
				var other:
					errors.append("unknown orbit frame '%s'" % other)
			return orbit
		"lunar_low_precision":
			return LunarOrbit.new()
		var other:
			errors.append("unknown orbit model '%s'" % other)
			return null


static func _check_shape(a: float, e: float, errors: PackedStringArray) -> void:
	if a <= 0.0:
		errors.append("the semi-major axis must be positive")
	if e < 0.0 or e >= 1.0:
		errors.append("the eccentricity must be in [0, 1)")


static func _number(fields: Dictionary, key: String, default_value: float) -> float:
	var value: Variant = fields.get(key, default_value)
	return float(value) if (value is float or value is int) else default_value
