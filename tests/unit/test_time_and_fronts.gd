extends TestCase
## The clock, the speed ladder, light and gravity fronts, and the physics
## formulas used by inspection and the habitable zone.


func test_clock_speeds_come_from_data() -> void:
	var clock: SimClock = SimClock.load_default(0.0)
	assert_eq(clock.speed(), 86400.0, "starts at one day per second, so planets visibly turn and move")
	assert_eq(clock.ladder[0], 0.01, "slow motion")
	assert_true(clock.ladder[clock.ladder.size() - 1] >= 1e9 * Units.YEAR_SECONDS, "up to billions of years per second")
	assert_true(clock.use_preset("4"), "4 is a preset")
	assert_eq(clock.speed(), 86400.0, "one day per second")
	assert_false(clock.use_preset("x"), "no such preset")


func test_clock_ladder_is_sorted_and_clamped() -> void:
	var clock: SimClock = SimClock.load_default(0.0)
	for i: int in range(1, clock.ladder.size()):
		assert_true(clock.ladder[i] > clock.ladder[i - 1], "ladder sorted at %d" % i)
	for i: int in 100:
		clock.faster()
	assert_eq(clock.speed_index, clock.ladder.size() - 1, "stops at the fastest")
	for i: int in 100:
		clock.slower()
	assert_eq(clock.speed_index, 0, "stops at the slowest")


func test_clock_advances_and_pauses() -> void:
	var clock: SimClock = SimClock.load_default(10.0)
	clock.use_preset("7")
	clock.advance(2.0)
	assert_almost_eq(clock.time, 12.0, 1e-9, "two years in two seconds at one year per second")
	clock.toggle_pause()
	clock.advance(5.0)
	assert_almost_eq(clock.time, 12.0, 1e-9, "paused")


func test_front_reaches_a_body_after_distance_over_c() -> void:
	var front: WaveFront = WaveFront.create(WaveFront.Kind.LIGHT, 0.0, 0.0, 0.0, 0.0)
	var step: float = 10.0 / Units.YEAR_SECONDS
	for distance: float in [0.387, 1.0, 5.2, 30.07]:
		var expected: float = distance / Units.C
		var t: float = 0.0
		while not front.has_reached(distance, 0.0, 0.0, t):
			t += step
		assert_true(absf(t - expected) <= step, "%.2f AU: arrives within one sub-step" % distance)
		assert_almost_eq(front.arrival_time(distance, 0.0, 0.0), expected, 1e-15, "arrival time")
	assert_almost_eq(front.arrival_time(1.0, 0.0, 0.0) * Units.YEAR_SECONDS, 499.005, 0.001, "8 min 19 s to the Earth")


func test_finished_fronts_are_dropped() -> void:
	var system: StarSystem = (PresetLoader.load_file("res://data/presets/solar_system.json") as Dictionary)["system"]
	var simulation: Simulation = Simulation.new(system, SimClock.load_default(0.0))
	simulation.clock.use_preset("1")
	simulation.fronts.append(WaveFront.create(WaveFront.Kind.GRAVITY, 0.0, 0.0, 0.0, 0.0))
	simulation.advance(1.0)
	assert_eq(simulation.fronts.size(), 1, "still travelling after one second")
	simulation.clock.use_preset("4")
	simulation.advance(1.0)
	assert_eq(simulation.fronts.size(), 0, "a day later it has passed Eris and is dropped")


func test_habitable_zone_of_the_sun() -> void:
	assert_almost_eq(Astro.habitable_zone_inner(1.0), 0.9535, 1e-4)
	assert_almost_eq(Astro.habitable_zone_outer(1.0), 1.3736, 1e-4)
	assert_true(Astro.in_habitable_zone(1.0, 1.0), "Earth inside")
	assert_false(Astro.in_habitable_zone(0.72, 1.0), "Venus too close")
	assert_false(Astro.in_habitable_zone(1.52, 1.0), "Mars too far")
	assert_almost_eq(Astro.habitable_zone_inner(4.0), 2.0 * Astro.habitable_zone_inner(1.0), 1e-12, "√L scaling")


func test_earth_physics() -> void:
	var mass: float = Units.solar_masses_from_kg(5.9722e24)
	var radius: float = Units.au_from_km(6371.0)
	assert_almost_eq(Astro.surface_gravity(mass, radius), 9.82, 0.01, "surface gravity")
	assert_almost_eq(Astro.escape_velocity(mass, radius), 11.19, 0.01, "escape velocity")
	assert_almost_eq(Astro.equilibrium_temperature(1.0, 1.0, 0.306), 254.0, 1.5, "equilibrium temperature")
