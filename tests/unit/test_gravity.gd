extends TestCase
## The gravity kernels (GDScript and, when loaded, native): orbits keep
## their energy, changes travel at the speed of light, a merger keeps the
## far field, sleeping particles follow the same orbits as integrated ones,
## collisions are found, and the same state has the same future however
## the frames fall.

const EARTH_MASS: float = 5.9722e24 / 1.98847e30
const NO_LIMIT: int = 1 << 30


func after_each() -> void:
	Gravity.use_script_kernel = false


## Every kernel available here, by name.
func _kernels() -> Dictionary[String, Object]:
	var kernels: Dictionary[String, Object] = {"script": GravityCoreScript.new()}
	if Gravity.native_available():
		kernels["native"] = ClassDB.instantiate(Gravity.NATIVE_CLASS)
	return kernels


func _advance(kernel: Object, s: NBodyState, t: float) -> Dictionary:
	return kernel.call(&"advance", s, t, NO_LIMIT, NO_LIMIT)


static func _sun_and_earth() -> NBodyState:
	var s: NBodyState = NBodyState.new()
	var v: float = sqrt(Units.G * (1.0 + EARTH_MASS))
	s.add_body(0.0, 0.0, 0.0, 0.0, -v * EARTH_MASS, 0.0, 1.0, Units.au_from_km(695700.0), Gravity.Mode.FREE, -1)
	s.add_body(1.0, 0.0, 0.0, 0.0, v, 0.0, EARTH_MASS, Units.au_from_km(6371.0), Gravity.Mode.FREE, -1)
	return s


static func _energy(s: NBodyState) -> float:
	var total: float = 0.0
	var n: int = s.body_count()
	for i: int in n:
		if s.mode[i] != Gravity.Mode.FREE:
			continue
		var b: int = i * 3
		total += 0.5 * s.mass[i] * (s.vel[b] * s.vel[b] + s.vel[b + 1] * s.vel[b + 1] + s.vel[b + 2] * s.vel[b + 2])
		for j: int in range(i + 1, n):
			if s.mode[j] != Gravity.Mode.FREE:
				continue
			var c: int = j * 3
			var d: float = Vector3(s.pos[b] - s.pos[c], s.pos[b + 1] - s.pos[c + 1], s.pos[b + 2] - s.pos[c + 2]).length()
			total -= Units.G * s.mass[i] * s.mass[j] / d
	return total


static func _distance(s: NBodyState, i: int, j: int) -> float:
	var b: int = i * 3
	var c: int = j * 3
	var dx: float = s.pos[b] - s.pos[c]
	var dy: float = s.pos[b + 1] - s.pos[c + 1]
	var dz: float = s.pos[b + 2] - s.pos[c + 2]
	return sqrt(dx * dx + dy * dy + dz * dz)


## Adds a front at a point, now, travelling at c, and returns its index.
static func _front(s: NBodyState, x: float, y: float, z: float) -> int:
	s.front_origin.append_array([x, y, z])
	s.front_time.append(s.time)
	s.front_speed.append(Units.C)
	return s.front_time.size() - 1


static func _delta(s: NBodyState, body: int, front: int, change: float) -> void:
	s.delta_body.append(body)
	s.delta_front.append(front)
	s.delta_mass.append(change)
	s.acc_valid = false


func test_two_body_orbit_keeps_its_energy_for_a_century() -> void:
	for kernel_name: String in _kernels():
		var kernel: Object = _kernels()[kernel_name]
		var s: NBodyState = _sun_and_earth()
		var start: float = _energy(s)
		var lowest: float = INF
		var highest: float = 0.0
		for year: int in 100:
			_advance(kernel, s, year + 1.0)
			var r: float = _distance(s, 0, 1)
			lowest = minf(lowest, r)
			highest = maxf(highest, r)
		assert_almost_eq((_energy(s) - start) / absf(start), 0.0, 1e-5, "%s: energy" % kernel_name)
		assert_true(lowest > 0.999 and highest < 1.001, "%s: the orbit stays at 1 AU (%s–%s)" % [kernel_name, lowest, highest])
		assert_true(s.time > 99.99 and s.time <= 100.0, "%s: reached the target in whole steps" % kernel_name)


