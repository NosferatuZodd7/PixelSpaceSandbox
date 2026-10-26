extends TestCase
## The Cosmos powers on the game screen, driven by real input: pick a power
## in the toolbar, then click, drag or cancel in space.

const SPACE_SCENE: String = "res://scenes/space.tscn"
const SETTINGS_PATH: String = "user://test_cosmos_settings.cfg"
const START: String = "2026-10-13T12:00:00"

var _screen: Node
var _view: SpaceView
var _toolbar: Toolbar


func before_each() -> void:
	InputBindings.apply()
	TranslationServer.set_locale("en")
	_screen = (load(SPACE_SCENE) as PackedScene).instantiate()
	_screen.set(&"start_time", Units.years_from_unix(Time.get_unix_time_from_datetime_string(START)))
	_screen.set(&"settings", GameSettings.new(SETTINGS_PATH))
	tree.root.add_child(_screen)
	_view = _screen.get_node("View")
	_toolbar = _screen.get_node("UI/Root/Toolbar")
	await wait_frames(3)
	_simulation().clock.paused = true


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


func _button(at: Vector2, pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.position = at
	event.global_position = at
	event.pressed = pressed
	tree.root.push_input(event)


func _move(from: Vector2, to: Vector2, held: MouseButtonMask = MOUSE_BUTTON_MASK_LEFT) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = to
	event.global_position = to
	event.relative = to - from
	event.button_mask = held
	tree.root.push_input(event)


func _click(at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_button(at, true, button)
	_button(at, false, button)


func _drag(from: Vector2, to: Vector2) -> void:
	_button(from, true)
	_move(from, from.lerp(to, 0.5))
	_move(from.lerp(to, 0.5), to)
	await wait_frames(1)
	_button(to, false)


func _choose(power_id: String) -> void:
	_action(&"tab_1")
	await wait_frames(1)
	var button: Button = _toolbar.power_button(power_id)
	assert_true(button != null and button.is_visible_in_tree(), "the %s button is shown" % power_id)
	_click(button.get_global_rect().get_center())
	await wait_frames(1)


## A point on screen with no body near it, where the Sun dominates.
func _empty_point() -> Vector2:
	for y: int in range(80, 280, 20):
		for x: int in range(60, 600, 20):
			var at: Vector2 = Vector2(x, y)
			var clear: bool = true
			for i: int in _simulation().system.size():
				if _view.is_shown(i) and _view.screen_position(i).distance_to(at) < 60.0:
					clear = false
			var world: PackedFloat64Array = _view.camera.to_world(at)
			if clear and _simulation().dominant_body(world[0], world[1], 0.0) == 0:
				return at
	fail("no empty point on screen")
	return Vector2(100, 100)


func test_the_cosmos_tab_shows_its_powers() -> void:
	_action(&"tab_1")
	await wait_frames(1)
	assert_eq(_toolbar.power_ids().size(), 11, "the eleven Cosmos powers")
	assert_eq(_toolbar.power_ids()[0], "sun_like_star")
	assert_true(_toolbar.current_power().is_empty(), "none chosen yet")
	await _choose("black_hole")
	assert_eq(_toolbar.current_power()["id"], "black_hole", "clicking an icon chooses the power")
	assert_true(_toolbar.content_text().contains("Black hole"), "its name is shown: %s" % _toolbar.content_text())
	assert_true(_toolbar.content_text().contains("circular orbit"), "with how to use it")
	_action(&"tab_2")
	await wait_frames(1)
	assert_true(_toolbar.current_power().is_empty(), "another tab puts the power away")
	assert_eq(_toolbar.content_text(), "These powers arrive in milestone 5.")


func test_clicking_space_places_a_star_on_a_circular_orbit() -> void:
	var simulation: Simulation = _simulation()
	var bodies: int = simulation.system.size()
	await _choose("sun_like_star")
	var at: Vector2 = _empty_point()
	_click(at)
	await wait_frames(2)
	assert_eq(simulation.system.size(), bodies + 1, "a new body")
	var star: int = bodies
	assert_eq(Format.body_name(simulation.system.body(star)), "Star 1")
	assert_false(simulation.is_pristine(), "the system now runs on gravity")
	assert_eq(simulation.fronts.size(), 1, "its news spreads at the speed of light")
	assert_true(_view.is_shown(star), "it is drawn")
	assert_true(_view.screen_position(star).distance_to(at) < 1.5, "where it was clicked")
	var elements: PackedFloat64Array = simulation.orbit_elements(star)
	assert_true(elements.size() > 0 and elements[1] < 0.02, "on a circular orbit (e = %s)" % [elements[1] if elements.size() > 0 else NAN])
	assert_eq(_toolbar.current_power()["id"], "sun_like_star", "the power stays chosen for more")


func test_dragging_throws_the_new_body() -> void:
	var simulation: Simulation = _simulation()
	var bodies: int = simulation.system.size()
	await _choose("rocky_planet")
	var at: Vector2 = _empty_point()
	await _drag(at, at + Vector2(0, 60))
	await wait_frames(2)
	assert_eq(simulation.system.size(), bodies + 1, "a new planet")
	var elements: PackedFloat64Array = simulation.orbit_elements(bodies)
	assert_true(elements[1] > 0.3, "thrown, not circling (e = %s)" % elements[1])
	assert_true(simulation.state.vel[bodies * 3 + 1] < 0.0, "downwards on screen is towards -y in space")


func test_a_rogue_planet_sweeps_through() -> void:
	var simulation: Simulation = _simulation()
	var bodies: int = simulation.system.size()
	await _choose("rogue_planet")
	_click(_empty_point())
	await wait_frames(2)
	assert_eq(simulation.system.size(), bodies + 1)
	assert_eq(Format.body_name(simulation.system.body(bodies)), "Rogue 1")
	var elements: PackedFloat64Array = simulation.orbit_elements(bodies)
	assert_true(elements[1] > 1.0, "on an open path (e = %s)" % elements[1])


func test_delete_removes_a_body_where_its_news_arrives() -> void:
	var simulation: Simulation = _simulation()
	var mars: int = _index(&"mars")
	await _choose("delete")
	_click(_view.screen_position(mars))
	await wait_frames(2)
	assert_eq(simulation.state.mode[mars], Gravity.Mode.GHOST, "Mars is removed; it pulls on as a ghost until the news spreads")
	assert_false(_view.is_shown(mars), "and is no longer drawn")
	_click(Vector2(5, 5) + _empty_point())
	await wait_frames(1)
	assert_eq(simulation.system.size(), 33, "clicking empty space removes nothing")


func test_fling_gives_a_body_a_new_course() -> void:
	var simulation: Simulation = _simulation()
	var jupiter: int = _index(&"jupiter")
	var before: PackedFloat64Array = simulation.state.view_vel.slice(jupiter * 3, jupiter * 3 + 3)
	await _choose("fling")
	var at: Vector2 = _view.screen_position(jupiter)
	await _drag(at, at + Vector2(50, 0))
	await wait_frames(2)
	var after: PackedFloat64Array = simulation.state.vel.slice(jupiter * 3, jupiter * 3 + 3)
	assert_true(after[0] > before[0] + 1.0, "pushed towards +x (%s → %s AU/yr)" % [before[0], after[0]])
	assert_eq(simulation.system.index_of(&"jupiter"), jupiter, "still Jupiter")
	assert_true(_view.is_shown(jupiter), "still drawn")
	assert_false(_view.is_shown(simulation.system.size() - 1), "its ghost is not drawn as a body")


func test_right_click_and_escape_put_the_power_away() -> void:
	await _choose("delete")
	_click(_empty_point(), MOUSE_BUTTON_RIGHT)
	await wait_frames(1)
	assert_true(_toolbar.current_power().is_empty(), "right click cancels")
	await _choose("delete")
	_action(&"ui_cancel")
	await wait_frames(1)
	assert_true(_toolbar.current_power().is_empty(), "Esc cancels")
	assert_false(_screen.call(&"is_menu_open"), "without opening the menu")
	_action(&"ui_cancel")
	await wait_frames(1)
	assert_true(_screen.call(&"is_menu_open"), "a second Esc opens it")


func test_placed_bodies_can_be_inspected() -> void:
	var simulation: Simulation = _simulation()
	await _choose("black_hole")
	_click(_empty_point())
	await wait_frames(1)
	_click(_view.screen_position(simulation.system.size() - 1), MOUSE_BUTTON_RIGHT)
	await wait_frames(1)
	_view.select(simulation.system.size() - 1)
	await wait_frames(2)
	var windows: Array[InspectWindow] = _screen.call(&"inspect_windows")
	assert_eq(windows.size(), 1, "an inspect window opens")
	var rows: Array[PackedStringArray] = windows[0].rows()
	assert_eq(rows[0], PackedStringArray(["INSPECT_KIND", "Black hole"]))
	var labels: PackedStringArray = []
	for row: PackedStringArray in rows:
		labels.append(row[0])
	assert_true(labels.has("INSPECT_ORBITS"), "says what it circles")
	_view.select(_index(&"earth"))
	await wait_frames(2)
	rows = windows[0].rows()
	assert_eq(rows[0], PackedStringArray(["INSPECT_KIND", "Planet"]), "integrated planets still inspect")


static func _far_star() -> CelestialBody:
	var star: CelestialBody = CelestialBody.new()
	star.id = &"far_star"
	star.name_key = "PLACED_STAR"
	star.name_number = 7
	star.kind = CelestialBody.Kind.STAR
	star.mass = 1.0
	star.radius = Units.au_from_km(695700.0)
	star.luminosity = 1.0
	star.temperature = 5772.0
	star.look = &"sun"
	return star


func test_the_news_of_a_change_and_jumping_to_its_arrival() -> void:
	var simulation: Simulation = _simulation()
	simulation.place_body(_far_star(), 0.0, 20.0, 0.0, 0.0, 0.0, 0.0, "FRONT_PLACED")
	var neptune: int = _index(&"neptune")
	_view.select(neptune)
	await wait_frames(2)
	var windows: Array[InspectWindow] = _screen.call(&"inspect_windows")
	var news: PackedStringArray = []
	for row: PackedStringArray in windows[0].rows():
		if row[0] == "Star 7 appeared":
			news = row
	assert_eq(news.size(), 2, "Neptune's window says the news is on its way")
	assert_true(news.size() == 2 and news[1].begins_with("arrives in"), "and when it arrives: %s" % news)
	var next: Dictionary = simulation.next_arrival()
	var first: int = next["body"]
	_action(&"next_arrival")
	await wait_frames(2)
	assert_true(simulation.news_for(first).is_empty(), "N jumps to the moment the first body hears of it")
	assert_true(simulation.clock.paused, "and waits there")


func test_smart_time_follows_the_wave() -> void:
	var simulation: Simulation = _simulation()
	simulation.place_body(_far_star(), 0.0, 20.0, 0.0, 0.0, 0.0, 0.0, "FRONT_PLACED")
	_action(&"smart_time")
	await wait_frames(30)
	assert_true(_screen.get(&"smart_time"), "G follows the wave")
	assert_false(simulation.clock.paused, "time runs")
	assert_true(simulation.clock.is_steered(), "at the speed the wave needs")
	assert_true(Vector2(_view.camera.center_x, _view.camera.center_y - 20.0).length() < 1e-6, "watching from where it started")
	_action(&"speed_4")
	await wait_frames(1)
	assert_false(_screen.get(&"smart_time"), "choosing a speed takes over again")
	assert_false(simulation.clock.is_steered())


func test_collisions_are_announced_and_can_be_followed() -> void:
	var simulation: Simulation = _simulation()
	var earth: int = _index(&"earth")
	var mars: int = _index(&"mars")
	simulation.merge(earth, mars, "FRONT_MERGED")
	await wait_frames(2)
	var feed: NotificationFeed = _screen.get_node("UI/Root/Notifications")
	assert_eq(feed.texts().size(), 1, "one notification")
	assert_true(feed.texts().size() == 1 and feed.texts()[0] == "Earth and Mars collided", "saying what happened: %s" % [feed.texts()])
	assert_true(simulation.events.is_empty(), "the screen took the event")
	_click(feed.entry(0).get_global_rect().get_center())
	await wait_frames(2)
	assert_eq(_view.followed, earth, "clicking it follows the Earth")
	assert_eq(_view.selected, earth)


func test_undo_and_the_timeline_bar() -> void:
	var simulation: Simulation = _simulation()
	await _choose("sun_like_star")
	_click(_empty_point())
	await wait_frames(2)
	assert_eq(simulation.system.size(), 34, "a star placed")
	var bar: TimelineBar = _screen.get_node("UI/Root/TimelineBar")
	assert_eq(bar.tick_count(), 1, "the timeline shows the snapshot taken before it")
	var undo: InputEventKey = InputEventKey.new()
	undo.keycode = KEY_Z
	undo.ctrl_pressed = true
	undo.pressed = true
	tree.root.push_input(undo)
	await wait_frames(2)
	assert_eq(simulation.system.size(), 33, "Ctrl+Z takes it back")
	assert_eq(_view.get_node("Bodies").get_child_count(), 33, "and the view drops its sprite")
	assert_true(simulation.is_pristine(), "the Solar System is untouched again")
	assert_eq(bar.tick_count(), 0, "the snapshot is used up")
	simulation.clock.paused = false
	simulation.timeline.record(simulation, Timeline.AUTO)
	simulation.clock.use_preset("6")
	await wait_frames(20)
	simulation.timeline.record(simulation, Timeline.AUTO)
	await wait_frames(2)
	assert_eq(bar.tick_count(), 2)
	var first: float = float(simulation.timeline.snapshots[0]["time"])
	_click(bar.tick(0).get_global_rect().get_center())
	await wait_frames(2)
	assert_almost_eq(simulation.clock.time, first, 1e-9, "clicking a mark goes back to it")
	assert_true(simulation.clock.paused, "and waits there")


func test_a_collision_flashes() -> void:
	var simulation: Simulation = _simulation()
	simulation.merge(_index(&"earth"), _index(&"mars"), "FRONT_MERGED")
	await wait_frames(2)
	assert_true(_view.active_flashes() > 0, "a flash where they met")
	simulation.clock.use_preset("4")
	simulation.clock.paused = false
	await wait_frames(30)
	var feed: NotificationFeed = _screen.get_node("UI/Root/Notifications")
	assert_eq(feed.texts().size(), 1, "falling debris is not announced: %s" % [feed.texts()])


func test_many_impacts_on_one_body_make_one_notice() -> void:
	var simulation: Simulation = _simulation()
	var jupiter: int = _index(&"jupiter")
	for k: int in 5:
		simulation.events.append({"kind": "impact", "body": jupiter, "particle": 0, "time": simulation.clock.time})
	await wait_frames(2)
	var feed: NotificationFeed = _screen.get_node("UI/Root/Notifications")
	assert_eq(feed.texts(), PackedStringArray(["5 small bodies struck Jupiter"]), "counted on one line")
	simulation.events.append({"kind": "impact", "body": jupiter, "particle": 0, "time": simulation.clock.time})
	await wait_frames(2)
	assert_eq(feed.texts(), PackedStringArray(["6 small bodies struck Jupiter"]), "and kept up to date")


## Following the Earth close up, with time running.
func _watch_earth(scale: float) -> int:
	var earth: int = _index(&"earth")
	_view.follow(earth)
	_view.camera.set_scale_now(scale)
	await wait_frames(2)
	return earth


func _merged_with(body: int) -> bool:
	for event: Dictionary in _simulation().events:
		if event["kind"] == "merge" and (int(event["body"]) == body or int(event["other"]) == body):
			return true
	return false


## Dragging a new planet onto the Earth throws it at the Earth: it stays in
## sight on the way and the two collide.
func test_dragging_onto_a_body_throws_the_new_body_at_it() -> void:
	var simulation: Simulation = _simulation()
	var earth: int = await _watch_earth(2000.0)
	var mass: float = simulation.state.final_mass(earth)
	await _choose("rocky_planet")
	var target: Vector2 = _view.screen_position(earth)
	await _drag(target + Vector2(60, -40), target)
	var planet: int = simulation.system.size() - 1
	assert_eq(simulation.system.body(planet).kind, CelestialBody.Kind.PLANET, "a planet was placed")
	simulation.clock.paused = false
	var hidden: int = 0
	for frame: int in 600:
		await wait_frames(1)
		if not simulation.is_present(planet) or simulation.state.final_mass(earth) > mass * 1.5:
			break
		if not _view.is_shown(planet):
			hidden += 1
	assert_true(simulation.state.final_mass(earth) > mass * 1.5, "they collided: the Earth has both masses")
	assert_eq(hidden, 0, "the planet was in sight all the way")


## Clicking on a body with a place power drops the new body onto it.
func test_clicking_a_body_drops_the_new_body_onto_it() -> void:
	var simulation: Simulation = _simulation()
	var mars: int = _index(&"mars")
	var mass: float = simulation.state.final_mass(mars)
	await _choose("rocky_planet")
	_click(_view.screen_position(mars))
	await wait_frames(1)
	var planet: int = simulation.system.size() - 1
	var planet_mass: float = simulation.state.final_mass(planet)
	simulation.clock.paused = false
	# The new planet is the heavier: it takes Mars in.
	var hit: bool = await wait_until(func() -> bool: return not simulation.is_present(mars), 1.0)
	assert_true(hit, "it hits Mars at once")
	assert_almost_eq(simulation.state.final_mass(planet), planet_mass + mass, 1e-12, "one body with both masses")


## While following a body, a drag is a throw as seen from it: dragging up
## sends the new body up past the Earth, not along the Earth's own orbit.
func test_while_following_a_drag_is_relative_to_what_is_followed() -> void:
	var simulation: Simulation = _simulation()
	var earth: int = await _watch_earth(2000.0)
	await _choose("rocky_planet")
	var start: Vector2 = _view.screen_position(earth) + Vector2(80, 0)
	await _drag(start, start + Vector2(0, -40))
	var planet: int = simulation.system.size() - 1
	var b: int = planet * 3
	var e: int = earth * 3
	var relative: Vector2 = Vector2(simulation.state.vel[b] - simulation.state.vel[e], simulation.state.vel[b + 1] - simulation.state.vel[e + 1])
	assert_true(relative.normalized().dot(Vector2(0, 1)) > 0.99, "it moves up the screen relative to the Earth: %s" % relative)


## Flinging a body by dragging it onto another throws it straight at it.
func test_flinging_a_body_onto_another_throws_it_at_it() -> void:
	var simulation: Simulation = _simulation()
	var venus: int = _index(&"venus")
	var earth: int = _index(&"earth")
	await _choose("fling")
	await _drag(_view.screen_position(venus), _view.screen_position(earth))
	simulation.clock.use_preset("5")
	simulation.clock.paused = false
	# The Earth is the heavier: it takes Venus in.
	var hit: bool = await wait_until(func() -> bool: return not simulation.is_present(venus), 6.0)
	assert_true(hit, "Venus flies into the Earth")
	assert_true(simulation.is_present(earth), "and the Earth remains, heavier")


## Dropped onto a much lighter body, a heavy one barely moves: the light
## one falls into it.
func test_a_black_hole_dropped_on_a_planet_stays_put() -> void:
	var simulation: Simulation = _simulation()
	var earth: int = _index(&"earth")
	var e: int = earth * 3
	var earth_velocity: Vector3 = Vector3(simulation.state.view_vel[e], simulation.state.view_vel[e + 1], simulation.state.view_vel[e + 2])
	await _choose("black_hole")
	_click(_view.screen_position(earth))
	await wait_frames(1)
	var hole: int = simulation.system.size() - 1
	var h: int = hole * 3
	var velocity: Vector3 = Vector3(simulation.state.vel[h], simulation.state.vel[h + 1], simulation.state.vel[h + 2])
	var kms: float = Units.km_from_au((velocity - earth_velocity).length()) / Units.YEAR_SECONDS
	assert_true(kms < 1.0, "it moves with the Earth (%.1f km/s apart)" % kms)


## A body thrown at another says, next to it, how long until it hits; the
## countdown runs with time and goes once they meet.
func test_a_thrown_body_counts_down_to_its_impact() -> void:
	var simulation: Simulation = _simulation()
	var venus: int = _index(&"venus")
	var earth: int = _index(&"earth")
	await _choose("fling")
	await _drag(_view.screen_position(venus), _view.screen_position(earth))
	await wait_frames(1)
	var label: String = _view.impact_labels().get(venus, "")
	assert_true(label.begins_with("Impact in "), "a countdown next to Venus: \"%s\"" % label)
	simulation.clock.use_preset("5")
	simulation.clock.paused = false
	await wait_frames(20)
	var later: String = _view.impact_labels().get(venus, "")
	assert_true(later.begins_with("Impact in ") and later != label, "it counts down: \"%s\", then \"%s\"" % [label, later])
	var hit: bool = await wait_until(func() -> bool: return not simulation.is_present(venus), 6.0)
	assert_true(hit, "Venus flies into the Earth")
	await wait_frames(1)
	assert_true(_view.impact_labels().is_empty(), "no countdown once they met: %s" % _view.impact_labels())


## Next to a body at the right edge of the screen, the countdown goes to
## its left rather than off the screen.
func test_the_countdown_of_a_body_at_the_edge_stays_on_screen() -> void:
	var simulation: Simulation = _simulation()
	var earth: int = _index(&"earth")
	simulation.leave_pristine()
	simulation.expect_impact(earth, _index(&"mars"), simulation.clock.time + 10.0 / Units.YEAR_DAYS)
	_view.camera.set_scale_now(2000.0)
	_view.camera.look_at(simulation.system.x(earth) - 300.0 / 2000.0, simulation.system.y(earth))
	await wait_frames(2)
	assert_true(_view.screen_position(earth).x > 600.0, "the Earth is at the right edge: %s" % _view.screen_position(earth))
	assert_eq(_view.impact_labels().get(earth, ""), "Impact in 10 days")


## Following a body that another takes in, the view follows what is left of
## them, rather than the empty place where it was.
func test_the_view_follows_what_takes_in_the_followed_body() -> void:
	var simulation: Simulation = _simulation()
	var earth: int = await _watch_earth(2000.0)
	await _choose("gas_giant")
	var target: Vector2 = _view.screen_position(earth)
	await _drag(target + Vector2(40, -30), target)
	var giant: int = simulation.system.size() - 1
	simulation.clock.paused = false
	var hit: bool = await wait_until(func() -> bool: return not simulation.is_present(earth), 6.0)
	assert_true(hit, "the giant takes the Earth in")
	await wait_frames(1)
	assert_eq(_view.followed, giant, "the view follows the giant")
