extends TestCase
## Smart time: light and gravity are slow at the scale of a system, so the
## game tells each body when the news of a change will reach it, can jump
## to the next arrival, and can run time so a front never takes more than
## a few seconds to cross the view, easing down as it reaches a body.

const SOLAR_SYSTEM: String = "res://data/presets/solar_system.json"
const START: float = 26.81


static func _simulation() -> Simulation:
	var system: StarSystem = (PresetLoader.load_file(SOLAR_SYSTEM) as Dictionary)["system"]
	var simulation: Simulation = Simulation.new(system, SimClock.load_default(START))
	simulation.max_usec_per_frame = 1 << 30
	return simulation


static func _star() -> CelestialBody:
	var star: CelestialBody = CelestialBody.new()
	star.id = &"far_star"
	star.name_key = "BODY_FAR_STAR"
	star.kind = CelestialBody.Kind.STAR
	star.mass = 1.0
	star.radius = Units.au_from_km(695700.0)
	star.luminosity = 1.0
	star.temperature = 5772.0
	return star


func test_a_body_knows_when_the_news_will_reach_it() -> void:
	var simulation: Simulation = _simulation()
	simulation.clock.paused = true
	var star: int = simulation.place_body(_star(), 0.0, 50.0, 0.0, 0.0, 0.0, 0.0, "FRONT_PLACED")
	var earth: int = simulation.system.index_of(&"earth")
	var news: Array[Dictionary] = simulation.news_for(earth)
	assert_eq(news.size(), 1, "one piece of news on its way to the Earth")
	var distance: float = Vector3(
		simulation.system.x(earth), simulation.system.y(earth) - 50.0, simulation.system.z(earth)
	).length()
	assert_almost_eq(float(news[0]["seconds"]), Units.light_time_seconds(distance), 1.0, "it arrives after the light time")
	assert_eq(news[0]["body"], star, "about the new star")
	assert_true(simulation.news_for(star).is_empty(), "the star itself knows")


func test_time_can_jump_to_the_next_arrival() -> void:
	var simulation: Simulation = _simulation()
	simulation.clock.paused = true
	simulation.place_body(_star(), 0.0, 50.0, 0.0, 0.0, 0.0, 0.0, "FRONT_PLACED")
	var next: Dictionary = simulation.next_arrival()
	assert_false(next.is_empty(), "a front is on its way")
	var first: int = next["body"]
	assert_eq(simulation.news_for(first).size(), 1, "the body it reaches first has not heard yet")
	for i: int in simulation.system.size():
		if simulation.is_present(i) and not simulation.news_for(i).is_empty():
			assert_true(float(simulation.news_for(i)[0]["seconds"]) >= float(simulation.news_for(first)[0]["seconds"]) - 1e-6, "no body hears sooner")
	simulation.jump_to_next_arrival()
	assert_true(simulation.news_for(first).is_empty(), "after the jump it has (%s)" % simulation.system.body(first).id)
	assert_true(simulation.clock.time - float(next["time"]) < 1.0 / Units.YEAR_SECONDS * 60.0, "within a minute of the arrival")


func test_following_the_wave_speeds_time_as_the_front_grows() -> void:
	# The front should cross half the view in a few seconds.
	var small: float = SmartTime.wave_speed(1.0)
	var big: float = SmartTime.wave_speed(30.0)
	assert_almost_eq(small * SmartTime.CROSS_SECONDS * Units.C / Units.YEAR_SECONDS, 1.0, 1e-9, "half a 2 AU view in CROSS_SECONDS")
	assert_almost_eq(big / small, 30.0, 1e-9, "thirty times wider, thirty times faster")


func test_time_eases_down_as_a_front_reaches_a_body() -> void:
	var far: float = SmartTime.arrival_speed(3600.0 * 24.0)
	var near: float = SmartTime.arrival_speed(60.0)
	assert_true(near < far, "slower as the arrival nears")
	assert_almost_eq(near * SmartTime.ARRIVAL_SECONDS, 60.0, 1e-9, "the last minute takes ARRIVAL_SECONDS of play")
	assert_eq(SmartTime.arrival_speed(0.01), SmartTime.MIN_SPEED, "never slower than real time")
	var eased: float = SmartTime.ease_towards(100.0, 1e6, 0.5)
	assert_almost_eq(eased, 100.0 * pow(SmartTime.MAX_CHANGE_PER_SECOND, 0.5), 1e-6, "speeds change smoothly, not in jumps")
	assert_eq(SmartTime.ease_towards(100.0, 10.0, 10.0), 10.0, "but reach what they aim for")
