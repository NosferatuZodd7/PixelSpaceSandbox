extends Node
## The game screen: a star system running through time, the space view, the
## big time counter, the god-powers toolbar and the power in use, inspect
## windows and the pause menu (Esc).
##
## Keys: Space pause, + and - speed, 1–0 speed presets, N jump to the next
## arrival of the news of a change, G follow the wave (smart time), Tab hide
## the interface, F1–F8 toolbar tabs; the view handles the camera keys.

const PRESET_PATH: String = "res://data/presets/solar_system.json"
const TITLE_SCENE: String = "res://scenes/main.tscn"
const SPEED_KEYS: String = "1234567890"

var simulation: Simulation
## The moment to start at (years since J2000.0); NAN means now.
var start_time: float = NAN
## The settings the pause menu edits. Defaults to the App's.
var settings: GameSettings
## Smart time: following the newest front, with time running so it crosses
## the view in a few seconds and easing down as it reaches a body.
var smart_time: bool = false

var _windows: Array[InspectWindow] = []
var _menu_open: bool = false
var _was_paused: bool = false

@onready var _view: SpaceView = $View
@onready var _powers: PowerTool = $Powers
@onready var _overlays: OverlayView = $Overlays
@onready var _ui: CanvasLayer = $UI
@onready var _root: Control = $UI/Root
@onready var _counter: TimeCounter = $UI/Root/TimeCounter
@onready var _time_controls: TimeControls = $UI/Root/TimeControls
@onready var _status: Label = $UI/Root/Status
@onready var _window_layer: Control = $UI/Root/Windows
@onready var _toolbar: Toolbar = $UI/Root/Toolbar
@onready var _pause_menu: PauseMenu = $UI/Root/Center/PauseMenu
@onready var _settings_panel: SettingsPanel = $UI/Root/Center/SettingsPanel
@onready var _laws_panel: WorldLawsPanel = $UI/Root/Center/WorldLawsPanel
@onready var _notifications: NotificationFeed = $UI/Root/Notifications
@onready var _timeline_bar: TimelineBar = $UI/Root/TimelineBar


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
	simulation.timeline = Timeline.new()
	_view.setup(simulation)
	_view.selection_changed.connect(_on_selection_changed)
	_powers.setup(simulation, _view)
	_overlays.setup(simulation, _view)
	for overlay: StringName in _toolbar.overlays:
		set_overlay(overlay, _toolbar.overlays[overlay])
	_toolbar.overlay_toggled.connect(set_overlay)
	_toolbar.laws_requested.connect(func() -> void: _laws_panel.open(simulation))
	_timeline_bar.simulation = simulation
	_timeline_bar.rewound.connect(_after_restore)
	_notifications.focus_requested.connect(func(body: int) -> void:
		_view.select(body)
		_view.follow(body))
	_toolbar.power_changed.connect(_powers.set_power)
	_powers.cancelled.connect(_toolbar.cancel_power)
	_counter.clock = simulation.clock
	_counter.simulation = simulation
	_counter.refresh()
	_time_controls.clock = simulation.clock
	_time_controls.changed.connect(_counter.refresh)
	_time_controls.next_arrival_requested.connect(jump_to_next_arrival)
	_time_controls.follow_wave_toggled.connect(set_smart_time)
	_pause_menu.resume_requested.connect(close_menu)
	_pause_menu.settings_requested.connect(_open_settings)
	_pause_menu.title_requested.connect(func() -> void: get_tree().change_scene_to_file(TITLE_SCENE))
	_settings_panel.closed.connect(func() -> void: _pause_menu.open())


func _process(delta: float) -> void:
	if not _menu_open:
		_steer_time(delta)
		simulation.advance(delta)
		simulation.timeline.tick(simulation, delta)
	_time_controls.news_travelling = not simulation.fronts.is_empty()
	_announce_events()
	_update_status()


