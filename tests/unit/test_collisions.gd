extends TestCase
## Bodies that touch merge: the heavier one (or a black hole) takes the
## other's mass and momentum, and the news spreads at the speed of light,
## so the far field does not jump. The game resolves collisions as time
## runs, without getting stuck on them.

const SOLAR_SYSTEM: String = "res://data/presets/solar_system.json"
const START: float = 26.81
const EARTH_MASS: float = Units.EARTH_MASS_KG / Units.SOLAR_MASS_KG


static func _simulation() -> Simulation:
	var system: StarSystem = (PresetLoader.load_file(SOLAR_SYSTEM) as Dictionary)["system"]
	var simulation: Simulation = Simulation.new(system, SimClock.load_default(START))
	simulation.max_usec_per_frame = 1 << 30
	return simulation


static func _body(id: StringName, kind: CelestialBody.Kind, mass: float, radius_km: float) -> CelestialBody:
	var b: CelestialBody = CelestialBody.new()
	b.id = id
	b.name_key = "BODY_" + String(id).to_upper()
	b.kind = kind
	b.mass = mass
	b.radius = Units.au_from_km(radius_km)
	if kind == CelestialBody.Kind.STAR:
		b.luminosity = 1.0
		b.temperature = 5772.0
	return b


## Half an Earth just off the Earth, heading straight at it at 10 km/s.
static func _impactor(simulation: Simulation) -> int:
	var earth: int = simulation.system.index_of(&"earth")
	var b: int = earth * 3
	var speed: float = Units.au_from_km(10.0) * Units.YEAR_SECONDS
	var state: NBodyState = simulation.state
	return simulation.place_body(
		_body(&"impactor", CelestialBody.Kind.PLANET, 0.5 * EARTH_MASS, 0.8 * 6371.0),
		state.view_pos[b] + 0.001, state.view_pos[b + 1], state.view_pos[b + 2],
		state.view_vel[b] - speed, state.view_vel[b + 1], state.view_vel[b + 2], "FRONT_PLACED"
	)


func test_a_merger_keeps_mass_and_momentum() -> void:
	var simulation: Simulation = _simulation()
	simulation.clock.paused = true
	var earth: int = simulation.system.index_of(&"earth")
	var other: int = _impactor(simulation)
	var state: NBodyState = simulation.state
	var m1: float = state.final_mass(earth)
	var m2: float = state.final_mass(other)
	var expected_v: float = (m1 * state.vel[earth * 3] + m2 * state.vel[other * 3]) / (m1 + m2)
	var expected_x: float = (m1 * state.pos[earth * 3] + m2 * state.pos[other * 3]) / (m1 + m2)
	var bodies: int = state.body_count()
	var survivor: int = simulation.merge(earth, other, "FRONT_MERGED")
	assert_eq(survivor, earth, "the heavier Earth keeps its name")
	assert_almost_eq(state.final_mass(earth), m1 + m2, 1e-20, "all of the mass")
	assert_almost_eq(state.vel[earth * 3], expected_v, 1e-12, "all of the momentum")
	assert_almost_eq(state.pos[earth * 3], expected_x, 1e-15, "at the centre of mass")
	assert_almost_eq(state.radius[earth], Units.au_from_km(6371.0 * pow(1.512, 1.0 / 3.0)), 1e-12, "the volumes add up")
	assert_almost_eq(simulation.system.body(earth).mass, m1 + m2, 1e-20, "the body says so too")
	assert_false(simulation.is_present(other), "the other is gone")
	assert_eq(state.body_count(), bodies + 1, "a ghost keeps the Earth's old path")
	assert_eq(simulation.parent_of(simulation.system.index_of(&"moon")), earth, "the Moon still circles the Earth")


func test_far_away_a_merger_is_felt_only_as_it_was() -> void:
	var simulation: Simulation = _simulation()
	simulation.clock.paused = true
	var earth: int = simulation.system.index_of(&"earth")
	var other: int = _impactor(simulation)
	var state: NBodyState = simulation.state
	var neptune: int = simulation.system.index_of(&"neptune")
	var n: PackedFloat64Array = state.view_pos.slice(neptune * 3, neptune * 3 + 3)
	var felt_before: float = state.mass_felt_at(earth, n[0], n[1], n[2], state.time) + state.mass_felt_at(other, n[0], n[1], n[2], state.time)
	var bodies: int = state.body_count()
	simulation.merge(earth, other, "FRONT_MERGED")
	var felt_after: float = 0.0
	for i: int in state.body_count():
		if i == earth or i == other or i >= bodies:
			felt_after += state.mass_felt_at(i, n[0], n[1], n[2], state.time)
	assert_almost_eq(felt_after, felt_before, 1e-20, "Neptune still feels the two as they were")
	var e: PackedFloat64Array = state.pos.slice(earth * 3, earth * 3 + 3)
	assert_almost_eq(state.mass_felt_at(earth, e[0], e[1], e[2], state.time), 1.5 * EARTH_MASS, EARTH_MASS * 0.01, "right there the merged body pulls at once")


