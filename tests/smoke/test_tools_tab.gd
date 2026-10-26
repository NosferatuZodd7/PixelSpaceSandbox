extends TestCase
## The Tools tab on the game screen, driven by real input: overlays switch
## on and off, the ruler measures, the light pulse sends a ring of light,
## and the overlays that need the simulation (ghost trajectories, Hill
## spheres, Lagrange points) draw what it gives them.

const SPACE_SCENE: String = "res://scenes/space.tscn"
const SETTINGS_PATH: String = "user://test_tools_settings.cfg"
const START: String = "2026-10-13T12:00:00"

var _screen: Node
var _view: SpaceView
var _overlays: OverlayView
var _toolbar: Toolbar


func before_each() -> void:
	InputBindings.apply()
	TranslationServer.set_locale("en")
	_screen = (load(SPACE_SCENE) as PackedScene).instantiate()
	_screen.set(&"start_time", Units.years_from_unix(Time.get_unix_time_from_datetime_string(START)))
	_screen.set(&"settings", GameSettings.new(SETTINGS_PATH))
	tree.root.add_child(_screen)
	_view = _screen.get_node("View")
	_overlays = _screen.get_node("Overlays")
	_toolbar = _screen.get_node("UI/Root/Toolbar")
	await wait_frames(3)
	_simulation().clock.paused = true


func after_each() -> void:
	_screen.queue_free()
	await wait_frames(2)
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


func _simulation() -> Simulation:
	return _screen.get(&"simulation")


func _index(id: StringName) -> int:
	return _simulation().system.index_of(id)


