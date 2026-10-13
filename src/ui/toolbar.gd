class_name Toolbar
extends PanelContainer
## The god-powers toolbar along the bottom: a row of tabs from
## data/power_tabs.json and the selected tab's powers below them. In
## milestone 1 the tabs are there and say when their powers arrive.

signal tab_changed(index: int)

const TABS_PATH: String = "res://data/power_tabs.json"

var tabs: Array[Dictionary] = []
var current: int = -1

var _buttons: Array[Button] = []
var _content: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABS_PATH))
	if data is Dictionary and (data as Dictionary).get("tabs") is Array:
		for tab: Variant in (data as Dictionary)["tabs"]:
			if tab is Dictionary:
				tabs.append(tab)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 3)
	add_child(column)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 2)
	column.add_child(row)
	var group: ButtonGroup = ButtonGroup.new()
	for i: int in tabs.size():
		var button: Button = Button.new()
		button.text = str(tabs[i].get("name_key", "?"))
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(select.bind(i))
		row.add_child(button)
		_buttons.append(button)
	_content = Label.new()
	_content.theme_type_variation = &"DimLabel"
	_content.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	column.add_child(_content)
	select(tabs.size() - 1)


func select(index: int) -> void:
	if index < 0 or index >= tabs.size():
		return
	current = index
	_buttons[index].button_pressed = true
	_refresh()
	tab_changed.emit(index)


func content_text() -> String:
	return _content.text


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _content != null:
		_refresh()


func _refresh() -> void:
	if current == -1:
		return
	var tab: Dictionary = tabs[current]
	var milestone: int = int(tab.get("milestone", 1))
	if tab.has("hint_key"):
		_content.text = tr(str(tab["hint_key"]))
	else:
		_content.text = Format.tr_units("TAB_COMING", str(milestone))