func test_a_black_hole_swallows_a_star() -> void:
	var simulation: Simulation = _simulation()
	simulation.clock.paused = true
	simulation.light_speed = INF
	var hole: int = simulation.place_body(
		_body(&"hole", CelestialBody.Kind.BLACK_HOLE, 0.5, 1.5), 0.0, 0.01, 0.0, 0.0, 0.0, 0.0, "FRONT_PLACED"
	)
	var survivor: int = simulation.merge(0, hole, "FRONT_MERGED")
	var b: CelestialBody = simulation.system.body(survivor)
	assert_eq(survivor, hole, "the black hole wins, though lighter than the Sun")
	assert_eq(b.kind, CelestialBody.Kind.BLACK_HOLE)
	assert_eq(simulation.state.mass[hole], 1.5, "it takes the Sun's mass")
	assert_eq(simulation.state.final_light(hole), 0.0, "and gives no light")
	assert_eq(simulation.state.mode[0], Gravity.Mode.GONE, "the Sun is gone at once (instant light)")
	assert_almost_eq(Units.km_from_au(simulation.state.radius[hole]), 2.953 * 1.5, 0.01, "its horizon grows with its mass")


func test_two_stars_make_a_brighter_one() -> void:
	var simulation: Simulation = _simulation()
	simulation.clock.paused = true
	simulation.light_speed = INF
	var star: int = simulation.place_body(
		_body(&"twin", CelestialBody.Kind.STAR, 1.0, 695700.0), 0.0, 0.004, 0.0, 0.0, 0.0, 0.0, "FRONT_PLACED"
	)
	var survivor: int = simulation.merge(0, star, "FRONT_MERGED")
	assert_eq(survivor, 0, "equal masses: the first keeps its name")
	assert_almost_eq(simulation.state.final_light(0), pow(2.0, 3.5), 1e-9, "twice the mass, about eleven times the light")
	assert_almost_eq(simulation.system.body(0).luminosity, pow(2.0, 3.5), 1e-9)


func test_time_runs_through_a_collision() -> void:
	var simulation: Simulation = _simulation()
	var earth: int = simulation.system.index_of(&"earth")
	var other: int = _impactor(simulation)
	# 150,000 km at 10 km/s: about four hours. Run a day.
	simulation.clock.use_preset("4")
	var target: float = simulation.clock.time + 1.0 / Units.YEAR_DAYS
	for frame: int in 60:
		simulation.advance(1.0 / 60.0)
	assert_false(simulation.lagging, "not held up by the collision")
	assert_almost_eq(simulation.clock.time, target, 1e-12, "a day later")
	assert_false(simulation.is_present(other), "the impactor merged into the Earth")
	assert_almost_eq(simulation.state.final_mass(earth), 1.5 * EARTH_MASS, EARTH_MASS * 0.01, "which now has both masses")
	var merges: Array[Dictionary] = []
	for event: Dictionary in simulation.events:
		if event["kind"] == "merge":
			merges.append(event)
	assert_eq(merges.size(), 1, "one merger reported")
	assert_eq(merges[0]["body"], earth)
	assert_eq(merges[0]["other"], other)


func test_without_collisions_bodies_pass_through() -> void:
	var simulation: Simulation = _simulation()
	simulation.state.collisions_enabled = false
	var other: int = _impactor(simulation)
	simulation.clock.use_preset("4")
	for frame: int in 60:
		simulation.advance(1.0 / 60.0)
	assert_true(simulation.is_present(other), "the world law turned collisions off")


## A Moon-like moon on a circular orbit this far (km) from the Earth.
static func _moon_at(simulation: Simulation, km: float) -> int:
	var earth: int = simulation.system.index_of(&"earth")
	var b: int = earth * 3
	var state: NBodyState = simulation.state
	var x: float = state.view_pos[b] + Units.au_from_km(km)
	var v: PackedFloat64Array = simulation.circular_velocity(x, state.view_pos[b + 1], state.view_pos[b + 2], 0.0123 * EARTH_MASS)
	return simulation.place_body(
		_body(&"close_moon", CelestialBody.Kind.MOON, 0.0123 * EARTH_MASS, 1737.0),
		x, state.view_pos[b + 1], state.view_pos[b + 2], v[0], v[1], v[2], "FRONT_PLACED"
	)


