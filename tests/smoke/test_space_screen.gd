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
	assert_eq(counter.date_text(), "13 OCT 2026", "the date (hours and minutes would flicker at this speed)")
	assert_eq(counter.speed_text(), "x86,400  ·  1 day per second", "starts at one day per second, so things visibly move")


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


func test_the_time_buttons_pause_and_change_speed() -> void:
	var clock: SimClock = _simulation().clock
	var controls: TimeControls = _screen.get_node("UI/Root/TimeControls")
	_click(controls.pause_button().get_global_rect().get_center())
	await wait_frames(1)
	assert_true(clock.paused, "the pause button pauses")
	_click(controls.pause_button().get_global_rect().get_center())
	await wait_frames(1)
	assert_false(clock.paused, "and resumes")
	var speed: float = clock.speed()
	_click(controls.faster_button().get_global_rect().get_center())
	await wait_frames(1)
	assert_true(clock.speed() > speed, "faster")
	_click(controls.slower_button().get_global_rect().get_center())
	_click(controls.slower_button().get_global_rect().get_center())
	await wait_frames(1)
	assert_true(clock.speed() < speed, "slower")


func test_planets_keep_spinning_when_time_runs_fast() -> void:
	var earth: int = _index(&"earth")
	var sprite: BodySprite = _view.get_node("Bodies").get_child(earth)
	_action(&"speed_7")
	await wait_frames(2)
	assert_true(sprite.visible, "the Earth is on screen")
	var before: float = (sprite.material as ShaderMaterial).get_shader_parameter(&"spin")
	await wait_frames(3)
	var after: float = (sprite.material as ShaderMaterial).get_shader_parameter(&"spin")
	assert_ne(after, before, "the Earth still turns (not frozen) at one year per second")


func test_the_counter_says_when_the_game_cannot_keep_up() -> void:
	var simulation: Simulation = _simulation()
	simulation.leave_pristine()
	simulation.max_steps_per_frame = 1
	_action(&"speed_7")
	await wait_frames(4)
	var counter: TimeCounter = _screen.get_node("UI/Root/TimeCounter")
	assert_true(simulation.lagging, "the simulation is behind")
	var says_so: bool = await wait_until(func() -> bool: return counter.speed_text().contains(tr("TIME_LAGGING")), 1.0)
	assert_true(says_so, "the counter says so: %s" % counter.speed_text())


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
	# Empty space, beside the window (which keeps clear of the Earth).
	var empty: Vector2 = Vector2(10, 60)
	if _windows()[0].get_global_rect().grow(2.0).has_point(empty):
		empty = Vector2(630, 60)
	_click(empty)
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


func test_bodies_grow_a_little_when_zooming_in() -> void:
	var earth: int = _index(&"earth")
	var far: int = _view.display_radius(earth)
	_view.follow(earth)
	_view.camera.set_scale_now(5.0e4)
	await wait_frames(2)
	var near: int = _view.display_radius(earth)
	assert_true(near > far, "close up the Earth is drawn bigger: %d px, %d from afar" % [near, far])
	assert_true(near <= far * 2, "but at most twice as big")
	assert_true(_view.is_shown(_index(&"moon")), "and the Moon still shows beside it")


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
	_action(&"toggle_ui")
	await wait_frames(1)
	assert_false((_screen.get_node("UI") as CanvasLayer).visible, "Tab hides the interface")
	_action(&"toggle_ui")
	await wait_frames(1)
	assert_true((_screen.get_node("UI") as CanvasLayer).visible, "and shows it again")


func test_belts_and_the_oort_cloud_are_drawn() -> void:
	_simulation().clock.paused = true
	await wait_frames(2)
	var shown: Dictionary = _view.particles_drawn()
	assert_true(int(shown.get(Gravity.ParticleKind.ASTEROID, 0)) > 300, "the asteroid belt shows as dots (%s)" % shown)
	assert_eq(int(shown.get(Gravity.ParticleKind.OORT, 0)), 0, "the Oort cloud is far off screen")
	_view.camera.set_scale_now(0.005)
	await wait_frames(2)
	shown = _view.particles_drawn()
	assert_true(int(shown.get(Gravity.ParticleKind.OORT, 0)) > 100, "zoomed far out, the Oort cloud appears (%s)" % shown)


func test_a_comet_near_the_sun_grows_a_tail_away_from_it() -> void:
	var simulation: Simulation = _simulation()
	var halley: int = simulation.particle_named("BODY_HALLEY")
	assert_eq(_view.comet_tail(halley), Vector2.ZERO, "far out, Halley has no tail")
	# Halley's next perihelion: late July 2061.
	simulation.set_time(Units.years_from_unix(Time.get_unix_time_from_datetime_string("2061-07-28T00:00:00")))
	simulation.clock.paused = true
	await wait_frames(2)
	var tail: Vector2 = _view.comet_tail(halley)
	assert_true(tail.length() > 10.0, "near the Sun its tail is long (%s px)" % tail.length())
	var head: Vector2 = Vector2(simulation.state.p_view[halley * 3], -simulation.state.p_view[halley * 3 + 1])
	assert_true(tail.normalized().dot(head.normalized()) > 0.95, "and points away from the Sun")


## Rings follow a planet drawn larger than life, but a ring far out from a
## tiny body (a planet torn apart around a black hole) stays near its disc
## instead of filling the screen.
func test_rings_far_out_stay_near_the_drawn_body() -> void:
	var simulation: Simulation = _simulation()
	simulation.clock.paused = true
	var saturn: int = _index(&"saturn")
	var saturn_sprite: BodySprite = _view.get_node("Bodies").get_child(saturn)
	_view.follow(saturn)
	await wait_frames(3)
	var saturn_extent: float = saturn_sprite.extent_px
	assert_true(saturn_extent > saturn_sprite.radius_px * 1.8, "Saturn's rings show beside the drawn planet")
	var hole: CelestialBody = PowerCatalog.make_body(_power("black_hole"), simulation.system)
	var earth: int = _index(&"earth")
	var e: int = earth * 3
	var index: int = simulation.place_body(hole, simulation.state.view_pos[e] + 0.3, simulation.state.view_pos[e + 1], 0.0, 0.0, 0.0, 0.0, "FRONT_PLACED")
	simulation.system.body(index).rings.append({"inner": 0.001, "outer": 0.0015, "color": &"accretion", "density": 0.5})
	_view.follow(index)
	await wait_frames(3)
	var sprite: BodySprite = _view.get_node("Bodies").get_child(index)
	assert_true(sprite.extent_px <= sprite.radius_px * 4.0 + 1.0, "a ring 0.0015 AU out stays near the black hole: %s px for a %d px disc" % [sprite.extent_px, sprite.radius_px])


func _power(id: String) -> Dictionary:
	for power: Dictionary in (PowerCatalog.load_file() as Dictionary)["powers"]:
		if power["id"] == id:
			return power
	return {}