func test_a_body_placed_far_away_is_felt_only_once_its_front_arrives() -> void:
	for kernel_name: String in _kernels():
		var kernel: Object = _kernels()[kernel_name]
		var s: NBodyState = _sun_and_earth()
		var reference: NBodyState = s.copy()
		# A second sun 1,000 AU away: it pulls only where its news has arrived.
		var star: int = s.add_body(1000.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, Units.au_from_km(695700.0), Gravity.Mode.FREE, -1)
		_delta(s, star, _front(s, 1000.0, 0.0, 0.0), 1.0)
		var arrival: float = 999.0 / Units.C
		_advance(kernel, s, arrival * 0.95)
		_advance(kernel, reference, arrival * 0.95)
		assert_true(s.time > arrival * 0.5, "%s: several steps before it arrives" % kernel_name)
		assert_eq(s.time, reference.time, "%s: same steps" % kernel_name)
		assert_true(s.pos.slice(0, 6) == reference.pos.slice(0, 6), "%s: no effect on positions before the front arrives" % kernel_name)
		assert_true(s.vel.slice(0, 6) == reference.vel.slice(0, 6), "%s: nor on velocities" % kernel_name)
		_advance(kernel, s, arrival * 3.0)
		_advance(kernel, reference, arrival * 3.0)
		assert_true(s.pos.slice(3, 6) != reference.pos.slice(3, 6), "%s: felt after it arrives" % kernel_name)


func test_the_pull_changes_exactly_when_the_front_arrives() -> void:
	for kernel_name: String in _kernels():
		var kernel: Object = _kernels()[kernel_name]
		var s: NBodyState = _sun_and_earth()
		var star: int = s.add_body(0.0, 50.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, Gravity.Mode.FREE, -1)
		_delta(s, star, _front(s, 0.0, 50.0, 0.0), 2.0)
		var probe: PackedFloat64Array = PackedFloat64Array([0.0, -10.0, 0.0])
		var arrival: float = 60.0 / Units.C
		var step: float = 10.0 / Units.YEAR_SECONDS
		var before: PackedFloat64Array = kernel.call(&"field_at", s, probe, arrival - step)
		var after: PackedFloat64Array = kernel.call(&"field_at", s, probe, arrival + step)
		var change: float = after[1] - before[1]
		assert_almost_eq(change, Units.G * 2.0 / 3600.0, 1e-9, "%s: the new star's pull, within one 10 s step" % kernel_name)


func test_a_merger_without_mass_loss_leaves_the_far_field_unchanged() -> void:
	for kernel_name: String in _kernels():
		var kernel: Object = _kernels()[kernel_name]
		var s: NBodyState = NBodyState.new()
		var m: float = 1e-3
		s.add_body(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.00465, Gravity.Mode.FREE, -1)
		var v: float = sqrt(Units.G / 5.0)
		var a: int = s.add_body(5.0, 0.002, 0.0, 0.0, v, 0.0, m, 0.0005, Gravity.Mode.FREE, -1)
		var b: int = s.add_body(5.0, -0.002, 0.0, 0.0, v, 0.0, m, 0.0005, Gravity.Mode.FREE, -1)
		var probe: PackedFloat64Array = PackedFloat64Array([-40.0, 0.0, 0.0])
		var before: PackedFloat64Array = kernel.call(&"field_at", s, probe, s.time)
		# Merge: the two become ghosts that still pull where the news has not
		# arrived; the merged body pulls only where it has.
		var front: int = _front(s, 5.0, 0.0, 0.0)
		s.mode[a] = Gravity.Mode.GHOST
		s.mode[b] = Gravity.Mode.GHOST
		_delta(s, a, front, -m)
		_delta(s, b, front, -m)
		var merged: int = s.add_body(5.0, 0.0, 0.0, 0.0, v, 0.0, 0.0, 0.0007, Gravity.Mode.FREE, -1)
		_delta(s, merged, front, 2.0 * m)
		var just_after: PackedFloat64Array = kernel.call(&"field_at", s, probe, s.time)
		_advance(kernel, s, 46.0 / Units.C)
		var later: PackedFloat64Array = kernel.call(&"field_at", s, probe, s.time)
		assert_almost_eq(just_after[0], before[0], absf(before[0]) * 1e-12, "%s: unchanged before the news arrives" % kernel_name)
		assert_almost_eq(later[0], before[0], absf(before[0]) * 1e-4, "%s: the far field barely changes" % kernel_name)