func test_a_moon_inside_the_roche_limit_becomes_a_ring() -> void:
	var simulation: Simulation = _simulation()
	var earth: int = simulation.system.index_of(&"earth")
	# The Moon's Roche limit around the Earth is about 9,500 km.
	var moon: int = _moon_at(simulation, 9000.0)
	var mass: float = simulation.state.final_mass(earth) + simulation.state.final_mass(moon)
	# A minute: a few of the kernel's steps.
	simulation.clock.use_preset("2")
	for frame: int in 60:
		simulation.advance(1.0 / 60.0)
	assert_false(simulation.is_present(moon), "the moon is torn apart")
	var rings: Array[Dictionary] = simulation.system.body(earth).rings
	assert_eq(rings.size(), 1, "into a ring around the Earth")
	if rings.size() == 1:
		var middle: float = Units.km_from_au(0.5 * (float(rings[0]["inner"]) + float(rings[0]["outer"])))
		assert_almost_eq(middle, 9000.0, 1500.0, "where it was (%s km)" % middle)
		assert_true(float(rings[0]["inner"]) > simulation.state.radius[earth], "above the surface")
	assert_almost_eq(simulation.state.final_mass(earth), mass, 1e-20, "its mass stays with the Earth, as a ring")
	assert_almost_eq(Units.km_from_au(simulation.state.radius[earth]), 6371.0, 1e-6, "the Earth itself does not grow")
	var torn: bool = false
	for event: Dictionary in simulation.events:
		torn = torn or (event["kind"] == "disrupt" and event["body"] == earth and event["other"] == moon)
	assert_true(torn, "reported")


func test_a_moon_outside_the_roche_limit_stays_whole() -> void:
	var simulation: Simulation = _simulation()
	var moon: int = _moon_at(simulation, 12000.0)
	simulation.clock.use_preset("2")
	for frame: int in 30:
		simulation.advance(1.0 / 60.0)
	assert_true(simulation.is_present(moon), "12,000 km out the moon holds together")


func test_the_real_moons_are_not_torn_apart() -> void:
	var simulation: Simulation = _simulation()
	simulation.leave_pristine()
	simulation.clock.use_preset("4")
	for frame: int in 30:
		simulation.advance(1.0 / 60.0)
	for i: int in simulation.system.size():
		assert_true(simulation.is_present(i), "%s is whole (Phobos too, at 2.8 Mars radii)" % simulation.system.body(i).id)
	assert_true(simulation.events.is_empty(), "nothing happened")


func test_a_star_too_close_to_a_black_hole_is_torn_apart() -> void:
	var simulation: Simulation = _simulation()
	simulation.clock.paused = true
	# A 10 M☉ black hole tears the Sun apart within about 2.7 solar radii.
	var hole: int = simulation.place_body(
		_body(&"hole", CelestialBody.Kind.BLACK_HOLE, 10.0, 29.5), 0.012, 0.0, 0.0, 0.0, 0.0, 0.0, "FRONT_PLACED"
	)
	simulation.clock.paused = false
	simulation.clock.use_preset("3")
	for frame: int in 60:
		simulation.advance(1.0 / 60.0)
	assert_false(simulation.is_present(0), "the Sun is torn apart")
	assert_eq(simulation.system.body(hole).rings.size(), 1, "into a ring around the black hole")


func test_a_small_body_striking_a_planet_is_reported() -> void:
	var simulation: Simulation = _simulation()
	simulation.leave_pristine()
	var earth: int = simulation.system.index_of(&"earth")
	var b: int = earth * 3
	var speed: float = Units.au_from_km(20.0) * Units.YEAR_SECONDS
	var state: NBodyState = simulation.state
	var rock: int = state.add_particle(
		state.view_pos[b] + 0.002, state.view_pos[b + 1], state.view_pos[b + 2],
		state.view_vel[b] - speed, state.view_vel[b + 1], state.view_vel[b + 2], 1e-9, Gravity.ParticleKind.ASTEROID
	)
	simulation.clock.use_preset("4")
	for frame: int in 60:
		simulation.advance(1.0 / 60.0)
	var impacts: Array[Dictionary] = simulation.events.filter(func(event: Dictionary) -> bool: return event["kind"] == "impact")
	assert_eq(impacts.size(), 1, "one impact")
	if impacts.size() == 1:
		assert_eq(impacts[0]["body"], earth, "on the Earth")
		assert_eq(impacts[0]["particle"], rock, "by the asteroid")
