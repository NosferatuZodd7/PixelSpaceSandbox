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
	var drift: PackedFloat64Array = reference.leave_pristine()
	var jupiter: int = changed.system.index_of(&"jupiter")
	var bodies: int = changed.state.body_count()
	changed.fling(jupiter, 0.0, 0.0, 0.0, "FRONT_FLUNG")
	assert_eq(changed.system.index_of(&"jupiter"), jupiter, "still the same Jupiter")
	assert_eq(changed.state.body_count(), bodies + 1, "a ghost keeps its old path")
	assert_eq(changed.state.mode[bodies], Gravity.Mode.GHOST, "the ghost")
	# Stopped as seen when it was flung: the first change also puts the
	# system's centre of mass at rest, which every velocity follows.
	assert_eq(changed.state.vel[jupiter * 3], -drift[0], "Jupiter stopped dead")
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


static func _small_moon() -> CelestialBody:
	var moon: CelestialBody = CelestialBody.new()
	moon.id = &"new_moon"
	moon.name_key = "BODY_NEW_MOON"
	moon.kind = CelestialBody.Kind.MOON
	moon.mass = 1e-12
	moon.radius = Units.au_from_km(100.0)
	return moon


func test_integrated_bodies_keep_what_they_circle() -> void:
	var simulation: Simulation = _simulation()
	simulation.clock.paused = true
	simulation.leave_pristine()
	var system: StarSystem = simulation.system
	assert_eq(simulation.parent_of(system.index_of(&"earth")), system.index_of(&"sun"), "the Earth circles the Sun")
	assert_eq(simulation.parent_of(system.index_of(&"moon")), system.index_of(&"earth"), "the Moon circles the Earth")
	assert_eq(simulation.parent_of(0), -1, "the Sun circles nothing")
	var elements: PackedFloat64Array = simulation.orbit_elements(system.index_of(&"mars"))
	assert_almost_eq(elements[0], 1.524, 0.01, "Mars's orbit is 1.52 AU across")
	assert_almost_eq(elements[1], 0.093, 0.005, "with its eccentricity")
	assert_true(simulation.orbit_elements(0).is_empty(), "no orbit for the Sun")


func test_a_placed_body_shows_its_orbit_at_once() -> void:
	var simulation: Simulation = _simulation()
	simulation.clock.paused = true
	var system: StarSystem = simulation.system
	var earth: int = system.index_of(&"earth")
	var r: float = 0.0006
	var x: float = system.x(earth) + r
	var v: PackedFloat64Array = simulation.circular_velocity(x, system.y(earth), system.z(earth))
	var moon: int = simulation.place_body(_small_moon(), x, system.y(earth), system.z(earth), v[0], v[1], v[2], "FRONT_PLACED")
	assert_eq(simulation.parent_of(moon), earth, "it circles the Earth, even before time runs")
	var elements: PackedFloat64Array = simulation.orbit_elements(moon)
	assert_almost_eq(elements[0], r, r * 0.01, "on a 90,000 km orbit")
	assert_true(elements[1] < 0.01, "a circle (e = %s)" % elements[1])


func test_a_rogue_planet_flies_through_and_away() -> void:
	var simulation: Simulation = _simulation()
	simulation.clock.paused = true
	var v: PackedFloat64Array = simulation.flyby_velocity(3.0, 0.0, 0.0, Units.au_from_km(20.0) * Units.YEAR_SECONDS)
	var rogue: int = simulation.place_body(_small_moon(), 3.0, 0.0, 0.0, v[0], v[1], v[2], "FRONT_PLACED")
	assert_eq(simulation.parent_of(rogue), 0, "the Sun bends its path")
	var elements: PackedFloat64Array = simulation.orbit_elements(rogue)
	assert_true(elements[0] < 0.0 and elements[1] > 1.0, "on an open path: it leaves again (a %s, e %s)" % [elements[0], elements[1]])
	var periapsis: float = absf(elements[0]) * (elements[1] - 1.0)
	assert_almost_eq(periapsis, 3.0, 0.01, "closest to the Sun where it was placed")


