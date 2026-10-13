extends TestCase
## The game screen: the Solar System on today's date, time controls,
## selecting and inspecting bodies, pinned windows, the pause menu, the
## toolbar and the camera, driven by real input events.

const SPACE_SCENE: String = "res://scenes/space.tscn"
const SETTINGS_PATH: String = "user://test_space_settings.cfg"
const START: String = "2026-10-13T12:00:00"

var _screen: Node
var _view: SpaceView


func before_each() -> void:
	InputBindings.apply()
	TranslationServer.set_locale("en")
	_screen = (load(SPACE_SCENE) as PackedScene).instantiate()
	_screen.set(&"start_time", Units.years_from_unix(Time.get_unix_time_from_datetime_string(START)))
	_screen.set(&"settings", GameSettings.new(SETTINGS_PATH))
	tree.root.add_child(_screen)
	_view = _screen.get_node("View")
	await wait_frames(3)


func after_each() -> void:
	_screen.queue_free()
	await wait_frames(2)
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	TranslationServer.set_locale("en")


func _simulation() -> Simulation:
	return _screen.get(&"simulation")


func _index(id: StringName) -> int:
	return _simulation().system.index_of(id)


func _action(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	tree.root.push_input(event)


func _click(at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = button
		event.position = at
		event.global_position = at
		event.pressed = pressed
		tree.root.push_input(event)


func _windows() -> Array[InspectWindow]:
	return _screen.call(&"inspect_windows")


func test_starts_on_the_given_date_with_the_solar_system() -> void:
	assert_eq(_simulation().system.size(), 33, "Sun, planets, dwarf planets and moons")
	var counter: TimeCounter = _screen.get_node("UI/Root/TimeCounter")
	assert_eq(counter.date_text(), "13 OCT 2026  12:00")
	assert_eq(counter.speed_text(), "x1  ·  real time")


func test_time_runs_pauses_and_changes_speed() -> void:
	var clock: SimClock = _simulation().clock
	var before: float = clock.time
	await wait_frames(3)
	assert_true(clock.time > before, "time runs")
	_action(&"pause")
	await wait_frames(1)
	assert_true(clock.paused, "Space pauses")
	var paused_at: float = clock.time
	await wait_frames(3)
	assert_eq(clock.time, paused_at, "paused time stands still")
	_action(&"speed_4")
	await wait_frames(1)
	assert_eq(clock.speed(), 86400.0, "4 is one day per second")
	assert_false(clock.paused, "choosing a speed resumes")
	_action(&"speed_up")
	await wait_frames(1)
	assert_eq(clock.speed(), 604800.0, "+ goes one step faster")
	_action(&"speed_down")
	_action(&"speed_down")
	await wait_frames(1)
	assert_eq(clock.speed(), 21600.0, "- goes slower")


func test_clicking_a_planet_opens_an_inspect_window() -> void:
	var earth: int = _index(&"earth")
	assert_true(_view.is_shown(earth), "Earth drawn at the start")
	_click(_view.screen_position(earth))
	await wait_frames(2)
	assert_eq(_view.selected, earth, "clicked Earth")
	assert_eq(_windows().size(), 1, "one window")
	var rows: Array[PackedStringArray] = _windows()[0].rows()
	assert_eq(rows[0], PackedStringArray(["INSPECT_KIND", "Planet"]))
	var labels: PackedStringArray = []
	for row: PackedStringArray in rows:
		labels.append(row[0])
	for expected: String in ["INSPECT_MASS", "INSPECT_GRAVITY", "INSPECT_LIGHT_TIME", "INSPECT_PERIOD", "INSPECT_IN_HABITABLE_ZONE"]:
		assert_true(labels.has(expected), "shows %s" % expected)
	_click(Vector2(10, 60))
	await wait_frames(2)
	assert_eq(_view.selected, -1, "clicking empty space deselects")
	assert_eq(_windows().size(), 0, "and closes the window")


func test_pinned_windows_stay_open() -> void:
	_view.select(_index(&"earth"))
	await wait_frames(1)
	_windows()[0].set_pinned(true)
	_view.select(_index(&"mars"))
	await wait_frames(1)
	assert_eq(_windows().size(), 2, "a second window for Mars")
	_view.select(-1)
	await wait_frames(2)
	assert_eq(_windows().size(), 1, "the pinned Earth window stays")
	assert_eq(_windows()[0].body_index, _index(&"earth"))


func test_escape_opens_the_pause_menu_and_stops_time() -> void:
	_action(&"ui_cancel")
	await wait_frames(1)
	assert_true(_screen.call(&"is_menu_open"), "Esc opens the menu")
	assert_true((_screen.get_node("UI/Root/Center/PauseMenu") as Control).visible, "menu shown")
	var clock: SimClock = _simulation().clock
	var frozen: float = clock.time
	await wait_frames(3)
	assert_eq(clock.time, frozen, "time stops while the menu is open")
	_action(&"ui_cancel")
	await wait_frames(1)
	assert_false(_screen.call(&"is_menu_open"), "Esc closes it again")
	await wait_frames(2)
	assert_true(clock.time > frozen, "time runs again")


func test_wheel_zooms_towards_the_cursor() -> void:
	var jupiter: int = _index(&"jupiter")
	_view.camera.set_scale_now(30.0)
	await wait_frames(1)
	var at: Vector2 = _view.screen_position(jupiter)
	for i: int in 3:
		_click(at, MOUSE_BUTTON_WHEEL_UP)
	await wait_until(func() -> bool: return not _view.camera.is_zooming(), 5.0)
	await wait_frames(1)
	assert_almost_eq(_view.camera.scale, 30.0 * pow(SpaceView.ZOOM_STEP, 3), 1e-6, "zoomed in three steps")
	assert_true(_view.screen_position(jupiter).distance_to(at) < 3.0, "Jupiter stayed under the cursor")


func test_moons_appear_when_zooming_in() -> void:
	var earth: int = _index(&"earth")
	var moon: int = _index(&"moon")
	assert_false(_view.is_shown(moon), "the Moon hides inside the Earth's dot from afar")
	_view.select(earth)
	_view.follow(earth)
	_view.camera.set_scale_now(5.0e4)
	await wait_frames(2)
	assert_true(_view.is_shown(moon), "close up the Moon appears")
	assert_true(_view.screen_position(earth).distance_to(Vector2(320, 180)) < 1.5, "following keeps the Earth centred")


func test_true_scale_shows_real_sizes() -> void:
	var earth: int = _index(&"earth")
	var drawn: int = _view.display_radius(earth)
	_action(&"true_scale")
	await wait_frames(1)
	assert_true(_view.true_scale, "T toggles true scale")
	assert_true(_view.display_radius(earth) < drawn, "the Earth shrinks to its real size")


func test_toolbar_and_interface_keys() -> void:
	var toolbar: Toolbar = _screen.get_node("UI/Root/Toolbar")
	assert_eq(toolbar.current, toolbar.tabs.size() - 1, "starts on Inspect")
	_action(&"tab_1")
	await wait_frames(1)
	assert_eq(toolbar.current, 0, "F1 selects Cosmos")
	assert_eq(toolbar.content_text(), "These powers arrive in milestone 2.")
	_action(&"toggle_ui")
	await wait_frames(1)
	assert_false((_screen.get_node("UI") as CanvasLayer).visible, "Tab hides the interface")
	_action(&"toggle_ui")
	await wait_frames(1)
	assert_true((_screen.get_node("UI") as CanvasLayer).visible, "and shows it again")
