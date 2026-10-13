extends Node
## The game screen: a star system running through time, the space view, the
## big time counter, the god-powers toolbar, inspect windows and the pause
## menu (Esc).
##
## Keys: Space pause, + and - speed, 1–0 speed presets, Tab hide the
## interface, F1–F8 toolbar tabs; the view handles the camera keys.

const PRESET_PATH: String = "res://data/presets/solar_system.json"
const TITLE_SCENE: String = "res://scenes/main.tscn"
const SPEED_KEYS: String = "1234567890"

var simulation: Simulation
## The moment to start at (years since J2000.0); NAN means now.
var start_time: float = NAN
## The settings the pause menu edits. Defaults to the App's.
var settings: GameSettings

var _windows: Array[InspectWindow] = []
var _menu_open: bool = false
var _was_paused: bool = false

@onready var _view: SpaceView = $View
@onready var _ui: CanvasLayer = $UI
@onready var _root: Control = $UI/Root
@onready var _counter: TimeCounter = $UI/Root/TimeCounter
@onready var _status: Label = $UI/Root/Status
@onready var _window_layer: Control = $UI/Root/Windows
@onready var _toolbar: Toolbar = $UI/Root/Toolbar
@onready var _pause_menu: PauseMenu = $UI/Root/Center/PauseMenu
@onready var _settings_panel: SettingsPanel = $UI/Root/Center/SettingsPanel


func _ready() -> void:
	if settings == null:
		settings = App.settings
	_root.theme = UiTheme.shared()
	var loaded: Dictionary = PresetLoader.load_file(PRESET_PATH)
	var errors: PackedStringArray = loaded["errors"]
	for message: String in errors:
		push_error("Solar System preset: %s" % message)
	var t: float = start_time
	if is_nan(t):
		t = Units.years_from_unix(Time.get_unix_time_from_system())
	simulation = Simulation.new(loaded["system"], SimClock.load_default(t))
	_view.setup(simulation)
	_view.selection_changed.connect(_on_selection_changed)
	_counter.clock = simulation.clock
	_counter.refresh()
	_pause_menu.resume_requested.connect(close_menu)
	_pause_menu.settings_requested.connect(_open_settings)
	_pause_menu.title_requested.connect(func() -> void: get_tree().change_scene_to_file(TITLE_SCENE))
	_settings_panel.closed.connect(func() -> void: _pause_menu.open())


func _process(delta: float) -> void:
	if not _menu_open:
		simulation.advance(delta)
	_update_status()


func is_menu_open() -> bool:
	return _menu_open


func open_menu() -> void:
	_menu_open = true
	_was_paused = simulation.clock.paused
	simulation.clock.paused = true
	_view.accepts_input = false
	_ui.visible = true
	_pause_menu.open()
	_counter.refresh()


func close_menu() -> void:
	_menu_open = false
	simulation.clock.paused = _was_paused
	_view.accepts_input = true
	_pause_menu.hide()
	_settings_panel.hide()
	_counter.refresh()


func inspect_windows() -> Array[InspectWindow]:
	return _windows


func _open_settings() -> void:
	_pause_menu.hide()
	_settings_panel.open(settings)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		if _menu_open:
			if not _settings_panel.visible:
				close_menu()
		else:
			open_menu()
		get_viewport().set_input_as_handled()
		return
	if _menu_open:
		return
	var clock: SimClock = simulation.clock
	if event.is_action_pressed(&"pause"):
		clock.toggle_pause()
	elif event.is_action_pressed(&"speed_up", true):
		clock.faster()
		clock.paused = false
	elif event.is_action_pressed(&"speed_down", true):
		clock.slower()
		clock.paused = false
	elif event.is_action_pressed(&"toggle_ui"):
		_ui.visible = not _ui.visible
	else:
		for key: String in SPEED_KEYS:
			if event.is_action_pressed(StringName("speed_" + key)):
				clock.use_preset(key)
				_counter.refresh()
				get_viewport().set_input_as_handled()
				return
		for tab: int in _toolbar.tabs.size():
			if event.is_action_pressed(StringName("tab_%d" % (tab + 1))):
				_toolbar.select(tab)
				get_viewport().set_input_as_handled()
				return
		return
	_counter.refresh()
	get_viewport().set_input_as_handled()


## Clicking a body shows it in the unpinned window (opening one if needed);
## pinned windows stay as they are. Clicking empty space closes the unpinned one.
func _on_selection_changed(index: int) -> void:
	var current: InspectWindow = null
	for window: InspectWindow in _windows:
		if not window.pinned:
			current = window
	if index == -1:
		if current != null:
			current.close_window()
		return
	if current == null:
		current = InspectWindow.new()
		_window_layer.add_child(current)
		current.closed.connect(_on_window_closed)
		current.position = Vector2(_root.size.x - InspectWindow.WIDTH - 6 - 10 * _windows.size(), 40 + 10 * _windows.size())
		_windows.append(current)
	current.show_body(simulation, index)
	current.move_to_front()


func _on_window_closed(window: InspectWindow) -> void:
	_windows.erase(window)
	if not window.pinned and _view.selected == window.body_index:
		_view.select(-1)


func _update_status() -> void:
	var parts: PackedStringArray = []
	if _view.followed != -1:
		parts.append(Format.tr_units("VIEW_FOLLOWING", tr(simulation.system.body(_view.followed).name_key)))
	if _view.true_scale:
		parts.append(tr("VIEW_TRUE_SCALE"))
	_status.text = "  ·  ".join(parts)
