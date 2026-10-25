class_name SmallBodies
extends RefCounted
## The small bodies of a preset as particles: belts drawn at random (the
## same every time) and named comets from their real elements. They start
## asleep, riding their orbits around their parent until something comes
## near.

const KINDS: Dictionary[String, Gravity.ParticleKind] = {
	"asteroid": Gravity.ParticleKind.ASTEROID,
	"icy": Gravity.ParticleKind.ICY,
	"oort": Gravity.ParticleKind.OORT,
}


## What is wrong with a belt from a preset (nothing when empty).
static func check_belt(entry: Variant, system: StarSystem) -> PackedStringArray:
	var errors: PackedStringArray = []
	if not entry is Dictionary:
		errors.append("a belt must be an object")
		return errors
	var belt: Dictionary = entry
	if not str(belt.get("id", "")).is_valid_ascii_identifier():
		errors.append("invalid id")
	if not KINDS.has(str(belt.get("kind", ""))):
		errors.append("unknown kind '%s'" % belt.get("kind", ""))
	if system.index_of(StringName(str(belt.get("parent", "")))) == -1:
		errors.append("unknown parent '%s'" % belt.get("parent", ""))
	if not (belt.get("count") is float or belt.get("count") is int) or int(belt["count"]) < 0:
		errors.append("count must be a number of bodies")
	var a: Vector2 = _range(belt, "a_au")
	if a.x <= 0.0 or a.y <= a.x:
		errors.append("a_au must be [min, max] with 0 < min < max")
	var e: Vector2 = _range(belt, "e")
	if e.x < 0.0 or e.y < e.x or e.y >= 1.0:
		errors.append("e must be [min, max] within [0, 1)")
	if _number(belt, "radius_km") <= 0.0:
		errors.append("radius_km must be positive")
	return errors


## What is wrong with a comet from a preset (nothing when empty).
static func check_comet(entry: Variant, system: StarSystem) -> PackedStringArray:
	var errors: PackedStringArray = []
	if not entry is Dictionary:
		errors.append("a comet must be an object")
		return errors
	var comet: Dictionary = entry
	if not str(comet.get("id", "")).is_valid_ascii_identifier():
		errors.append("invalid id")
	if not comet.get("name_key") is String:
		errors.append("needs a name_key")
	if system.index_of(StringName(str(comet.get("parent", "")))) == -1:
		errors.append("unknown parent '%s'" % comet.get("parent", ""))
	if _number(comet, "q_au") <= 0.0:
		errors.append("q_au must be positive")
	var e: float = _number(comet, "e")
	if e < 0.0 or e >= 1.0:
		errors.append("e must be in [0, 1)")
	for key: String in ["i_deg", "node_deg", "arg_peri_deg", "perihelion_jd", "radius_km"]:
		if not (comet.get(key) is float or comet.get(key) is int):
			errors.append("needs %s" % key)
	return errors


## Adds the system's belts and comets to a state as sleeping particles,
## placed for time t. Returns the comets' particle indices by name key.
static func populate(state: NBodyState, system: StarSystem, t: float, g_scale: float) -> Dictionary[String, int]:
	for belt: Dictionary in system.belts:
		_add_belt(state, system, belt, t, g_scale)
	var named: Dictionary[String, int] = {}
	for comet: Dictionary in system.comets:
		var parent: int = system.index_of(StringName(str(comet["parent"])))
		var e: float = _number(comet, "e")
		var a: float = _number(comet, "q_au") / (1.0 - e)
		var mu: float = Units.G * g_scale * system.body(parent).mass
		var n: float = sqrt(mu / (a * a * a))
		var since: float = t - Units.years_from_julian_date(_number(comet, "perihelion_jd"))
		var index: int = _add(
			state, system, parent, a, e, deg_to_rad(_number(comet, "i_deg")), deg_to_rad(_number(comet, "node_deg")),
			deg_to_rad(_number(comet, "arg_peri_deg")), n * since, t, mu, Units.au_from_km(_number(comet, "radius_km")),
			Gravity.ParticleKind.COMET
		)
		named[str(comet["name_key"])] = index
	return named


static func _add_belt(state: NBodyState, system: StarSystem, belt: Dictionary, t: float, g_scale: float) -> void:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = hash(str(belt["id"]))
	var parent: int = system.index_of(StringName(str(belt["parent"])))
	var mu: float = Units.G * g_scale * system.body(parent).mass
	var a_range: Vector2 = _range(belt, "a_au")
	var e_range: Vector2 = _range(belt, "e")
	var gaps: Array = belt.get("gaps_au", [])
	var log_a: bool = bool(belt.get("log_a", false))
	var isotropic: bool = bool(belt.get("isotropic", false))
	var sigma: float = deg_to_rad(_number(belt, "i_sigma_deg"))
	var radius: float = Units.au_from_km(_number(belt, "radius_km"))
	var kind: Gravity.ParticleKind = KINDS[str(belt["kind"])]
	for k: int in int(belt["count"]):
		var a: float = _draw_a(random, a_range, log_a)
		for attempt: int in 100:
			if not _in_gap(a, gaps):
				break
			a = _draw_a(random, a_range, log_a)
		var e: float = random.randf_range(e_range.x, e_range.y)
		var inclination: float = acos(random.randf_range(-1.0, 1.0)) if isotropic else absf(random.randfn(0.0, sigma))
		_add(
			state, system, parent, a, e, inclination, random.randf_range(0.0, TAU), random.randf_range(0.0, TAU),
			random.randf_range(0.0, TAU), t, mu, radius, kind
		)


static func _add(
	state: NBodyState, system: StarSystem, parent: int, a: float, e: float, inclination: float, node: float,
	arg_periapsis: float, mean_anomaly: float, t: float, mu: float, radius: float, kind: Gravity.ParticleKind
) -> int:
	var relative: PackedFloat64Array = Kepler.state_from_elements(
		a, e, inclination, node, arg_periapsis, mean_anomaly, sqrt(mu / (a * a * a))
	)
	var elements: PackedFloat64Array = Kepler.elements_from_state(
		relative[0], relative[1], relative[2], relative[3], relative[4], relative[5], mu, t
	)
	var index: int = state.add_sleeping_particle(parent, elements, radius, kind)
	for k: int in 3:
		state.p_view[index * 3 + k] = system.positions[parent * 3 + k] + relative[k]
	return index


static func _draw_a(random: RandomNumberGenerator, a_range: Vector2, log_a: bool) -> float:
	if log_a:
		return exp(random.randf_range(log(a_range.x), log(a_range.y)))
	return random.randf_range(a_range.x, a_range.y)


static func _in_gap(a: float, gaps: Array) -> bool:
	for gap: Variant in gaps:
		if gap is Array and (gap as Array).size() == 2 and a > float(gap[0]) and a < float(gap[1]):
			return true
	return false


static func _range(fields: Dictionary, key: String) -> Vector2:
	var value: Variant = fields.get(key)
	if value is Array and (value as Array).size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2(-1.0, -1.0)


static func _number(fields: Dictionary, key: String) -> float:
	var value: Variant = fields.get(key, 0.0)
	return float(value) if (value is float or value is int) else 0.0
