class_name BenchmarkScenario
extends RefCounted
## The milestone 2 performance scene, as the brief sets it for the low
## profile: 4 stars, 12 planets, 20 moons, 2,000 particles and 10 fronts
## still travelling, run at ×1,000,000 (16,667 simulated seconds, about
## 4.6 hours, per frame at 60 frames per second). Built from a seed, so
## every run measures exactly the same thing.
##
## Layout: a sun-like star with 8 planets and an asteroid belt; a second
## star 80 AU away with 4 planets; a distant pair of red dwarfs. Of the six
## gas giants, the first five have four moons each, the innermost on an
## Io-like 1.8-day orbit (the shortest orbit sets the step). This is a test
## fixture, not game content, so it lives here rather than in data/. Ten mass changes travel at
## the speed of light, so every pull goes through the slower path that
## checks which fronts have arrived.

const STARS: int = 4
const PLANETS: int = 12
const MOONS: int = 20
const PARTICLES: int = 2000
const FRONTS: int = 10
## Simulated seconds per real second.
const SPEED: float = 1.0e6
const FRAME_SECONDS: float = 1.0 / 60.0

const JUPITER_MASS: float = 9.546e-4
const EARTH_MASS: float = 3.003e-6
const SUN_RADIUS: float = 0.00465


## Builds the scene. awake_share is the part of the particles that start
## awake (integrated) rather than asleep on their orbits.
static func build(seed_value: int = 2026, awake_share: float = 0.1) -> NBodyState:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var s: NBodyState = NBodyState.new()
	# Stars: A at the centre, B on an 80 AU orbit, and a red-dwarf pair 600 AU out.
	var a: int = s.add_body(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, SUN_RADIUS, Gravity.Mode.FREE, -1)
	var b: int = _add_orbiting(s, a, 80.0, 0.0, 0.6, 0.6 * SUN_RADIUS, 0.3)
	var c: int = _add_orbiting(s, a, 600.0, 0.0, 0.3, 0.3 * SUN_RADIUS, 2.0)
	_add_orbiting(s, c, 20.0, 0.0, 0.2, 0.2 * SUN_RADIUS, 4.0)
	# Planets: 8 around A, 4 around B; the giants carry moons.
	var giants: Array[int] = []
	var around_a: Array[Array] = [
		[0.4, EARTH_MASS * 0.06, 2440.0], [0.7, EARTH_MASS * 0.8, 6050.0], [1.0, EARTH_MASS, 6371.0],
		[1.5, EARTH_MASS * 0.1, 3390.0], [5.2, JUPITER_MASS, 69911.0], [9.5, JUPITER_MASS * 0.3, 58232.0],
		[19.2, JUPITER_MASS * 0.046, 25362.0], [30.0, JUPITER_MASS * 0.054, 24622.0],
	]
	var around_b: Array[Array] = [
		[0.5, EARTH_MASS * 0.5, 5000.0], [1.2, EARTH_MASS * 2.0, 8000.0],
		[3.0, JUPITER_MASS * 0.8, 65000.0], [8.0, JUPITER_MASS * 0.1, 30000.0],
	]
	for entry: Array in around_a:
		var planet: int = _add_orbiting(s, a, entry[0], rng.randf_range(-0.03, 0.03), entry[1], Units.au_from_km(entry[2]), rng.randf() * TAU)
		if entry[1] > JUPITER_MASS * 0.04:
			giants.append(planet)
	for entry: Array in around_b:
		var planet: int = _add_orbiting(s, b, entry[0], rng.randf_range(-0.03, 0.03), entry[1], Units.au_from_km(entry[2]), rng.randf() * TAU)
		if entry[1] > JUPITER_MASS * 0.04:
			giants.append(planet)
	# Moons: four around each of the first five giants, from an Io-like orbit outwards.
	var moons: int = 0
	for giant: int in giants:
		var scale: float = pow(s.mass[giant] / JUPITER_MASS, 1.0 / 3.0)
		for k: int in 4:
			if moons == MOONS:
				break
			var distance: float = Units.au_from_km(421700.0 * pow(1.6, k)) * scale
			_add_orbiting(s, giant, distance, rng.randf_range(-0.02, 0.02), s.mass[giant] * 4e-5, Units.au_from_km(1800.0), rng.randf() * TAU)
			moons += 1
	# The asteroid belt around A.
	for p: int in PARTICLES:
		var semi_major: float = rng.randf_range(2.1, 3.3)
		var state: PackedFloat64Array = Kepler.state_from_elements(
			semi_major, rng.randf_range(0.0, 0.2), deg_to_rad(rng.randf_range(0.0, 15.0)),
			rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU, Kepler.mean_motion(semi_major, 1.0)
		)
		var radius: float = Units.au_from_km(rng.randf_range(0.5, 50.0))
		if rng.randf() < awake_share:
			s.add_particle(state[0], state[1], state[2], state[3], state[4], state[5], radius, 0)
		else:
			var elements: PackedFloat64Array = Kepler.elements_from_state(
				state[0], state[1], state[2], state[3], state[4], state[5], Units.G, s.time
			)
			s.add_sleeping_particle(a, elements, radius, 0)
	# Ten mass changes still travelling: small enough not to disturb the
	# scene, real enough that every pull checks them.
	for f: int in FRONTS:
		var source: int = rng.randi_range(0, s.body_count() - 1)
		s.front_origin.append_array([s.pos[source * 3], s.pos[source * 3 + 1], s.pos[source * 3 + 2]])
		s.front_time.append(s.time - rng.randf_range(0.0, 0.001))
		s.front_speed.append(Units.C)
		s.delta_body.append(source)
		s.delta_front.append(f)
		s.delta_mass.append(s.mass[source] * 1e-9)
	s.acc_valid = false
	return s


