class_name SettingRow
extends HBoxContainer
## One setting: its name, then its value between "<" and ">" arrows.
##
## The row takes keyboard focus as a whole: left and right (or Enter, or a
## click on an arrow) change the value, wrapping around.

const VALUE_WIDTH: int = 120

var _options: PackedStringArray = []
var _read: Callable
var _write: Callable
var _value_label: Label


## name_key: translation key of the setting's name. options: the values'
## texts (translation keys when translate is true). read returns the current
## option index; write receives the new index.
func setup(name_key: String, options: PackedStringArray, translate: bool, read: Callable, write: Callable) -> void:
	_options = options
	_read = read
	_write = write
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_constant_override(&"separation", 6)

	var name_label: Label = Label.new()
	name_label.text = name_key
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(name_label)
	add_child(_arrow("<", -1))
	_value_label = Label.new()
	_value_label.custom_minimum_size = Vector2(VALUE_WIDTH, 0)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not translate:
		_value_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_value_label)
	add_child(_arrow(">", 1))
	mouse_entered.connect(grab_focus)
	refresh()


## Shows the current value (call after the setting changed elsewhere).
func refresh() -> void:
	var index: int = _read.call()
	_value_label.text = _options[clampi(index, 0, _options.size() - 1)]


## Moves the value by the given number of options, wrapping around.
func step(delta: int) -> void:
	var index: int = posmod(int(_read.call()) + delta, _options.size())
	_write.call(index)
	refresh()


func value_text() -> String:
	return _value_label.text


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left", true):
		step(-1)
		accept_event()
	elif event.is_action_pressed(&"ui_right", true) or event.is_action_pressed(&"ui_accept"):
		step(1)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
		queue_redraw()


func _draw() -> void:
	if has_focus():
		var area: Rect2 = Rect2(Vector2(-3, -1), size + Vector2(6, 2))
		draw_rect(area, Palette.color(&"ui_panel_light"))
		UiTheme.draw_frame(self, area, Palette.color(&"ui_accent"))


func _arrow(text: String, delta: int) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.theme_type_variation = &"ArrowButton"
	button.focus_mode = Control.FOCUS_NONE
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.pressed.connect(func() -> void:
		step(delta)
		grab_focus()
	)
	return button
