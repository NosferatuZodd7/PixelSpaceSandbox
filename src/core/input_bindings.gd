class_name InputBindings
extends RefCounted
## Default key bindings from data/input_bindings.json, registered in the InputMap.
##
## Bindings live in data so that rebinding (milestone 9) only has to store the
## player's overrides on top of these defaults.

const DEFAULT_PATH: String = "res://data/input_bindings.json"

## Short labels for keys whose names are long on screen.
const SHORT_KEY_NAMES: Dictionary[String, String] = {
	"Escape": "Esc", "PageUp": "PgUp", "PageDown": "PgDn", "Delete": "Del", "Insert": "Ins",
}


## Registers every action of the bindings file in the InputMap, replacing the
## events of actions that already exist.
static func apply(path: String = DEFAULT_PATH) -> Error:
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("InputBindings: cannot parse '%s': %s" % [path, json.get_error_message()])
		return ERR_PARSE_ERROR
	var parsed: Dictionary = parse(json.data)
	var errors: PackedStringArray = parsed["errors"]
	for message: String in errors:
		push_error("InputBindings: '%s': %s" % [path, message])
	var actions: Dictionary = parsed["actions"]
	for action: StringName in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var events: Array[InputEventKey] = actions[action]
		for event: InputEventKey in events:
			InputMap.action_add_event(action, event)
	return OK if errors.is_empty() else ERR_INVALID_DATA


## Converts bindings data (the parsed JSON) into key events. Never prints: it
## returns {"actions": {action: Array[InputEventKey]}, "errors": PackedStringArray}.
static func parse(data: Variant) -> Dictionary:
	var actions: Dictionary[StringName, Array] = {}
	var errors: PackedStringArray = []
	if not data is Dictionary or not (data as Dictionary).get("actions") is Dictionary:
		errors.append("the file must have an 'actions' object")
		return {"actions": actions, "errors": errors}
	var entries: Dictionary = (data as Dictionary)["actions"]
	for action: Variant in entries:
		var action_name: String = str(action)
		if not action_name.is_valid_ascii_identifier():
			errors.append("invalid action name '%s'" % action_name)
			continue
		var keys: Variant = entries[action]
		if not keys is Array:
			errors.append("action '%s' must list its keys" % action_name)
			continue
		var events: Array[InputEventKey] = []
		for key: Variant in keys:
			var event: InputEventKey = key_event_from_string(str(key))
			if event == null:
				errors.append("action '%s' has an unknown key '%s'" % [action_name, key])
			else:
				events.append(event)
		actions[StringName(action_name)] = events
	return {"actions": actions, "errors": errors}


## The text shown for a key in hints and menus ("Esc", "Ctrl+Z", "F11").
static func key_label(event: InputEventKey) -> String:
	var parts: PackedStringArray = event.as_text_keycode().split("+")
	for i: int in parts.size():
		parts[i] = SHORT_KEY_NAMES.get(parts[i], parts[i])
	return "+".join(parts)


## Builds a key event from a key name with optional modifiers ("Ctrl+Z").
## Returns null when the key name is unknown.
static func key_event_from_string(text: String) -> InputEventKey:
	var code: int = OS.find_keycode_from_string(text)
	var key: int = code & KEY_CODE_MASK
	if key == KEY_NONE:
		return null
	var event: InputEventKey = InputEventKey.new()
	event.keycode = key as Key
	event.shift_pressed = (code & KEY_MASK_SHIFT) != 0
	event.ctrl_pressed = (code & KEY_MASK_CTRL) != 0
	event.alt_pressed = (code & KEY_MASK_ALT) != 0
	event.meta_pressed = (code & KEY_MASK_META) != 0
	return event