func test_a_sleeping_particle_follows_the_integrated_orbit() -> void:
	for kernel_name: String in _kernels():
		var kernel: Object = _kernels()[kernel_name]
		var s: NBodyState = NBodyState.new()
		s.add_body(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.00465, Gravity.Mode.FREE, -1)
		var mu: float = Units.G
		var state: PackedFloat64Array = Kepler.state_from_elements(2.5, 0.15, 0.1, 0.4, 1.2, 0.3, Kepler.mean_motion(2.5, 1.0))
		var elements: PackedFloat64Array = Kepler.elements_from_state(
			state[0], state[1], state[2], state[3], state[4], state[5], mu, s.time
		)
		var asleep: int = s.add_sleeping_particle(0, elements, 1e-9, 0)
		var awake: int = s.add_particle(state[0], state[1], state[2], state[3], state[4], state[5], 1e-9, 0)
		_advance(kernel, s, 20.0)
		kernel.call(&"preview", s, s.time)
		var d: Vector3 = Vector3(
			s.p_view[asleep * 3] - s.p_view[awake * 3], s.p_view[asleep * 3 + 1] - s.p_view[awake * 3 + 1],
			s.p_view[asleep * 3 + 2] - s.p_view[awake * 3 + 2]
		)
		assert_true(d.length() < 2e-3, "%s: within 0.002 AU after 5 orbits (%s)" % [kernel_name, d.length()])
		assert_eq(s.p_mode[asleep], Gravity.ParticleMode.ASLEEP, "%s: nothing woke it" % kernel_name)


func test_a_particle_wakes_when_a_planet_comes_near() -> void:
	for kernel_name: String in _kernels():
		var kernel: Object = _kernels()[kernel_name]
		var s: NBodyState = _sun_and_earth()
		# On Earth's orbit, a little ahead of it: Earth catches up with it.
		var state: PackedFloat64Array = Kepler.state_from_elements(1.02, 0.0, 0.0, 0.0, 0.0, 0.3, Kepler.mean_motion(1.02, 1.0))
		var elements: PackedFloat64Array = Kepler.elements_from_state(
			state[0], state[1], state[2], state[3], state[4], state[5], Units.G, s.time
		)
		s.add_sleeping_particle(0, elements, 1e-9, 0)
		var result: Dictionary = _advance(kernel, s, 0.5)
		var woken: int = int(result["woken"])
		for k: int in 30:
			result = _advance(kernel, s, 0.5 + k)
			woken += int(result["woken"])
		assert_true(woken >= 1, "%s: woken when Earth came near" % kernel_name)


func test_the_same_state_has_the_same_future_however_the_frames_fall() -> void:
	for kernel_name: String in _kernels():
		var kernel: Object = _kernels()[kernel_name]
		var s: NBodyState = _sun_and_earth()
		var moon_v: float = sqrt(Units.G * EARTH_MASS / 0.00257)
		s.add_body(1.00257, 0.0, 0.0, 0.0, s.vel[4] + moon_v, 0.0, EARTH_MASS / 81.3, 1.16e-5, Gravity.Mode.FREE, -1)
		s.add_body(-5.2, 0.0, 0.1, 0.0, -sqrt(Units.G / 5.2), 0.0, 9.5e-4, 0.000477, Gravity.Mode.FREE, -1)
		for k: int in 40:
			var state: PackedFloat64Array = Kepler.state_from_elements(
				2.2 + 0.03 * k, 0.1, 0.05, 0.3 * k, 0.7 * k, 0.11 * k, Kepler.mean_motion(2.2 + 0.03 * k, 1.0)
			)
			if k % 2 == 0:
				s.add_particle(state[0], state[1], state[2], state[3], state[4], state[5], 1e-9, 0)
			else:
				s.add_sleeping_particle(
					0, Kepler.elements_from_state(state[0], state[1], state[2], state[3], state[4], state[5], Units.G, 0.0), 1e-9, 0
				)
		var other: NBodyState = s.copy()
		_advance(kernel, s, 0.37)
		var t: float = 0.0
		var frame: int = 0
		while t < 0.37:
			t = minf(0.37, t + 0.001 + 0.004 * (frame % 7))
			_advance(kernel, other, t)
			frame += 1
		assert_eq(other.time, s.time, "%s: same committed time" % kernel_name)
		for field: StringName in [&"pos", &"vel", &"acc", &"p_pos", &"p_vel", &"p_mode", &"p_elem"]:
			assert_true(s.get(field) == other.get(field), "%s: %s identical" % [kernel_name, field])


