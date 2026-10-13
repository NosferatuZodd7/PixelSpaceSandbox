class_name PauseMenu
extends PanelContainer
## The in-game menu (Esc): continue, settings, back to the title, quit.

signal resume_requested
signal settings_requested
signal title_requested

var _first: Button


func _ready() -> void:
	custom_minimum_size = Vector2(160, 0)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 4)
	add_child(column)
	var header: Label = Label.new()
	header.text = "PAUSE_TITLE"
	header.theme_type_variation = &"HeaderLabel"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(header)
	_first = _button(column, "MENU_CONTINUE", func() -> void: resume_requested.emit())
	_button(column, "MENU_SETTINGS", func() -> void: settings_requested.emit())
	_button(column, "MENU_TITLE", func() -> void: title_requested.emit())
	_button(column, "MENU_QUIT", func() -> void: get_tree().quit())


func open() -> void:
	show()
	_first.grab_focus()


func _button(column: VBoxContainer, text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.pressed.connect(action)
	column.add_child(button)
	return button