func test_a_new_star_can_be_circled_at_once() -> void:
	var simulation: Simulation = _simulation()
	simulation.clock.paused = true
	var star: int = simulation.place_body(_sun_like_star(), 0.0, 30.0, 0.0, 0.0, 0.0, 0.0, "FRONT_PLACED")
	assert_eq(simulation.dominant_body(0.0, 30.05, 0.0), star, "close to the new star, before its news has spread")
	var v: PackedFloat64Array = simulation.circular_velocity(0.0, 30.05, 0.0, 1e-6)
	var dvx: float = v[0] - simulation.state.view_vel[star * 3]
	var dvy: float = v[1] - simulation.state.view_vel[star * 3 + 1]
	var speed: float = sqrt(dvx * dvx + dvy * dvy)
	assert_almost_eq(speed, sqrt(Units.G * (1.0 + 1e-6) / 0.05), 1e-9, "the circular speed counts both masses")


func test_two_stars_circle_each_other() -> void:
	var simulation: Simulation = _simulation()
	simulation.clock.paused = true
	var v: PackedFloat64Array = simulation.circular_velocity(0.0, 3.0, 0.0, 1.0)
	var star: int = simulation.place_body(_sun_like_star(), 0.0, 3.0, 0.0, v[0], v[1], v[2], "FRONT_PLACED")
	assert_eq(simulation.parent_of(star), 0, "it circles the Sun")
	var elements: PackedFloat64Array = simulation.orbit_elements(star)
	assert_true(elements[1] < 0.01, "on a circle, both stars' masses counted (e = %s)" % elements[1])


func test_starlight_arrives_from_every_star() -> void:
	var simulation: Simulation = _simulation()
	simulation.clock.paused = true
	var e: PackedFloat64Array = _position(simulation, &"earth")
	var d: float = Vector3(e[0], e[1], e[2]).length()
	assert_almost_eq(simulation.flux_at(e[0], e[1], e[2]), 1.0 / (d * d), 1e-3, "sunlight at the Earth")
	assert_eq(simulation.main_star_at(e[0], e[1], e[2]), 0, "from the Sun")
	var star: int = simulation.place_body(_sun_like_star(), e[0] + 0.5, e[1], e[2], 0.0, 0.0, 0.0, "FRONT_PLACED")
	assert_almost_eq(simulation.flux_at(e[0], e[1], e[2]), 1.0 / (d * d), 1e-3, "the new star's light has not arrived yet")
	simulation.clock.paused = false
	_run([simulation], 5.0, "2")
	e = _position(simulation, &"earth")
	assert_eq(simulation.main_star_at(e[0], e[1], e[2]), star, "four minutes later the close new star outshines the Sun")
	assert_true(simulation.flux_at(e[0], e[1], e[2]) > 3.0, "the Earth gets far more light")
	simulation.remove_body(0, "FRONT_REMOVED")
	simulation.remove_body(star, "FRONT_REMOVED")
	_run([simulation], 1.0, "4")
	e = _position(simulation, &"earth")
	assert_eq(simulation.flux_at(e[0], e[1], e[2]), 0.0, "darkness once both are gone")
	assert_eq(simulation.main_star_at(e[0], e[1], e[2]), -1)
	assert_eq(simulation.state.mode[star], Gravity.Mode.GONE, "the new star is gone")
	assert_eq(simulation.state.mass[star], 0.0, "with all of its mass, though its arrival was still on its way")


