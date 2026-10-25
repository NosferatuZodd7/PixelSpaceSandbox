extends TestCase
## Changing the system: placing, removing and flinging bodies. Each change
## travels at the speed of light as a front; bodies the news has not reached
## still feel the old system (a removed body pulls on as a ghost), and a
## front is folded away once it has passed everything.

const SOLAR_SYSTEM: String = "res://data/presets/solar_system.json"
const START: float = 26.81


static func _simulation() -> Simulation:
	var system: StarSystem = (PresetLoader.load_file(SOLAR_SYSTEM) as Dictionary)["system"]
	var simulation: Simulation = Simulation.new(system, SimClock.load_default(START))
	simulation.max_usec_per_frame = 1 << 30
	return simulation


static func _sun_like_star() -> CelestialBody:
	var star: CelestialBody = CelestialBody.new()
	star.id = &"second_sun"
	star.name_key = "BODY_SECOND_SUN"
	star.kind = CelestialBody.Kind.STAR
	star.mass = 1.0
	star.radius = Units.au_from_km(695700.0)
	star.luminosity = 1.0
	star.temperature = 5772.0
	star.look = &"sun"
	return star


## Runs both simulations to the same moment, frame by frame.
static func _run(simulations: Array[Simulation], seconds: float, preset: String) -> void:
	for simulation: Simulation in simulations:
		simulation.clock.use_preset(preset)
		var frames: int = 60
		for frame: int in frames:
			simulation.advance(seconds / frames)


## The committed position, as 64-bit numbers (Vector3 would round to 32 bits).
static func _position(simulation: Simulation, id: StringName) -> PackedFloat64Array:
	var i: int = simulation.system.index_of(id)
	return simulation.state.pos.slice(i * 3, i * 3 + 3)


func test_a_star_placed_far_away_is_felt_only_once_its_front_arrives() -> void:
	var changed: Simulation = _simulation()
	var reference: Simulation = _simulation()
	reference.leave_pristine()
	var star: int = changed.place_body(_sun_like_star(), 0.0, 50.0, 0.0, 0.0, 0.0, 0.0, "FRONT_PLACED")
	assert_false(changed.is_pristine(), "a change leaves the untouched orbits")
	assert_eq(changed.fronts.size(), 1, "one front leaves the new star")
	assert_eq(changed.state.mass[star], 0.0, "nobody feels it yet")
	# 50 AU of light: about 6.9 hours; run 6 hours at one hour per second.
	_run([changed, reference], 6.0, "3")
	assert_eq(changed.state.time, reference.state.time, "same steps")
	for id: StringName in [&"sun", &"earth", &"jupiter", &"saturn"]:
		assert_eq(_position(changed, id), _position(reference, id), "%s untouched before the news arrives" % id)
	_run([changed, reference], 24.0, "3")
	assert_ne(_position(changed, &"earth"), _position(reference, &"earth"), "felt once it has arrived")


func test_a_removed_sun_keeps_pulling_until_the_news_arrives() -> void:
	var changed: Simulation = _simulation()
	var reference: Simulation = _simulation()
	reference.leave_pristine()
	var sun: int = changed.system.index_of(&"sun")
	var earth: int = changed.system.index_of(&"earth")
	changed.remove_body(sun, "FRONT_REMOVED")
	assert_eq(changed.state.mode[sun], Gravity.Mode.GHOST, "the Sun is now a ghost")
	assert_eq(changed.felt_luminosity(sun, changed.system.x(earth), changed.system.y(earth), changed.system.z(earth)), 1.0, "Earth still sees it")
	# Light takes 8 min 19 s to reach the Earth: run 5 minutes.
	_run([changed, reference], 5.0, "2")
	assert_eq(_position(changed, &"earth"), _position(reference, &"earth"), "the Earth still circles the ghost")
	var e: PackedFloat64Array = _position(changed, &"earth")
	assert_eq(changed.felt_luminosity(sun, e[0], e[1], e[2]), 1.0, "and is still lit")
	_run([changed, reference], 5.0, "2")
	e = _position(changed, &"earth")
	assert_eq(changed.felt_luminosity(sun, e[0], e[1], e[2]), 0.0, "ten minutes on, the Earth has gone dark")
	_run([changed, reference], 2.0, "4")
	assert_eq(changed.state.mode[sun], Gravity.Mode.GONE, "once the news has passed everything, the ghost is gone")
	assert_true(changed.fronts.is_empty(), "and the front is folded away")
	assert_true(changed.state.delta_body.is_empty(), "with its mass changes")