## Simulated years per frame at the benchmark speed.
static func frame_years() -> float:
	return SPEED * FRAME_SECONDS / Units.YEAR_SECONDS


## Runs the scene for a number of frames on a kernel and times each frame's
## simulation work: advance() to the frame's time plus preview() of where
## everything is drawn. The first call, which sets the scene up (parents,
## Hill spheres, first pulls), is timed apart. Returns {"times": ms per
## frame, "setup": ms, "steps": total steps}.
static func run(kernel: Object, s: NBodyState, frames: int) -> Dictionary:
	var target: float = s.time
	var setup_start: int = Time.get_ticks_usec()
	kernel.call(&"advance", s, target, 1 << 30, 1 << 30)
	var setup: float = (Time.get_ticks_usec() - setup_start) / 1000.0
	var times: PackedFloat64Array = []
	var steps: int = 0
	for f: int in frames:
		target += frame_years()
		var start: int = Time.get_ticks_usec()
		var result: Dictionary = kernel.call(&"advance", s, target, 1 << 30, 1 << 30)
		kernel.call(&"preview", s, target)
		times.append((Time.get_ticks_usec() - start) / 1000.0)
		steps += int(result["steps"])
	return {"times": times, "setup": setup, "steps": steps}


## Mean, median, 95th percentile and worst of frame times (ms), and the
## frame the worst one was.
static func summarize(times: PackedFloat64Array) -> Dictionary:
	var sorted: PackedFloat64Array = times.duplicate()
	sorted.sort()
	var count: int = sorted.size()
	var total: float = 0.0
	for t: float in times:
		total += t
	return {
		"mean": total / count, "median": sorted[int(count / 2.0)], "p95": sorted[int(count * 0.95)],
		"worst": sorted[count - 1], "worst_frame": times.find(sorted[count - 1]),
	}


## How far apart two runs of the scene ended: the largest coordinate
## difference for bodies and for particles (AU), and whether every particle
## is asleep or awake alike.
static func compare(a: NBodyState, b: NBodyState) -> Dictionary:
	var body_gap: float = 0.0
	for k: int in mini(a.pos.size(), b.pos.size()):
		body_gap = maxf(body_gap, absf(a.pos[k] - b.pos[k]))
	var particle_gap: float = 0.0
	for k: int in mini(a.p_pos.size(), b.p_pos.size()):
		particle_gap = maxf(particle_gap, absf(a.p_pos[k] - b.p_pos[k]))
	return {"bodies": body_gap, "particles": particle_gap, "same_modes": a.p_mode == b.p_mode, "same_time": a.time == b.time}


## A body on a circular orbit around a parent (in the parent's moving frame).
static func _add_orbiting(
	s: NBodyState, parent: int, distance: float, inclination: float, body_mass: float, body_radius: float, angle: float
) -> int:
	var speed: float = sqrt(Units.G * (s.mass[parent] + body_mass) / distance)
	var pb: int = parent * 3
	return s.add_body(
		s.pos[pb] + distance * cos(angle), s.pos[pb + 1] + distance * sin(angle) * cos(inclination),
		s.pos[pb + 2] + distance * sin(angle) * sin(inclination),
		s.vel[pb] - speed * sin(angle), s.vel[pb + 1] + speed * cos(angle) * cos(inclination),
		s.vel[pb + 2] + speed * cos(angle) * sin(inclination),
		body_mass, body_radius, Gravity.Mode.FREE, -1
	)