func test_a_body_flung_before_its_news_spread_keeps_all_of_it() -> void:
	var simulation: Simulation = _simulation()
	var star: int = simulation.place_body(_sun_like_star(), 0.0, 3.0, 0.0, 0.0, 0.0, 0.0, "FRONT_PLACED")
	# An hour later the Earth (2 to 4 AU away) has heard of the star, Neptune not yet.
	_run([simulation], 60.0, "2")
	simulation.fling(star, 1.0, 0.0, 0.0, "FRONT_FLUNG")
	var ghost: int = simulation.state.body_count() - 1
	var t: float = simulation.clock.time
	var e: PackedFloat64Array = _position(simulation, &"earth")
	assert_almost_eq(simulation.state.mass_felt_at(ghost, e[0], e[1], e[2], t), 1.0, 1e-12, "the Earth feels the star on its old path")
	assert_almost_eq(simulation.state.mass_felt_at(star, e[0], e[1], e[2], t), 0.0, 1e-12, "not yet on its new one")
	var n: PackedFloat64Array = _position(simulation, &"neptune")
	assert_almost_eq(simulation.state.mass_felt_at(ghost, n[0], n[1], n[2], t), 0.0, 1e-12, "Neptune has not heard of the star at all")
	assert_almost_eq(simulation.state.mass_felt_at(star, n[0], n[1], n[2], t), 0.0, 1e-12)
	_run([simulation], 1.0, "4")
	assert_true(simulation.fronts.is_empty(), "a day later all the news has spread")
	assert_eq(simulation.state.mass[star], 1.0, "the flung star has its whole mass")
	assert_eq(simulation.state.mode[ghost], Gravity.Mode.GONE, "its ghost is gone")
	assert_eq(simulation.state.mass[ghost], 0.0)


func test_the_moons_of_a_removed_planet_circle_its_star() -> void:
	var simulation: Simulation = _simulation()
	simulation.clock.paused = true
	var system: StarSystem = simulation.system
	simulation.remove_body(system.index_of(&"mars"), "FRONT_REMOVED")
	assert_eq(simulation.parent_of(system.index_of(&"phobos")), 0, "Phobos now circles the Sun")
	assert_eq(simulation.dominant_body(-2.0, 1.0, 0.0), 0, "and does not take over the inner system")


func test_a_point_on_screen_lies_in_the_plane_of_what_it_would_circle() -> void:
	var simulation: Simulation = _simulation()
	var system: StarSystem = simulation.system
	var earth: int = system.index_of(&"earth")
	var point: PackedFloat64Array = simulation.point_in_plane(system.x(earth) + 6e-5, system.y(earth))
	assert_eq(point[2], system.z(earth), "at the Earth's height, which is not the ecliptic's (the Moon pulls it off)")
	assert_eq(simulation.dominant_body(point[0], point[1], point[2]), earth)
	point = simulation.point_in_plane(3.0, 0.0)
	assert_eq(point[2], system.z(0), "in the asteroid belt, at the Sun's height")


func test_world_laws_change_the_rules() -> void:
	var simulation: Simulation = _simulation()
	simulation.set_light_slowdown(1000.0)
	assert_almost_eq(simulation.light_speed, Units.C / 1000.0, 1e-9, "light a thousand times slower (fiction)")
	simulation.set_light_slowdown(INF)
	assert_eq(simulation.light_speed, INF, "or instant, the classic sandbox")
	simulation.set_light_slowdown(1.0)
	assert_eq(simulation.light_speed, Units.C, "or real")
	simulation.set_collisions(false)
	assert_false(simulation.state.collisions_enabled, "collisions off")
	assert_true(simulation.is_pristine(), "rules alone do not disturb the untouched system")
	simulation.set_gravity_scale(2.0)
	assert_eq(simulation.state.g_scale, 2.0, "gravity twice as strong")
	assert_false(simulation.is_pristine(), "which changes every orbit, so the system runs on gravity from now on")
	var earth: int = simulation.system.index_of(&"earth")
	var before: PackedFloat64Array = _position(simulation, &"earth")
	simulation.clock.use_preset("6")
	for frame: int in 60:
		simulation.advance(1.0 / 60.0)
	var r: float = Vector3(simulation.system.x(earth), simulation.system.y(earth), simulation.system.z(earth)).length()
	assert_true(r < 0.99, "the Earth falls inwards under the stronger pull (%s AU)" % r)
	assert_true(before.size() == 3)


