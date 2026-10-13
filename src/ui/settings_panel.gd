class_name SettingsPanel
extends PanelContainer
## The settings screen. Every change is applied and saved at once; there is
## no "apply" button to forget.

## Emitted when the player leaves the screen (Back button or Esc).
signal closed

var _settings: GameSettings
var _rows: Array[SettingRow] = []

@onready var _row_box: VBoxContainer = $Content/Rows
@onready var _back: Button = $Content/Back


func _ready() -> void:
	_back.pressed.connect(close)


## Shows the screen for these settings and focuses the first row.
func open(settings: GameSettings) -> void:
	if _settings != settings:
		if _settings != null:
			_settings.changed.disconnect(_refresh)
		_settings = settings
		_settings.changed.connect(_refresh)
		_build_rows()
	_refresh()
	show()
	if not _rows.is_empty():
		_rows[0].grab_focus()


func close() -> void:
	hide()
	closed.emit()


func rows() -> Array[SettingRow]:
	return _rows


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _build_rows() -> void:
	for row: SettingRow in _rows:
		row.queue_free()
	_rows.clear()

	var locales: PackedStringArray = GameSettings.available_locales()
	var names: PackedStringArray = []
	for code: String in locales:
		names.append(GameSettings.language_name(code))
	_add_row("SETTING_LANGUAGE", names, false,
		func() -> int: return locales.find(_settings.locale),
		func(index: int) -> void: _settings.change(&"locale", locales[index]))
	_add_row("SETTING_DISPLAY", ["DISPLAY_WINDOWED", "DISPLAY_FULLSCREEN"], true,
		func() -> int: return 1 if _settings.fullscreen else 0,
		func(index: int) -> void: _settings.change(&"fullscreen", index == 1))
	_add_row("SETTING_VSYNC", ["VSYNC_OFF", "VSYNC_ON"], true,
		func() -> int: return 1 if _settings.vsync else 0,
		func(index: int) -> void: _settings.change(&"vsync", index == 1))


func _add_row(name_key: String, options: PackedStringArray, translate: bool, read: Callable, write: Callable) -> void:
	var row: SettingRow = SettingRow.new()
	_row_box.add_child(row)
	row.setup(name_key, options, translate, read, write)
	_rows.append(row)


func _refresh() -> void:
	for row: SettingRow in _rows:
		row.refresh()
