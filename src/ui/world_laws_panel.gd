class_name WorldLawsPanel
extends PanelContainer
## The rules of this universe, changed while it runs: the speed of light
## (real, slower as clearly marked fiction, or instant as in a classic
## sandbox), whether bodies collide, and how strong gravity is. Opened from
## the Tools tab; Esc or Back closes it.

signal closed

## Speeds of light offered, as how many times slower than real (INF:
## instant), with their names.
const LIGHT_SLOWDOWNS: Array[float] = [1.0, 10.0, 1000.0, INF]
const LIGHT_KEYS: Array[String] = ["LAW_LIGHT_REAL", "LAW_LIGHT_10", "LAW_LIGHT_1000", "LAW_LIGHT_INSTANT"]
const GRAVITY_SCALES: Array[float] = [0.5, 1.0, 2.0]

var simulation: Simulation

var _rows: Array[SettingRow] = []
var _row_box: VBoxContainer
var _note: Label


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(296, 0)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 6)
	add_child(content)
	var header: Label = Label.new()
	header.theme_type_variation = &"HeaderLabel"
	header.text = "LAWS_TITLE"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(header)
	_row_box = VBoxContainer.new()
	_row_box.add_theme_constant_override(&"separation", 3)
	content.add_child(_row_box)
	_note = Label.new()
	_note.theme_type_variation = &"KeyLabel"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	content.add_child(_note)
	var back: Button = Button.new()
	back.text = "MENU_BACK"
	back.custom_minimum_size = Vector2(80, 0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	content.add_child(back)


func open(sim: Simulation) -> void:
	simulation = sim
	if _rows.is_empty():
		_build_rows()
	for row: SettingRow in _rows:
		row.refresh()
	_refresh_note()
	show()
	_rows[0].grab_focus()


func close() -> void:
	hide()
	closed.emit()


func rows() -> Array[SettingRow]:
	return _rows


func note_text() -> String:
	return _note.text


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _build_rows() -> void:
	_add_row("LAW_LIGHT", PackedStringArray(LIGHT_KEYS), true,
		func() -> int: return _light_index(),
		func(index: int) -> void:
			simulation.set_light_slowdown(LIGHT_SLOWDOWNS[index])
			_refresh_note())
	_add_row("LAW_COLLISIONS", ["LAW_ON", "LAW_OFF"], true,
		func() -> int: return 0 if simulation.state.collisions_enabled else 1,
		func(index: int) -> void: simulation.set_collisions(index == 0))
	_add_row("LAW_GRAVITY", ["x0.5", "x1", "x2"], false,
		func() -> int: return GRAVITY_SCALES.find(simulation.state.g_scale),
		func(index: int) -> void: simulation.set_gravity_scale(GRAVITY_SCALES[index]))


func _light_index() -> int:
	for k: int in LIGHT_SLOWDOWNS.size():
		var speed: float = INF if is_inf(LIGHT_SLOWDOWNS[k]) else Units.C / LIGHT_SLOWDOWNS[k]
		if is_equal_approx(speed, simulation.light_speed) or (is_inf(speed) and is_inf(simulation.light_speed)):
			return k
	return 0


## Slower light is not how the universe works: say so plainly.
func _refresh_note() -> void:
	var slowdown: float = LIGHT_SLOWDOWNS[_light_index()]
	_note.text = "" if slowdown == 1.0 or is_inf(slowdown) else Format.tr_units("LAW_LIGHT_FICTION", Format.number(slowdown))
	_note.visible = not _note.text.is_empty()


func _add_row(name_key: String, options: PackedStringArray, translate: bool, read: Callable, write: Callable) -> void:
	var row: SettingRow = SettingRow.new()
	_row_box.add_child(row)
	row.setup(name_key, options, translate, read, write)
	_rows.append(row)