## The screen shows a moment between the kernel's steps. A body placed
## there starts from where it is shown, with its velocity: it does not
## jump, and a throw lands where it was aimed.
func test_a_new_body_starts_at_the_moment_shown() -> void:
	var simulation: Simulation = _simulation()
	simulation.leave_pristine()
	for frame: int in 7:
		simulation.advance(1.0 / 60.0)
	assert_true(simulation.clock.time > simulation.state.time, "the shown moment is past the last step")
	var star: int = simulation.place_body(_sun_like_star(), 3.0, 1.0, 0.0, -8.0, 4.0, 0.0, "FRONT_PLACED")
	simulation.advance(0.0)
	var placed: PackedFloat64Array = simulation.state.view_pos.slice(star * 3, star * 3 + 3)
	assert_almost_eq(placed[0], 3.0, 1e-9, "the new body is where it was put")
	assert_almost_eq(placed[1], 1.0, 1e-9)
	var velocity: PackedFloat64Array = simulation.state.view_vel.slice(star * 3, star * 3 + 3)
	assert_almost_eq(velocity[0], -8.0, 1e-3, "moving as it was thrown")
	assert_almost_eq(velocity[1], 4.0, 1e-3)


## The first change switches the system from its real orbits to gravity,
## seen from the centre of mass: a body placed then moves as it was thrown
## relative to the others, not with the old frame's drift.
func test_the_first_change_keeps_a_new_body_moving_as_thrown() -> void:
	var simulation: Simulation = _simulation()
	simulation.advance(1.0 / 60.0)
	var earth: int = simulation.system.index_of(&"earth")
	var e: int = earth * 3
	var x: float = simulation.state.view_pos[e] + 0.002
	var y: float = simulation.state.view_pos[e + 1]
	var z: float = simulation.state.view_pos[e + 2]
	var v: PackedFloat64Array = simulation.circular_velocity(x, y, z, 0.0)
	var wanted: Vector3 = Vector3(v[0] - simulation.state.view_vel[e], v[1] - simulation.state.view_vel[e + 1], v[2] - simulation.state.view_vel[e + 2])
	var moon: CelestialBody = _sun_like_star()
	moon.kind = CelestialBody.Kind.MOON
	moon.mass = 1e-12
	moon.luminosity = 0.0
	moon.radius = Units.au_from_km(100.0)
	var index: int = simulation.place_body(moon, x, y, z, v[0], v[1], v[2], "FRONT_PLACED")
	simulation.advance(0.0)
	var m: int = index * 3
	var got: Vector3 = Vector3(simulation.state.view_vel[m] - simulation.state.view_vel[e], simulation.state.view_vel[m + 1] - simulation.state.view_vel[e + 1], simulation.state.view_vel[m + 2] - simulation.state.view_vel[e + 2])
	assert_true((got - wanted).length() < 1e-6, "relative to the Earth as thrown (off by %s AU/yr)" % (got - wanted).length())


## A body thrown at a giant from close by, even slowly, is aimed so that it
## hits it, and soon: an aimed throw arrives within a month.
func test_an_aimed_throw_hits_a_giant_soon() -> void:
	var simulation: Simulation = _simulation()
	simulation.advance(1.0 / 60.0)
	var jupiter: int = simulation.system.index_of(&"jupiter")
	var j: int = jupiter * 3
	var x: float = simulation.state.view_pos[j] + 0.2
	var y: float = simulation.state.view_pos[j + 1] + 0.1
	var z: float = simulation.state.view_pos[j + 2]
	var giant: CelestialBody = _sun_like_star()
	giant.kind = CelestialBody.Kind.PLANET
	giant.mass = Units.solar_masses_from_kg(318.0 * Units.EARTH_MASS_KG)
	giant.radius = Units.au_from_km(69911.0)
	giant.luminosity = 0.0
	var slow: float = Units.au_from_km(3.3) * Units.YEAR_SECONDS
	var v: PackedFloat64Array = simulation.intercept_velocity(jupiter, x, y, z, slow, giant.mass)
	var thrown: int = simulation.place_body(giant, x, y, z, v[0], v[1], v[2], "FRONT_PLACED")
	var start: float = simulation.clock.time
	simulation.clock.use_preset("5")
	while simulation.is_present(thrown) and simulation.is_present(jupiter) and simulation.clock.time - start < 45.0 / Units.YEAR_DAYS:
		simulation.advance(1.0 / 60.0)
	assert_false(simulation.is_present(thrown) and simulation.is_present(jupiter), "they collided within 45 days")