func test_a_flung_planet_keeps_its_identity_and_leaves_a_ghost() -> void:
	var changed: Simulation = _simulation()
	var reference: Simulation = _simulation()
	reference.leave_pristine()
	var jupiter: int = changed.system.index_of(&"jupiter")
	var bodies: int = changed.state.body_count()
	changed.fling(jupiter, 0.0, 0.0, 0.0, "FRONT_FLUNG")
	assert_eq(changed.system.index_of(&"jupiter"), jupiter, "still the same Jupiter")
	assert_eq(changed.state.body_count(), bodies + 1, "a ghost keeps its old path")
	assert_eq(changed.state.mode[bodies], Gravity.Mode.GHOST, "the ghost")
	assert_eq(changed.state.vel[jupiter * 3], 0.0, "Jupiter stopped dead")
	# Saturn is more than 4 AU away: over half an hour of light. Run 20 minutes.
	_run([changed, reference], 20.0, "2")
	assert_eq(_position(changed, &"saturn"), _position(reference, &"saturn"), "Saturn feels the old Jupiter")
	assert_ne(_position(changed, &"jupiter"), _position(reference, &"jupiter"), "Jupiter itself has stopped")


func test_with_instant_light_a_change_is_felt_at_once() -> void:
	var simulation: Simulation = _simulation()
	simulation.light_speed = INF
	var star: int = simulation.place_body(_sun_like_star(), 0.0, 50.0, 0.0, 0.0, 0.0, 0.0, "FRONT_PLACED")
	assert_true(simulation.fronts.is_empty(), "no front travels")
	assert_eq(simulation.state.mass[star], 1.0, "everyone feels the new star at once")
	var sun: int = simulation.system.index_of(&"sun")
	simulation.remove_body(sun, "FRONT_REMOVED")
	assert_eq(simulation.state.mode[sun], Gravity.Mode.GONE, "and a removed body is gone at once")


func test_finished_fronts_are_folded_into_the_masses() -> void:
	var simulation: Simulation = _simulation()
	var star: int = simulation.place_body(_sun_like_star(), 0.0, 50.0, 0.0, 0.0, 0.0, 0.0, "FRONT_PLACED")
	_run([simulation], 1.0, "4")
	assert_true(simulation.fronts.is_empty(), "a day later the front has passed everything")
	assert_true(simulation.state.delta_body.is_empty(), "its mass change is folded in")
	assert_eq(simulation.state.mass[star], 1.0, "the star's full mass, felt by all")
	var s: PackedFloat64Array = _position(simulation, &"saturn")
	assert_eq(simulation.felt_luminosity(star, s[0], s[1], s[2]), 1.0, "and its light reaches everywhere")


func test_what_a_new_body_would_circle() -> void:
	var simulation: Simulation = _simulation()
	var system: StarSystem = simulation.system
	var earth: int = system.index_of(&"earth")
	assert_eq(simulation.dominant_body(system.x(earth) + 0.001, system.y(earth), system.z(earth)), earth, "near the Earth: the Earth")
	assert_eq(simulation.dominant_body(3.0, 0.0, 0.0), system.index_of(&"sun"), "in the asteroid belt: the Sun")
	simulation.leave_pristine()
	simulation.advance(1.0 / 60.0)
	assert_eq(simulation.dominant_body(system.x(earth) + 0.001, system.y(earth), system.z(earth)), earth, "also once integrated")


func test_a_body_placed_with_the_circular_velocity_circles() -> void:
	var simulation: Simulation = _simulation()
	var system: StarSystem = simulation.system
	var earth: int = system.index_of(&"earth")
	# 90,000 km out: well inside the Moon's orbit, so the Moon barely tugs it.
	var r: float = 0.0006
	var start: PackedFloat64Array = [system.x(earth) + r, system.y(earth), system.z(earth)]
	var v: PackedFloat64Array = simulation.circular_velocity(start[0], start[1], start[2])
	var period: float = Kepler.period_years(r, system.body(earth).mass)
	var path: PackedFloat64Array = simulation.predict_particle(start[0], start[1], start[2], v[0], v[1], v[2], period, 64)
	assert_eq(path.size(), 64 * 3, "64 points")
	var lowest: float = INF
	var highest: float = 0.0
	var rails: StarSystem = (PresetLoader.load_file(SOLAR_SYSTEM) as Dictionary)["system"]
	for k: int in 64:
		rails.place_on_orbits(START + period * (k + 1) / 64.0)
		var d: float = Vector2(path[k * 3] - rails.x(earth), path[k * 3 + 1] - rails.y(earth)).length()
		lowest = minf(lowest, d)
		highest = maxf(highest, d)
	assert_true(lowest > r * 0.9 and highest < r * 1.1, "stays about 90,000 km from the Earth for a whole orbit (%s–%s AU)" % [lowest, highest])
