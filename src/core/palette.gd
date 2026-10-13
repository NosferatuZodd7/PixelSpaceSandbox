class_name Palette
extends RefCounted
## The one shared colour palette, loaded from data/palette.json.
##
## Every colour in the game comes from here: code asks for a colour by its id
## ("nebula_3") or by a semantic alias ("ui_text"), never by a hex value.

const DEFAULT_PATH: String = "res://data/palette.json"

static var _colors: Dictionary[StringName, Color] = {}
static var _aliases: Dictionary[StringName, StringName] = {}
static var _ids: Array[StringName] = []
static var _loaded: bool = false


## Returns the colour for an id or alias. An unknown name is an error and
## returns magenta, so it stands out on screen.
static func color(name: StringName) -> Color:
	_ensure_loaded()
	var id: StringName = _aliases.get(name, name)
	if not _colors.has(id):
		push_error("Palette: unknown colour '%s'." % name)
		return Color.MAGENTA
	return _colors[id]


## True if the name is a colour id or an alias.
static func has(name: StringName) -> bool:
	_ensure_loaded()
	return _colors.has(name) or _aliases.has(name)


## Colour ids in palette order (aliases not included).
static func ids() -> Array[StringName]:
	_ensure_loaded()
	return _ids.duplicate()


static func aliases() -> Dictionary[StringName, StringName]:
	_ensure_loaded()
	return _aliases.duplicate()


## The colour id closest to the given colour (squared RGB distance).
static func nearest_id(target: Color) -> StringName:
	_ensure_loaded()
	var best_id: StringName = &""
	var best_distance: float = INF
	for id: StringName in _ids:
		var c: Color = _colors[id]
		var distance: float = (
			pow(c.r - target.r, 2.0) + pow(c.g - target.g, 2.0) + pow(c.b - target.b, 2.0)
		)
		if distance < best_distance:
			best_distance = distance
			best_id = id
	return best_id


## Loads a palette file, replacing the current palette. Reports problems with
## push_error and keeps the previous palette if the file is invalid.
static func load_file(path: String = DEFAULT_PATH) -> Error:
	_loaded = true
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Palette: cannot read '%s'." % path)
		return ERR_FILE_CANT_OPEN
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		push_error(
			"Palette: '%s' line %d: %s" % [path, json.get_error_line(), json.get_error_message()]
		)
		return ERR_PARSE_ERROR
	var parsed: Dictionary = parse(json.data)
	var errors: PackedStringArray = parsed["errors"]
	if not errors.is_empty():
		for message: String in errors:
			push_error("Palette: '%s': %s" % [path, message])
		return ERR_INVALID_DATA
	_colors = parsed["colors"]
	_aliases = parsed["aliases"]
	_ids = parsed["ids"]
	return OK


## Validates and converts palette data (the parsed JSON). Never prints: it
## returns {"colors", "aliases", "ids", "errors"} so callers decide what to do.
static func parse(data: Variant) -> Dictionary:
	var colors: Dictionary[StringName, Color] = {}
	var palette_aliases: Dictionary[StringName, StringName] = {}
	var order: Array[StringName] = []
	var errors: PackedStringArray = []
	if not data is Dictionary:
		errors.append("the root must be an object")
		return _parsed(colors, palette_aliases, order, errors)
	var root: Dictionary = data
	var entries: Variant = root.get("colors")
	if not entries is Array or (entries as Array).is_empty():
		errors.append("'colors' must be a non-empty list")
		return _parsed(colors, palette_aliases, order, errors)
	for entry: Variant in entries:
		if not entry is Dictionary:
			errors.append("every colour must be an object")
			continue
		var fields: Dictionary = entry
		var id: String = str(fields.get("id", ""))
		var hex: String = str(fields.get("hex", ""))
		if not id.is_valid_ascii_identifier():
			errors.append("invalid colour id '%s'" % id)
		elif colors.has(StringName(id)):
			errors.append("duplicate colour id '%s'" % id)
		elif not hex.begins_with("#") or hex.length() != 7 or not Color.html_is_valid(hex):
			errors.append("colour '%s' has an invalid hex value '%s'" % [id, hex])
		else:
			colors[StringName(id)] = Color.html(hex)
			order.append(StringName(id))
	var alias_entries: Variant = root.get("aliases", {})
	if not alias_entries is Dictionary:
		errors.append("'aliases' must be an object")
		return _parsed(colors, palette_aliases, order, errors)
	var alias_map: Dictionary = alias_entries
	for alias: Variant in alias_map:
		var alias_name: StringName = StringName(str(alias))
		var target: StringName = StringName(str(alias_map[alias]))
		if colors.has(alias_name):
			errors.append("alias '%s' hides a colour id" % alias_name)
		elif not colors.has(target):
			errors.append("alias '%s' points to unknown colour '%s'" % [alias_name, target])
		else:
			palette_aliases[alias_name] = target
	return _parsed(colors, palette_aliases, order, errors)


static func _parsed(
	colors: Dictionary[StringName, Color],
	palette_aliases: Dictionary[StringName, StringName],
	order: Array[StringName],
	errors: PackedStringArray
) -> Dictionary:
	return {"colors": colors, "aliases": palette_aliases, "ids": order, "errors": errors}


static func _ensure_loaded() -> void:
	if not _loaded:
		load_file(DEFAULT_PATH)
