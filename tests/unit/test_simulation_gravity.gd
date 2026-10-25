extends TestCase
## The game's simulation on the gravity kernel: the untouched Solar System
## rides its real orbits; once disturbed it runs on n-body gravity, keeps its
## shape, shows where everything is, and gives the same future whatever the
## frame rate.

const SOLAR_SYSTEM: String = "res://data/presets/solar_system.json"
## 2026-10-25 12:00 UTC, in years since J2000.0.
const START: float = 26.81


static func _simulation() -> Simulation:
	var system: StarSystem = (PresetLoader.load_file(SOLAR_SYSTEM) as Dictionary)["system"]
	return Simulation.new(system, SimClock.load_default(START))


static func _distance(system: StarSystem, a: StringName, b: StringName) -> float:
	return system.distance(system.index_of(a), system.index_of(b))


func test_the_untouched_system_rides_its_real_orbits() -> void:
	var simulation: Simulation = _simulation()
	assert_true(simulation.is_pristine(), "untouched at first")
	simulation.clock.use_preset("4")
	for frame: int in 60:
		simulation.advance(1.0 / 60.0)
	var rails: StarSystem = (PresetLoader.load_file(SOLAR_SYSTEM) as Dictionary)["system"]
	rails.place_on_orbits(simulation.clock.time)
	assert_true(simulation.system.positions == rails.positions, "exactly where the orbits put them")
	assert_true(simulation.is_pristine(), "still untouched")


func test_a_disturbed_solar_system_keeps_its_shape_under_real_gravity() -> void:
	var simulation: Simulation = _simulation()
	simulation.leave_pristine()
	assert_false(simulation.is_pristine(), "now integrated")
	var state: NBodyState = simulation.state
	for k: int in 3:
		var momentum: float = 0.0
		for i: int in state.body_count():
			momentum += state.vel[i * 3 + k] * state.mass[i]
		assert_almost_eq(momentum, 0.0, 1e-15, "the system's centre of mass is at rest (axis %d)" % k)
	simulation.clock.use_preset("7")
	var closest: float = INF
	var farthest: float = 0.0
	var moon_closest: float = INF
	var moon_farthest: float = 0.0
	for frame: int in 120:
		simulation.advance(1.0 / 60.0)
		var r: float = _distance(simulation.system, &"sun", &"earth")
		closest = minf(closest, r)
		farthest = maxf(farthest, r)
		var m: float = _distance(simulation.system, &"earth", &"moon")
		moon_closest = minf(moon_closest, m)
		moon_farthest = maxf(moon_farthest, m)
	assert_true(simulation.clock.time > START + 1.95, "about two years later (%s)" % (simulation.clock.time - START))
	assert_true(closest > 0.98 and farthest < 1.02, "Earth stays on its orbit (%s–%s AU)" % [closest, farthest])
	assert_true(
		moon_closest > Units.au_from_km(350000.0) and moon_farthest < Units.au_from_km(410000.0),
		"the Moon stays with the Earth (%s–%s km)" % [Units.km_from_au(moon_closest), Units.km_from_au(moon_farthest)]
	)
	var rails: StarSystem = (PresetLoader.load_file(SOLAR_SYSTEM) as Dictionary)["system"]
	rails.place_on_orbits(simulation.clock.time)
	var jupiter: int = rails.index_of(&"jupiter")
	var gap: float = Vector3(
		simulation.system.x(jupiter) - rails.x(jupiter), simulation.system.y(jupiter) - rails.y(jupiter),
		simulation.system.z(jupiter) - rails.z(jupiter)
	).length()
	assert_true(gap < 0.01, "Jupiter within 0.01 AU of its real place after two years (%s AU)" % gap)


func test_the_screen_shows_the_simulated_moment() -> void:
	var simulation: Simulation = _simulation()
	simulation.leave_pristine()
	simulation.clock.use_preset("4")
	for frame: int in 30:
		simulation.advance(1.0 / 60.0)
	assert_almost_eq(simulation.clock.time, START + 0.5 / Units.YEAR_DAYS, 1e-9, "half a day at one day per second")
	assert_true(simulation.state.time <= simulation.clock.time, "committed up to the shown moment")
	assert_true(simulation.system.positions == simulation.state.view_pos, "drawn where the kernel says they are now")


func test_frames_do_not_change_the_future() -> void:
	var a: Simulation = _simulation()
	var b: Simulation = _simulation()
	a.leave_pristine()
	b.leave_pristine()
	# The frame budget depends on how busy the machine is; this test is about
	# how frames split the time, so it gets all the work it needs.
	for simulation: Simulation in [a, b]:
		simulation.max_usec_per_frame = 1 << 30
		simulation.clock.use_preset("5")
	for frame: int in 60:
		a.advance(1.0 / 60.0)
	for frame: int in 25:
		b.advance(1.0 / 25.0 if frame % 2 == 0 else 1.0 / 50.0)
	b.advance(1.0 - 13.0 / 25.0 - 12.0 / 50.0)
	assert_almost_eq(a.clock.time, b.clock.time, 1e-12, "same moment")
	assert_eq(a.state.time, b.state.time, "same committed step")
	assert_true(a.state.pos == b.state.pos, "same positions")
	assert_true(a.state.vel == b.state.vel, "same velocities")


func test_the_fastest_moons_ride_rails_when_time_runs_fast() -> void:
	var simulation: Simulation = _simulation()
	simulation.leave_pristine()
	var phobos: int = simulation.system.index_of(&"phobos")
	var moon: int = simulation.system.index_of(&"moon")
	simulation.clock.use_preset("4")
	for frame: int in 70:
		simulation.advance(1.0 / 60.0)
	assert_eq(simulation.state.mode[phobos], Gravity.Mode.FREE, "integrated at one day per second")
	simulation.clock.use_preset("7")
	for frame: int in 70:
		simulation.advance(1.0 / 60.0)
	assert_eq(simulation.state.mode[phobos], Gravity.Mode.RAILS, "on rails at one year per second")
	assert_eq(simulation.state.mode[moon], Gravity.Mode.FREE, "the Moon stays integrated")
	simulation.clock.use_preset("4")
	for frame: int in 70:
		simulation.advance(1.0 / 60.0)
	assert_eq(simulation.state.mode[phobos], Gravity.Mode.FREE, "integrated again when time slows down")


func test_the_simulation_lags_rather_than_stalls() -> void:
	var simulation: Simulation = _simulation()
	simulation.leave_pristine()
	simulation.max_steps_per_frame = 3
	simulation.clock.use_preset("6")
	simulation.advance(1.0 / 60.0)
	assert_true(simulation.lagging, "too much work for one frame")
	assert_eq(simulation.clock.time, simulation.state.time, "the clock waits for the simulation")
	simulation.max_steps_per_frame = 100000
	simulation.advance(1.0 / 60.0)
	assert_false(simulation.lagging, "caught up")