## Turns what happened in the simulation into notices.
func _announce_events() -> void:
	var system: StarSystem = simulation.system
	for event: Dictionary in simulation.events:
		var body: int = event["body"]
		var who: String = Format.body_name(system.body(body))
		match str(event["kind"]):
			"merge":
				_notifications.push(tr("NOTE_MERGE") % [who, Format.body_name(system.body(event["other"]))], body)
			"disrupt":
				_notifications.push(tr("NOTE_TORN") % [Format.body_name(system.body(event["other"])), who], body)
			"impact":
				var particle: int = event["particle"]
				var named: String = ""
				for key: String in simulation.particle_names:
					if simulation.particle_names[key] == particle:
						named = tr(key)
				if not named.is_empty():
					_notifications.push(tr("NOTE_IMPACT_NAMED") % [named, who], body)
				elif simulation.state.p_kind[particle] == Gravity.ParticleKind.COMET:
					_notifications.push(Format.tr_units("NOTE_IMPACT_COMET", who), body)
				else:
					_notifications.push(Format.tr_units("NOTE_IMPACT", who), body)
	simulation.events.clear()


## After going back in time: nothing travels any more, so smart time and
## the power in use stop.
func _after_restore() -> void:
	set_smart_time(false)
	_toolbar.cancel_power()
	_counter.refresh()


## Shows or hides a layer of the view (from the Tools tab).
func set_overlay(overlay: StringName, on: bool) -> void:
	_view.overlays[overlay] = on
	if overlay == &"ghosts":
		simulation.keep_alternative = on


## Runs time on to the moment the news of a change next reaches a body,
## and pauses there.
func jump_to_next_arrival() -> void:
	set_smart_time(false)
	simulation.jump_to_next_arrival()
	simulation.clock.paused = true
	_counter.refresh()


func set_smart_time(on: bool) -> void:
	smart_time = on and not simulation.fronts.is_empty()
	_time_controls.show_following(smart_time)
	if smart_time:
		simulation.clock.paused = false
		simulation.clock.steer(simulation.clock.speed())
		_view.follow(-1)
	else:
		simulation.clock.release()
	_counter.refresh()


func _steer_time(delta: float) -> void:
	if not smart_time:
		return
	var clock: SimClock = simulation.clock
	# Choosing a speed or pausing hands time back to the player; so does the
	# wave passing everything.
	if simulation.fronts.is_empty() or not clock.is_steered() or clock.paused:
		set_smart_time(false)
		return
	var front: WaveFront = simulation.fronts.back()
	var camera: SpaceCamera = _view.camera
	camera.look_at(front.origin_x, front.origin_y)
	var radius: float = front.radius_at(clock.time)
	var height: float = camera.viewport_size.y
	if radius > 0.0 and radius * camera.scale > 0.4 * height:
		camera.set_scale_now(0.4 * height / radius)
	var wanted: float = SmartTime.wave_speed(0.5 * height / camera.scale)
	var next: Dictionary = simulation.next_arrival(true)
	if not next.is_empty():
		wanted = minf(wanted, SmartTime.arrival_speed((float(next["time"]) - clock.time) * Units.YEAR_SECONDS))
	clock.steer(SmartTime.ease_towards(clock.speed(), wanted, delta))


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
	elif event.is_action_pressed(&"next_arrival"):
		jump_to_next_arrival()
	elif event.is_action_pressed(&"smart_time"):
		set_smart_time(not smart_time)
	elif event.is_action_pressed(&"undo"):
		if simulation.timeline.undo(simulation):
			_after_restore()
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
		parts.append(Format.tr_units("VIEW_FOLLOWING", Format.body_name(simulation.system.body(_view.followed))))
	if _view.true_scale:
		parts.append(tr("VIEW_TRUE_SCALE"))
	if smart_time:
		parts.append(tr("VIEW_FOLLOWING_WAVE"))
	_status.text = "  ·  ".join(parts)
