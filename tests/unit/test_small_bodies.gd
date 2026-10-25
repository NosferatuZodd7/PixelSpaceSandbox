extends TestCase
## Small bodies from the preset: the asteroid belt with its Kirkwood gaps,
## the Kuiper belt and plutinos, the Oort cloud, and real comets, as
## particles riding their orbits; the same every time.

const SOLAR_SYSTEM: String = "res://data/presets/solar_system.json"
## 2026-10-25 12:00 UTC, in years since J2000.0.
const START: float = 26.81


static func _simulation() -> Simulation:
	var system: StarSystem = (PresetLoader.load_file(SOLAR_SYSTEM) as Dictionary)["system"]
	var simulation: Simulation = Simulation.new(system, SimClock.load_default(START))
	simulation.max_usec_per_frame = 1 << 30
	return simulation


static func _of_kind(simulation: Simulation, kind: Gravity.ParticleKind) -> PackedInt32Array:
	var found: PackedInt32Array = []
	for p: int in simulation.state.particle_count():
		if simulation.state.p_kind[p] == kind:
			found.append(p)
	return found


## Distance of a particle from the Sun where it is shown.
static func _distance(simulation: Simulation, p: int) -> float:
	var v: PackedFloat64Array = simulation.state.p_view
	var s: PackedFloat64Array = simulation.state.view_pos
	return Vector3(v[p * 3] - s[0], v[p * 3 + 1] - s[1], v[p * 3 + 2] - s[2]).length()


func test_the_preset_lists_its_belts_and_comets() -> void:
	var loaded: Dictionary = PresetLoader.load_file(SOLAR_SYSTEM)
	var errors: PackedStringArray = loaded["errors"]
	assert_true(errors.is_empty(), "; ".join(errors))
	var system: StarSystem = loaded["system"]
	assert_eq(system.belts.size(), 4, "asteroid belt, Kuiper belt, plutinos, Oort cloud")
	assert_eq(system.comets.size(), 3, "Halley, Encke, Hale-Bopp")


func test_the_solar_system_has_its_small_bodies() -> void:
	var simulation: Simulation = _simulation()
	assert_eq(_of_kind(simulation, Gravity.ParticleKind.ASTEROID).size(), 1200, "asteroids")
	assert_eq(_of_kind(simulation, Gravity.ParticleKind.ICY).size(), 850, "Kuiper belt objects and plutinos")
	assert_eq(_of_kind(simulation, Gravity.ParticleKind.OORT).size(), 600, "Oort cloud")
	assert_eq(_of_kind(simulation, Gravity.ParticleKind.COMET).size(), 3, "comets")
	for p: int in simulation.state.particle_count():
		if simulation.state.p_mode[p] != Gravity.ParticleMode.ASLEEP:
			fail("particle %d starts awake" % p)
			break


func test_asteroids_fill_the_belt_but_not_its_gaps() -> void:
	var simulation: Simulation = _simulation()
	var gaps: Array[Vector2] = [Vector2(2.47, 2.53), Vector2(2.80, 2.86), Vector2(2.94, 2.98)]
	var in_gap: int = 0
	var inner: float = INF
	var outer: float = 0.0
	for p: int in _of_kind(simulation, Gravity.ParticleKind.ASTEROID):
		var a: float = simulation.state.p_elem[p * Gravity.ELEMENT_SIZE]
		for gap: Vector2 in gaps:
			if a > gap.x and a < gap.y:
				in_gap += 1
		var d: float = _distance(simulation, p)
		inner = minf(inner, d)
		outer = maxf(outer, d)
	assert_eq(in_gap, 0, "the Kirkwood gaps are empty")
	assert_true(inner > 2.1 * 0.75 - 0.01 and outer < 3.3 * 1.25 + 0.01, "between Mars and Jupiter (%s–%s AU)" % [inner, outer])


func test_the_oort_cloud_is_far_out() -> void:
	var simulation: Simulation = _simulation()
	var nearest: float = INF
	var above: int = 0
	for p: int in _of_kind(simulation, Gravity.ParticleKind.OORT):
		nearest = minf(nearest, _distance(simulation, p))
		if simulation.state.p_view[p * 3 + 2] > 0.0:
			above += 1
	assert_true(nearest > 2000.0 * 0.4 - 1.0, "nothing closer than 800 AU (%s)" % nearest)
	assert_true(above > 200 and above < 400, "a sphere, not a disc: %d of 600 above the ecliptic" % above)


func test_small_bodies_are_the_same_every_time() -> void:
	var a: Simulation = _simulation()
	var b: Simulation = _simulation()
	assert_true(a.state.p_elem == b.state.p_elem, "same orbits")
	assert_true(a.state.p_view == b.state.p_view, "same places")


func test_halleys_comet_is_far_out_near_its_aphelion() -> void:
	var simulation: Simulation = _simulation()
	var halley: int = simulation.particle_named("BODY_HALLEY")
	assert_ne(halley, -1, "Halley's comet is there")
	var d: float = _distance(simulation, halley)
	# Aphelion (35.1 AU) was in December 2023; in late 2026 it is falling back.
	assert_true(d > 34.0 and d < 35.1, "about 34.5 AU from the Sun (%s)" % d)
	var encke: int = simulation.particle_named("BODY_ENCKE")
	var elements: PackedFloat64Array = simulation.state.p_elem.slice(encke * Gravity.ELEMENT_SIZE, (encke + 1) * Gravity.ELEMENT_SIZE)
	assert_almost_eq(elements[0] * (1.0 - elements[1]), 0.336, 0.001, "Encke dives to 0.34 AU from the Sun")


func test_small_bodies_ride_their_orbits_as_time_runs() -> void:
	var simulation: Simulation = _simulation()
	var asteroid: int = _of_kind(simulation, Gravity.ParticleKind.ASTEROID)[0]
	var before: PackedFloat64Array = simulation.state.p_view.slice(asteroid * 3, asteroid * 3 + 3)
	simulation.clock.use_preset("6")
	for frame: int in 30:
		simulation.advance(1.0 / 60.0)
	var after: PackedFloat64Array = simulation.state.p_view.slice(asteroid * 3, asteroid * 3 + 3)
	assert_true(before != after, "a month later the asteroid has moved")
	var d: float = _distance(simulation, asteroid)
	assert_true(d > 1.5 and d < 4.2, "and is still in the belt (%s AU)" % d)