func test_bodies_on_a_collision_course_are_reported() -> void:
	for kernel_name: String in _kernels():
		var kernel: Object = _kernels()[kernel_name]
		var s: NBodyState = NBodyState.new()
		s.add_body(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.00465, Gravity.Mode.FREE, -1)
		s.add_body(3.0, -0.5, 0.0, 0.0, 6.0, 0.0, 1e-4, 0.0003, Gravity.Mode.FREE, -1)
		s.add_body(3.0, 0.5, 0.0, 0.0, -6.0, 0.0, 1e-4, 0.0003, Gravity.Mode.FREE, -1)
		var result: Dictionary = _advance(kernel, s, 1.0)
		assert_eq(int(result["status"]), Gravity.Status.EVENTS, "%s: stopped at the collision" % kernel_name)
		var pair: PackedInt32Array = result["collisions"]
		assert_eq(pair.size(), 2, "%s: one pair" % kernel_name)
		if pair.size() == 2:
			assert_eq([mini(pair[0], pair[1]), maxi(pair[0], pair[1])], [1, 2], "%s: the two planets" % kernel_name)
		assert_true(s.time < 0.2, "%s: soon after they meet (%s)" % [kernel_name, s.time])


func test_a_particle_striking_a_planet_is_an_impact() -> void:
	for kernel_name: String in _kernels():
		var kernel: Object = _kernels()[kernel_name]
		var s: NBodyState = _sun_and_earth()
		# Falling straight at the Earth from 0.01 AU at 20 km/s.
		var speed: float = 20.0 * Units.YEAR_SECONDS / Units.AU_KM
		s.add_particle(1.0, -0.01, 0.0, 0.0, s.vel[4] + speed, 0.0, 1e-9, 0)
		var result: Dictionary = {}
		for k: int in 20:
			result = _advance(kernel, s, 0.001 * (k + 1))
			if int(result["status"]) == Gravity.Status.EVENTS:
				break
		var impacts: PackedInt32Array = result.get("impacts", PackedInt32Array())
		assert_eq(impacts.size(), 2, "%s: one impact" % kernel_name)
		if impacts.size() == 2:
			assert_eq(impacts[1], 1, "%s: on the Earth" % kernel_name)
			var data: PackedFloat64Array = result["impact_data"]
			assert_true(data[1] * Units.AU_KM / Units.YEAR_SECONDS > 19.0, "%s: at about 20 km/s or more" % kernel_name)
		assert_eq(s.p_mode[0], Gravity.ParticleMode.GONE, "%s: the particle is gone" % kernel_name)


func test_kernels_agree() -> void:
	var kernels: Dictionary[String, Object] = _kernels()
	if not kernels.has("native"):
		return
	var a: NBodyState = _sun_and_earth()
	a.add_body(-5.2, 0.0, 0.1, 0.0, -sqrt(Units.G / 5.2), 0.0, 9.5e-4, 0.000477, Gravity.Mode.FREE, -1)
	a.add_particle(2.0, 0.0, 0.0, 0.0, sqrt(Units.G / 2.0), 0.3, 1e-9, 0)
	var b: NBodyState = a.copy()
	_advance(kernels["script"], a, 3.0)
	_advance(kernels["native"], b, 3.0)
	assert_eq(a.time, b.time, "same steps")
	for k: int in a.pos.size():
		assert_almost_eq(a.pos[k], b.pos[k], 1e-12, "body coordinate %d" % k)
	for k: int in a.p_pos.size():
		assert_almost_eq(a.p_pos[k], b.p_pos[k], 1e-12, "particle coordinate %d" % k)
