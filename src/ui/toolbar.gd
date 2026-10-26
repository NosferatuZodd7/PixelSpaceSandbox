class_name Toolbar
extends PanelContainer
## The god-powers toolbar along the bottom: a row of tabs from
## data/power_tabs.json and, below them, the selected tab's powers from
## data/powers.json as pixel icons, with the chosen power's name and how to
## use it on one line (and in the icon's tooltip). Tabs whose powers arrive
## later are dimmed and say in which milestone. Overlay buttons switch a
## layer of the view on and off on their own; the world laws button opens
## its panel; every other power is chosen one at a time.

signal tab_changed(index: int)
## The chosen power changed; empty when none is chosen.
signal power_changed(power: Dictionary)
signal overlay_toggled(overlay: StringName, on: bool)
signal laws_requested

const TABS_PATH: String = "res://data/power_tabs.json"

var tabs: Array[Dictionary] = []
var current: int = -1
## Which overlays are shown, starting as data/powers.json says.
var overlays: Dictionary[StringName, bool] = {}

var _buttons: Array[Button] = []
var _powers: Array[Dictionary] = []
var _power: Dictionary = {}
var _power_row: HBoxContainer
var _power_buttons: Dictionary[String, Button] = {}
var _power_group: ButtonGroup
## The chosen (or described) power's name, and how to use it or the tab's hint.
var _name: Label
var _content: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABS_PATH))
	if data is Dictionary and (data as Dictionary).get("tabs") is Array:
		for tab: Variant in (data as Dictionary)["tabs"]:
			if tab is Dictionary:
				tabs.append(tab)
	var loaded: Dictionary = PowerCatalog.load_file()
	for message: String in loaded["errors"] as PackedStringArray:
		push_error("Powers: %s" % message)
	_powers = loaded["powers"]
	for power: Dictionary in _powers:
		if power["action"] == "overlay":
			overlays[StringName(str(power["overlay"]))] = bool(power.get("on", false))
	# From the shared theme: the screen sets it on its UI only after its children are ready.
	var panel: StyleBoxFlat = UiTheme.shared().get_stylebox(&"panel", &"PanelContainer").duplicate()
	panel.content_margin_left = 6
	panel.content_margin_right = 6
	panel.content_margin_top = 4
	panel.content_margin_bottom = 4
	add_theme_stylebox_override(&"panel", panel)
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
		button.theme_type_variation = &"LockedTab" if _is_locked(tabs[i]) else &"TabButton"
		button.pressed.connect(select.bind(i))
		row.add_child(button)
		_buttons.append(button)
	var content: HBoxContainer = HBoxContainer.new()
	content.add_theme_constant_override(&"separation", 6)
	column.add_child(content)
	_power_row = HBoxContainer.new()
	_power_row.add_theme_constant_override(&"separation", 1)
	content.add_child(_power_row)
	_power_group = ButtonGroup.new()
	_power_group.allow_unpress = true
	_name = Label.new()
	_name.theme_type_variation = &"KeyLabel"
	_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	content.add_child(_name)
	_content = Label.new()
	_content.theme_type_variation = &"DimLabel"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_content.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(_content)
	select(tabs.size() - 1)


func select(index: int) -> void:
	if index < 0 or index >= tabs.size():
		return
	cancel_power()
	current = index
	_buttons[index].button_pressed = true
	_build_power_row()
	_refresh()
	tab_changed.emit(index)


func tab_button(index: int) -> Button:
	return _buttons[index]


## What the line beside the icons says: "name  ·  how to use it", or the
## tab's hint.
func content_text() -> String:
	if not _name.visible:
		return _content.text
	return "%s  %s" % [_name.text, _content.text]


## The ids of the current tab's powers, in order.
func power_ids() -> PackedStringArray:
	return PackedStringArray(_power_buttons.keys())


func power_button(id: String) -> Button:
	return _power_buttons.get(id)


## The chosen power (an entry of data/powers.json), or empty.
func current_power() -> Dictionary:
	return _power


func choose_power(id: String) -> void:
	var button: Button = _power_buttons.get(id)
	if button != null:
		button.button_pressed = true
		_set_power(id)


func cancel_power() -> void:
	if _power.is_empty():
		return
	var pressed: BaseButton = _power_group.get_pressed_button()
	if pressed != null:
		pressed.set_pressed_no_signal(false)
	_set_power("")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _content != null:
		_refresh()
		_describe_buttons()


func _build_power_row() -> void:
	for child: Node in _power_row.get_children():
		_power_row.remove_child(child)
		child.queue_free()
	_power_buttons.clear()
	var tab_id: String = str(tabs[current].get("id", ""))
	for power: Dictionary in _powers:
		if str(power["tab"]) != tab_id:
			continue
		var id: String = power["id"]
		var button: Button = Button.new()
		button.icon = PixelIcons.texture(StringName(str(power["icon"])))
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.set_meta(&"power", power)
		button.focus_mode = Control.FOCUS_NONE
		button.theme_type_variation = &"IconButton"
		match str(power["action"]):
			"overlay":
				var overlay: StringName = StringName(str(power["overlay"]))
				button.toggle_mode = true
				button.button_pressed = overlays.get(overlay, false)
				button.toggled.connect(func(on: bool) -> void:
					overlays[overlay] = on
					_describe(power)
					overlay_toggled.emit(overlay, on))
			"laws":
				button.pressed.connect(func() -> void: laws_requested.emit())
			_:
				button.toggle_mode = true
				button.button_group = _power_group
				button.toggled.connect(func(on: bool) -> void: _set_power(id if on else ""))
		_power_row.add_child(button)
		_power_buttons[id] = button
	_power_row.visible = not _power_buttons.is_empty()
	_content.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if _power_row.visible else HORIZONTAL_ALIGNMENT_CENTER
	_describe_buttons()


## Each icon's tooltip: the power's name and how to use it, and for the
## powers that throw, that releasing on a body aims at it.
func _describe_buttons() -> void:
	for button: Button in _power_buttons.values():
		var power: Dictionary = button.get_meta(&"power")
		var text: String = "%s\n%s" % [tr(str(power["name_key"])), tr(str(power["hint_key"]))]
		if power["action"] == "place" or power["action"] == "fling":
			text += "\n" + tr("POWER_AIM_HINT")
		button.tooltip_text = text


## A tab with no powers yet and nothing else to say: its powers come later.
func _is_locked(tab: Dictionary) -> bool:
	if tab.has("hint_key"):
		return false
	for power: Dictionary in _powers:
		if power["tab"] == tab.get("id"):
			return false
	return true


func _set_power(id: String) -> void:
	var chosen: Dictionary = {}
	for power: Dictionary in _powers:
		if power["id"] == id:
			chosen = power
	if chosen == _power:
		return
	_power = chosen
	_refresh()
	power_changed.emit(_power)


## Shows a power's name and how to use it, without choosing it.
func _describe(power: Dictionary) -> void:
	if _power.is_empty():
		_show(power)


func _show(power: Dictionary) -> void:
	_name.text = tr(str(power["name_key"]))
	_name.visible = true
	_content.text = "·  " + tr(str(power["hint_key"]))


func _refresh() -> void:
	if current == -1:
		return
	var tab: Dictionary = tabs[current]
	if not _power.is_empty():
		_show(_power)
		return
	_name.visible = false
	if tab.has("hint_key"):
		_content.text = tr(str(tab["hint_key"]))
	else:
		_content.text = Format.tr_units("TAB_COMING", str(int(tab.get("milestone", 1))))
