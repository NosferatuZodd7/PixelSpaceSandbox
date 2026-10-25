class_name PowerCatalog
extends RefCounted
## The god powers listed in data/powers.json, and the bodies the "place"
## powers add.
##
## Like the other data parsers it never prints: it returns
## {"powers": Array[Dictionary], "errors": PackedStringArray} so a broken
## catalog (or a mod's) can be reported instead of crashing the game.

const PATH: String = "res://data/powers.json"
const ACTIONS: Array[String] = ["place", "fling", "delete"]
const FIELDS: Array[String] = ["id", "tab", "action", "icon", "name_key", "hint_key"]


static func load_file(path: String = PATH) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data == null:
		var powers: Array[Dictionary] = []
		var errors: PackedStringArray = ["cannot read or parse '%s'" % path]
		return {"powers": powers, "errors": errors}
	return parse(data)


static func parse(data: Variant) -> Dictionary:
	var powers: Array[Dictionary] = []
	var errors: PackedStringArray = []
	if not data is Dictionary or not (data as Dictionary).get("powers") is Array:
		errors.append("a power catalog needs a 'powers' list")
		return {"powers": powers, "errors": errors}
	var ids: PackedStringArray = []
	for entry: Variant in (data as Dictionary)["powers"]:
		if not entry is Dictionary:
			errors.append("every power must be an object")
			continue
		var power: Dictionary = entry
		var power_errors: PackedStringArray = _check(power, ids)
		if power_errors.is_empty():
			powers.append(power)
			ids.append(str(power["id"]))
		for message: String in power_errors:
			errors.append("%s: %s" % [power.get("id", "?"), message])
	return {"powers": powers, "errors": errors}


## A new body for a "place" power, numbered after the bodies with the same
## name already in the system ("Star 3"), with an id of its own.
static func make_body(power: Dictionary, system: StarSystem) -> CelestialBody:
	var fields: Dictionary = power["body"]
	var b: CelestialBody = CelestialBody.new()
	b.kind = PresetLoader.KINDS[str(fields["kind"])]
	b.name_key = str(fields["name_key"])
	b.mass = _mass(fields)
	b.radius = Units.au_from_km(_number(fields, "radius_km", 0.0))
	b.luminosity = _number(fields, "luminosity_lsun", 0.0)
	b.temperature = _number(fields, "temperature_k", 0.0)
	b.albedo = clampf(_number(fields, "albedo", 0.3), 0.0, 1.0)
	b.rotation_hours = _number(fields, "rotation_hours", 24.0)
	b.look = StringName(str(fields.get("look", "")))
	var number: int = 1
	for other: CelestialBody in system.bodies:
		if other.name_key == b.name_key:
			number = maxi(number, other.name_number + 1)
	b.name_number = number
	var suffix: int = number
	while system.index_of(StringName("%s_%d" % [power["id"], suffix])) != -1:
		suffix += 1
	b.id = StringName("%s_%d" % [power["id"], suffix])
	return b


static func _check(power: Dictionary, ids: PackedStringArray) -> PackedStringArray:
	var errors: PackedStringArray = []
	for field: String in FIELDS:
		if not power.get(field) is String or str(power[field]).is_empty():
			errors.append("needs a '%s'" % field)
	if not errors.is_empty():
		return errors
	if not str(power["id"]).is_valid_ascii_identifier():
		errors.append("invalid id")
	elif ids.has(str(power["id"])):
		errors.append("duplicate id")
	if power.has("flyby_kms") and _number(power, "flyby_kms", 0.0) <= 0.0:
		errors.append("flyby_kms must be a positive number")
	if not ACTIONS.has(str(power["action"])):
		errors.append("unknown action '%s'" % power["action"])
	elif power["action"] == "place":
		if not power.get("body") is Dictionary:
			errors.append("a 'place' power needs a body")
		else:
			_check_body(power["body"], errors)
	return errors


static func _check_body(fields: Dictionary, errors: PackedStringArray) -> void:
	if not PresetLoader.KINDS.has(str(fields.get("kind", ""))):
		errors.append("unknown kind '%s'" % fields.get("kind", ""))
	if _mass(fields) <= 0.0 or _number(fields, "radius_km", 0.0) <= 0.0:
		errors.append("the body needs a positive mass (mass_suns or mass_earths) and radius_km")
	if str(fields.get("kind", "")) == "star" and _number(fields, "luminosity_lsun", 0.0) <= 0.0:
		errors.append("a star needs a positive luminosity_lsun")
	if not fields.get("name_key") is String:
		errors.append("the body needs a name_key")


static func _mass(fields: Dictionary) -> float:
	if fields.has("mass_suns"):
		return _number(fields, "mass_suns", 0.0)
	return Units.solar_masses_from_kg(_number(fields, "mass_earths", 0.0) * Units.EARTH_MASS_KG)


static func _number(fields: Dictionary, key: String, default_value: float) -> float:
	var value: Variant = fields.get(key, default_value)
	return float(value) if (value is float or value is int) else default_value
