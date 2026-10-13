extends TestCase
## Default key bindings come from data and register in the InputMap.


func _defaults() -> Dictionary:
	return InputBindings.parse(JSON.parse_string(FileAccess.get_file_as_string(InputBindings.DEFAULT_PATH)))


func test_default_bindings_parse_without_errors() -> void:
	var parsed: Dictionary = _defaults()
	var errors: PackedStringArray = parsed["errors"]
	assert_true(errors.is_empty(), "errors: %s" % ", ".join(errors))
	var actions: Dictionary = parsed["actions"]
	assert_false(actions.is_empty(), "has actions")
	for action: StringName in actions:
		var events: Array = actions[action]
		assert_false(events.is_empty(), "action '%s' has a key" % action)


func test_no_two_actions_share_a_key() -> void:
	var actions: Dictionary = _defaults()["actions"]
	var owners: Dictionary[String, StringName] = {}
	for action: StringName in actions:
		var events: Array[InputEventKey] = actions[action]
		for event: InputEventKey in events:
			var key: String = event.as_text()
			assert_false(owners.has(key), "'%s' is bound to '%s' and '%s'" % [key, owners.get(key, ""), action])
			owners[key] = action


func test_key_names_with_modifiers() -> void:
	var undo: InputEventKey = InputBindings.key_event_from_string("Ctrl+Z")
	assert_true(undo != null, "Ctrl+Z parses")
	if undo != null:
		assert_eq(undo.keycode, KEY_Z)
		assert_true(undo.ctrl_pressed, "Ctrl")
		assert_false(undo.shift_pressed, "no Shift")
	var escape: InputEventKey = InputBindings.key_event_from_string("Escape")
	assert_true(escape != null and escape.keycode == KEY_ESCAPE, "Escape parses")
	assert_true(InputBindings.key_event_from_string("NotAKey") == null, "unknown key")


func test_key_labels_are_short() -> void:
	assert_eq(InputBindings.key_label(InputBindings.key_event_from_string("Escape")), "Esc")
	assert_eq(InputBindings.key_label(InputBindings.key_event_from_string("Ctrl+Z")), "Ctrl+Z")
	assert_eq(InputBindings.key_label(InputBindings.key_event_from_string("F11")), "F11")


func test_parse_reports_bad_entries() -> void:
	assert_false((InputBindings.parse({}) as Dictionary)["errors"].is_empty(), "no actions")
	var bad_key: Dictionary = InputBindings.parse({"actions": {"jump": ["NotAKey"]}})
	assert_false((bad_key["errors"] as PackedStringArray).is_empty(), "unknown key")
	var bad_list: Dictionary = InputBindings.parse({"actions": {"jump": "Space"}})
	assert_false((bad_list["errors"] as PackedStringArray).is_empty(), "keys not in a list")


func test_apply_registers_actions() -> void:
	assert_eq(InputBindings.apply(), OK)
	var actions: Dictionary = _defaults()["actions"]
	for action: StringName in actions:
		assert_true(InputMap.has_action(action), "InputMap has '%s'" % action)
		assert_eq(InputMap.action_get_events(action).size(), (actions[action] as Array).size(), String(action))
