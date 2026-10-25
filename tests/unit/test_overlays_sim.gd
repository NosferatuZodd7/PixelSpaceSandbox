extends TestCase
## What the Tools tab's overlays need from the simulation: the Lagrange
## points of a body and what it circles, Hill spheres, the system as it
## would have gone without the last change (for ghost trajectories), and
## the light pulse.

const SOLAR_SYSTEM: String = "res://data/presets/solar_system.json"
const START: float = 26.81


static func _simulation(small_bodies: bool = true) -> Simulation:
	var system: StarSystem = (PresetLoader.load_file(SOLAR_SYSTEM) as Dictionary)["system"]
	if not small_bodies:
		system.belts.clear()
		system.comets.clear()
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


static func _distance(points: PackedFloat64Array, k: int, x: float, y: float, z: float) -> float:
	return Vector3(points[k * 3] - x, points[k * 3 + 1] - y, points[k * 3 + 2] - z).length()


func test_the_earth_s_lagrange_points() -> void:
	var simulation: Simulation = _simulation()
	var system: StarSystem = simulation.system
	var earth: int = system.index_of(&"earth")
	var points: PackedFloat64Array = simulation.lagrange_points(earth)
	assert_eq(points.size(), 15, "L1 to L5")
	var ex: float = system.x(earth)
	var ey: float = system.y(earth)
	var ez: float = system.z(earth)
	var r: float = system.distance(0, earth)
	assert_almost_eq(Units.km_from_au(_distance(points, 0, ex, ey, ez)), 1.5e6, 0.05e6, "L1 1.5 million km sunward")
	assert_true(_distance(points, 0, system.x(0), system.y(0), system.z(0)) < r, "between the Earth and the Sun")
	assert_almost_eq(Units.km_from_au(_distance(points, 1, ex, ey, ez)), 1.5e6, 0.05e6, "L2 as far on the other side")
	assert_true(_distance(points, 1, system.x(0), system.y(0), system.z(0)) > r)
	assert_almost_eq(_distance(points, 2, system.x(0), system.y(0), system.z(0)), r, 0.001, "L3 opposite, as far from the Sun")
	for k: int in [3, 4]:
		assert_almost_eq(_distance(points, k, ex, ey, ez), r, 0.001, "L%d makes an equilateral triangle" % (k + 1))
		assert_almost_eq(_distance(points, k, system.x(0), system.y(0), system.z(0)), r, 0.001)
	assert_true(simulation.lagrange_points(0).is_empty(), "the Sun circles nothing")


func test_hill_spheres_are_public() -> void:
	var simulation: Simulation = _simulation()
	var earth: int = simulation.system.index_of(&"earth")
	assert_almost_eq(Units.km_from_au(simulation.hill_radius(earth)), 1.5e6, 0.05e6, "the Earth's Hill sphere, 1.5 million km")
	assert_eq(simulation.hill_radius(0), INF)


func test_the_system_as_it_would_have_gone_runs_alongside() -> void:
	# The copy leaves the small bodies out (awake ones would change the
	# steps), so compare with a system without them.
	var changed: Simulation = _simulation(false)
	var reference: Simulation = _simulation(false)
	reference.leave_pristine()
	changed.keep_alternative = true
	changed.place_body(_star(), 0.0, 3.0, 0.0, 0.0, 0.0, 0.0, "FRONT_PLACED")
	assert_true(changed.alternative != null, "a copy of the system as it was keeps running")
	for simulation: Simulation in [changed, reference]:
		simulation.clock.use_preset("5")
		for frame: int in 60:
			simulation.advance(1.0 / 60.0)
	var earth: int = changed.system.index_of(&"earth")
	var real: PackedFloat64Array = changed.state.view_pos.slice(earth * 3, earth * 3 + 3)
	var would: PackedFloat64Array = changed.alternative.view_pos.slice(earth * 3, earth * 3 + 3)
	var without: PackedFloat64Array = reference.state.view_pos.slice(earth * 3, earth * 3 + 3)
	assert_true(would == without, "the copy is exactly the untouched system")
	assert_true(real != would, "the real Earth has felt the new star")
	changed.keep_alternative = false
	changed.advance(1.0 / 60.0)
	assert_eq(changed.alternative, null, "turning it off drops the copy")


func test_a_light_pulse_carries_only_light() -> void:
	var simulation: Simulation = _simulation()
	var earth: int = simulation.system.index_of(&"earth")
	var front: int = simulation.light_pulse(earth)
	assert_eq(simulation.fronts.size(), 1, "a ring of light leaves the Earth")
	var pulse: WaveFront = simulation.fronts[front]
	assert_true(pulse.light and not pulse.gravity, "light only")
	assert_eq(pulse.label_key, "FRONT_PULSE")
	assert_true(simulation.state.delta_body.is_empty() and simulation.state.light_body.is_empty(), "it changes nothing")
	assert_true(simulation.is_pristine(), "the system stays untouched")