func _button(at: Vector2, pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.position = at
	event.global_position = at
	event.pressed = pressed
	tree.root.push_input(event)


func _move(from: Vector2, to: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = to
	event.global_position = to
	event.relative = to - from
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	tree.root.push_input(event)


func _click(at: Vector2) -> void:
	_button(at, true)
	_button(at, false)


func _open_tools() -> void:
	_toolbar.select(_toolbar.tabs.map(func(tab: Dictionary) -> String: return tab["id"]).find("tools"))
	await wait_frames(1)


func _press(tool_id: String) -> void:
	var button: Button = _toolbar.power_button(tool_id)
	assert_true(button != null and button.is_visible_in_tree(), "the %s button is shown" % tool_id)
	_click(button.get_global_rect().get_center())
	await wait_frames(2)


func test_overlays_switch_on_and_off() -> void:
	await _open_tools()
	assert_eq(_toolbar.power_ids().size(), 11, "eleven tools")
	assert_true(_view.overlays[&"orbits"] and _view.overlays[&"fronts"] and _view.overlays[&"hz"], "orbits, fronts and the habitable zone start shown")
	assert_true(_toolbar.power_button("overlay_orbits").button_pressed, "and their buttons say so")
	await _press("overlay_orbits")
	assert_false(_view.overlays[&"orbits"], "a click hides the orbits")
	assert_eq(_view.orbits_drawn(), 0, "none are drawn")
	await _press("overlay_orbits")
	assert_true(_view.orbits_drawn() > 0, "another shows them again")
	await _press("overlay_hill")
	assert_true(_view.overlays[&"hill"], "overlays add up")
	# Zoomed out, Jupiter's Hill sphere (0.35 AU) is wider than its disc.
	_view.camera.set_scale_now(40.0)
	await wait_frames(2)
	assert_true(_overlays.drawn(&"hill") > 0, "Hill spheres are drawn")


func test_the_ruler_measures_in_km_au_and_light_time() -> void:
	await _open_tools()
	await _press("ruler")
	var sun: Vector2 = _view.screen_position(0)
	var earth: Vector2 = _view.screen_position(_index(&"earth"))
	_button(sun, true)
	_move(sun, earth)
	await wait_frames(1)
	_button(earth, false)
	await wait_frames(2)
	var tool: PowerTool = _screen.get_node("Powers")
	var text: String = tool.ruler_text()
	assert_true(text.contains("AU"), "in AU: %s" % text)
	assert_true(text.contains("km"), "in km")
	assert_true(text.contains("8 min"), "and light needs about 8 minutes")


func test_a_light_pulse_leaves_a_body() -> void:
	await _open_tools()
	await _press("light_pulse")
	_click(_view.screen_position(_index(&"jupiter")))
	await wait_frames(2)
	var fronts: Array[WaveFront] = _simulation().fronts
	assert_eq(fronts.size(), 1, "a ring of light")
	assert_eq(fronts[0].label_key, "FRONT_PULSE")
	assert_eq(fronts[0].body, _index(&"jupiter"), "from Jupiter")
	assert_true(_simulation().is_pristine(), "it changes nothing")


func test_ghost_trajectories_show_what_would_have_been() -> void:
	await _open_tools()
	await _press("overlay_ghosts")
	assert_true(_simulation().keep_alternative, "the simulation keeps the system as it was at each change")
	var star: CelestialBody = PowerCatalog.make_body(
		PowerCatalog.load_file()["powers"].filter(func(power: Dictionary) -> bool: return power["id"] == "sun_like_star")[0],
		_simulation().system
	)
	_simulation().place_body(star, 0.0, 2.0, 0.0, 0.0, 0.0, 0.0, "FRONT_PLACED")
	_simulation().clock.use_preset("4")
	await wait_frames(40)
	assert_true(_simulation().alternative != null, "what would have been runs alongside")
	assert_true(_overlays.drawn(&"ghosts") > 0, "and is drawn next to the real paths")


func test_lagrange_points_of_the_selected_body() -> void:
	await _open_tools()
	await _press("overlay_lagrange")
	assert_eq(_overlays.drawn(&"lagrange"), 0, "nothing selected, nothing drawn")
	_view.select(_index(&"jupiter"))
	await wait_frames(2)
	assert_eq(_overlays.drawn(&"lagrange"), 5, "Jupiter's five points")


func test_the_world_laws_panel_changes_the_rules() -> void:
	await _open_tools()
	await _press("world_laws")
	var panel: WorldLawsPanel = _screen.get_node("UI/Root/Center/WorldLawsPanel")
	assert_true(panel.visible, "the World laws button opens the panel")
	var rows: Array[SettingRow] = panel.rows()
	assert_eq(rows.size(), 3, "speed of light, collisions, gravity")
	assert_eq(tr(rows[0].value_text()), "Real", "light at its real speed")
	rows[0].step(-1)
	assert_eq(_simulation().light_speed, INF, "one step back: instant")
	assert_true(panel.note_text().is_empty(), "instant needs no warning")
	rows[0].step(-1)
	assert_almost_eq(_simulation().light_speed, Units.C / 1000.0, 1e-9, "then a thousand times slower")
	assert_true(panel.note_text().to_lower().contains("fiction"), "clearly marked as fiction: %s" % panel.note_text())
	rows[1].step(1)
	assert_false(_simulation().state.collisions_enabled, "collisions off")
	rows[2].step(1)
	assert_eq(_simulation().state.g_scale, 2.0, "gravity twice as strong")
	_press_action(&"ui_cancel")
	await wait_frames(1)
	assert_false(panel.visible, "Esc closes it")
	assert_false(_screen.call(&"is_menu_open"), "without opening the pause menu")


func _press_action(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	tree.root.push_input(event)


## With the world laws panel open, the arrow keys change the law in focus
## and leave the camera alone, and Space still pauses without changing a law.
func test_keys_in_the_world_laws_panel_do_not_move_the_camera() -> void:
	await _open_tools()
	await _press("world_laws")
	var x: float = _view.camera.center_x
	var y: float = _view.camera.center_y
	Input.action_press(&"pan_right")
	await wait_frames(10)
	Input.action_release(&"pan_right")
	assert_eq(_view.camera.center_x, x, "the camera stays put")
	assert_eq(_view.camera.center_y, y)
	var paused: bool = _simulation().clock.paused
	var space: InputEventKey = InputEventKey.new()
	space.keycode = KEY_SPACE
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	tree.root.push_input(space)
	await wait_frames(1)
	assert_eq(_simulation().clock.paused, not paused, "Space pauses or resumes")
	assert_eq(_simulation().light_speed, Units.C, "and changes no law")
