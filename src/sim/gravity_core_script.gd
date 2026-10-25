class_name GravityCoreScript
extends RefCounted
## The gravity kernel in GDScript: the reference implementation, used when
## the native kernel (the C++ GDExtension) is not loaded, and by tests that
## compare the two. The native kernel follows this file line by line.
##
## It moves an NBodyState forward in whole velocity-Verlet steps whose size
## comes from the state alone (a power of two of Gravity.UNIT, about 1/250
## of the shortest orbit), so the same state always has the same future,
## however the frames fall. Everything that changes the motion (parents,
## Hill spheres, rails, waking particles) happens at moments the state
## decides, never at frame boundaries.

const RAILS: int = Gravity.Mode.RAILS
const FREE: int = Gravity.Mode.FREE
const GHOST: int = Gravity.Mode.GHOST
const GONE: int = Gravity.Mode.GONE
const ASLEEP: int = Gravity.ParticleMode.ASLEEP
const AWAKE: int = Gravity.ParticleMode.AWAKE
const P_GONE: int = Gravity.ParticleMode.GONE
const ES: int = Gravity.ELEMENT_SIZE
## Parents, Hill spheres and rails are reviewed every this many steps.
const MAINTENANCE_STEPS: int = 64
## A body heavier than this (M☉) never rides rails: stars stay integrated.
const RAILS_MAX_MASS: float = 0.01
## Asleep particles are checked at least this often (years).
const MAX_CHECK_INTERVAL: float = 0.25
## Awake particles review whether they can sleep every this many own steps.
const SLEEP_CHECK_STEPS: int = 32
## A star that is not an ancestor wakes a particle when its tidal pull
## reaches this share of the particle's parent's pull.
const WAKE_TIDAL: float = 0.01
const LN2: float = 0.6931471805599453

var _delta_start: PackedInt32Array = []
var _delta_front: PackedInt32Array = []
var _delta_mass: PackedFloat64Array = []
var _reach2: PackedFloat64Array = []
var _new_acc: PackedFloat64Array = []
var _prev: PackedFloat64Array = []
var _placed: PackedByteArray = []
var _queue: Array[int] = []
var _queue_head: int = 0
var _queue_limit: float = 0.0
var _woken: int = 0
var _slept: int = 0


## Moves the state towards t_target in whole steps. Returns a summary:
## {"status": Gravity.Status, "steps", "collisions": [i, j, …] body pairs,
## "impacts": [particle, body, …], "impact_data": [time, speed, nx, ny, nz, …],
## "woken", "slept"}.
func advance(s: NBodyState, t_target: float, max_steps: int, max_usec: int) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var collisions: PackedInt32Array = PackedInt32Array()
	var impacts: PackedInt32Array = PackedInt32Array()
	var impact_data: PackedFloat64Array = PackedFloat64Array()
	var status: int = Gravity.Status.REACHED
	var steps: int = 0
	_woken = 0
	_slept = 0
	_prepare(s)
	_build_queue(s, t_target)
	while true:
		var h: float = Gravity.step_size(s.level)
		if s.time + h > t_target:
			break
		_step(s, h, collisions, impacts, impact_data)
		steps += 1
		_run_checks(s)
		if s.step_count % MAINTENANCE_STEPS == 0 and _maintain(s):
			_refresh_accelerations(s)
		if not collisions.is_empty() or not impacts.is_empty():
			status = Gravity.Status.EVENTS
			break
		if steps >= max_steps or (steps % 8 == 0 and Time.get_ticks_usec() - started > max_usec):
			if s.time + Gravity.step_size(s.level) <= t_target:
				status = Gravity.Status.BUDGET
			break
	return {
		"status": status, "steps": steps, "collisions": collisions, "impacts": impacts,
		"impact_data": impact_data, "woken": _woken, "slept": _slept,
	}


## Fills the state's view arrays with where everything is at time t, which
## may lie a little after the committed time (between two steps).
func preview(s: NBodyState, t: float) -> void:
	var n: int = s.mass.size()
	var count: int = s.p_mode.size()
	if s.view_pos.size() != n * 3:
		s.view_pos.resize(n * 3)
		s.view_vel.resize(n * 3)
	if s.p_view.size() != count * 3:
		s.p_view.resize(count * 3)
	var view: PackedFloat64Array = s.view_pos
	var view_vel: PackedFloat64Array = s.view_vel
	if not s.pristine:
		var delta: float = t - s.time
		var half: float = 0.5 * delta * delta
		for i: int in n:
			var b: int = i * 3
			if s.mode[i] == FREE or s.mode[i] == GHOST:
				for k: int in 3:
					view[b + k] = s.pos[b + k] + s.vel[b + k] * delta + s.acc[b + k] * half
					view_vel[b + k] = s.vel[b + k] + s.acc[b + k] * delta
			elif s.mode[i] == GONE:
				for k: int in 3:
					view[b + k] = s.pos[b + k]
					view_vel[b + k] = s.vel[b + k]
		_placed.resize(n)
		_placed.fill(0)
		for i: int in n:
			if s.mode[i] == RAILS:
				_place_one(s, i, t, view, view_vel)
	var elements: PackedFloat64Array = s.p_elem
	for p: int in count:
		var b: int = p * 3
		var mode: int = s.p_mode[p]
		if mode == AWAKE:
			var since: float = t - s.p_last[p]
			var half_since: float = 0.5 * since * since
			for k: int in 3:
				s.p_view[b + k] = s.p_pos[b + k] + s.p_vel[b + k] * since + s.p_acc[b + k] * half_since
		elif mode == ASLEEP:
			var primary: int = s.p_primary[p]
			var e_off: int = p * ES
			var a: float = elements[e_off]
			var e: float = elements[e_off + 1]
			var anomaly_mean: float = elements[e_off + 3] + elements[e_off + 2] * (t - elements[e_off + 4])
			var cp: float
			var cq: float
			if a > 0.0:
				var anomaly: float = Kepler.eccentric_anomaly(anomaly_mean, e)
				cp = cos(anomaly) - e
				cq = sin(anomaly)
			else:
				var anomaly: float = Kepler.hyperbolic_anomaly(anomaly_mean, e)
				cp = e - cosh(anomaly)
				cq = sinh(anomaly)
			var pb: int = primary * 3
			s.p_view[b] = view[pb] + cp * elements[e_off + 5] + cq * elements[e_off + 8]
			s.p_view[b + 1] = view[pb + 1] + cp * elements[e_off + 6] + cq * elements[e_off + 9]
			s.p_view[b + 2] = view[pb + 2] + cp * elements[e_off + 7] + cq * elements[e_off + 10]


## Accelerations (AU/yr²) at points [x, y, z, …] at time t, from every
## body as felt there (travelling changes included).
func field_at(s: NBodyState, points: PackedFloat64Array, t: float) -> PackedFloat64Array:
	_build_delta_index(s)
	_fronts_reach(s, t)
	var out: PackedFloat64Array = PackedFloat64Array()
	out.resize(points.size())
	for q: int in int(points.size() / 3.0):
		var b: int = q * 3
		var a: PackedFloat64Array = _pull_at(s, points[b], points[b + 1], points[b + 2], -1, false, 0.0, 0.0, 0.0)
		out[b] = a[0]
		out[b + 1] = a[1]
		out[b + 2] = a[2]
	return out


## Where the given bodies and particles will be over the next duration, at
## samples evenly spaced moments: [x, y, z] per sample for each body, then
## each particle (NAN once it hits something). Works on a copy; collisions
## between other bodies are ignored.
func predict(
	s: NBodyState, bodies: PackedInt32Array, particles: PackedInt32Array, duration: float, samples: int, max_steps: int
) -> PackedFloat64Array:
	var copy: NBodyState = s.copy()
	copy.collisions_enabled = false
	copy.acc_valid = false
	var tracked: int = bodies.size() + particles.size()
	var out: PackedFloat64Array = PackedFloat64Array()
	out.resize(tracked * samples * 3)
	out.fill(NAN)
	var stopped: PackedByteArray = PackedByteArray()
	stopped.resize(tracked)
	var start: float = copy.time
	var budget: int = maxi(int(max_steps / float(maxi(samples, 1))), 4)
	for k: int in samples:
		var target: float = start + duration * (k + 1) / samples
		var result: Dictionary = advance(copy, target, budget, 1 << 30)
		if int(result["status"]) == Gravity.Status.BUDGET:
			target = copy.time
		preview(copy, target)
		for q: int in tracked:
			if stopped[q] == 1:
				continue
			var x: float
			var y: float
			var z: float
			if q < bodies.size():
				var b: int = bodies[q] * 3
				x = copy.view_pos[b]
				y = copy.view_pos[b + 1]
				z = copy.view_pos[b + 2]
			else:
				var p: int = particles[q - bodies.size()]
				if copy.p_mode[p] == P_GONE:
					stopped[q] = 1
					continue
				x = copy.p_view[p * 3]
				y = copy.p_view[p * 3 + 1]
				z = copy.p_view[p * 3 + 2]
			if _touches_body(copy, x, y, z, bodies[q] if q < bodies.size() else -1):
				stopped[q] = 1
			var o: int = (q * samples + k) * 3
			out[o] = x
			out[o + 1] = y
			out[o + 2] = z
	return out


## Makes asleep particles that a new mass change matters to get checked
## when its front reaches them.
func schedule_front(s: NBodyState, front: int) -> void:
	_build_delta_index(s)
	for p: int in s.p_mode.size():
		if s.p_mode[p] != ASLEEP:
			continue
		var arrival: float = _significant_arrival(s, p, front)
		if not is_nan(arrival) and arrival < s.p_next[p]:
			s.p_next[p] = maxf(arrival, s.time)


# --- Steps -------------------------------------------------------------------

func _prepare(s: NBodyState) -> void:
	var n: int = s.mass.size()
	if s.hill.size() != n:
		s.hill.resize(n)
		s.hill.fill(INF)
	if s.p_next.size() != s.p_mode.size():
		var old: int = s.p_next.size()
		s.p_next.resize(s.p_mode.size())
		for p: int in range(old, s.p_mode.size()):
			s.p_next[p] = s.time
	_build_delta_index(s)
	if not s.acc_valid:
		_maintain(s)
		_refresh_accelerations(s)
		s.acc_valid = true
	for p: int in s.p_mode.size():
		if s.p_mode[p] == AWAKE and s.p_level[p] < 0:
			_lower_level(s, _start_particle(s, p))
	if s.level < 0:
		_refresh_accelerations(s)


func _refresh_accelerations(s: NBodyState) -> void:
	_place_rails(s, s.time)
	var tau: float = _body_forces(s, s.time)
	var n3: int = s.mass.size() * 3
	for k: int in n3:
		s.acc[k] = _new_acc[k]
	_choose_level(s, minf(tau, _particle_tau(s)), s.level < 0)


func _step(
	s: NBodyState, h: float, collisions: PackedInt32Array, impacts: PackedInt32Array, impact_data: PackedFloat64Array
) -> void:
	var n: int = s.mass.size()
	var pos: PackedFloat64Array = s.pos
	var vel: PackedFloat64Array = s.vel
	var acc: PackedFloat64Array = s.acc
	var mode: PackedInt32Array = s.mode
	_prev = pos.duplicate()
	var half: float = 0.5 * h * h
	for i: int in n:
		var m: int = mode[i]
		if m == FREE or m == GHOST:
			var b: int = i * 3
			pos[b] += vel[b] * h + acc[b] * half
			pos[b + 1] += vel[b + 1] * h + acc[b + 1] * half
			pos[b + 2] += vel[b + 2] * h + acc[b + 2] * half
	var t1: float = s.time + h
	_place_rails(s, t1)
	var tau: float = _body_forces(s, t1)
	var half_h: float = 0.5 * h
	for i: int in n:
		var m: int = mode[i]
		if m == FREE or m == GHOST:
			var b: int = i * 3
			for k: int in 3:
				vel[b + k] += (acc[b + k] + _new_acc[b + k]) * half_h
				acc[b + k] = _new_acc[b + k]
	s.time = t1
	s.step_count += 1
	if s.collisions_enabled:
		_sweep_bodies(s, collisions)
	tau = minf(tau, _step_particles(s, h, impacts, impact_data))
	_choose_level(s, tau, false)


## Picks the next step from the shortest dynamical time: shorter at once,
## longer only after it has stayed longer for a few steps.
func _choose_level(s: NBodyState, tau: float, reset: bool) -> void:
	var want: int = Gravity.MAX_LEVEL
	if tau > 0.0 and tau < INF:
		want = clampi(floori(log(Gravity.ETA * tau / Gravity.UNIT) / LN2), 0, Gravity.MAX_LEVEL)
	if reset or want < s.level:
		s.level = want
		s.level_up = 0
	elif want > s.level:
		s.level_up += 1
		if s.level_up >= 4:
			s.level += 1
			s.level_up = 0
	else:
		s.level_up = 0


## Shortens the step at once if something now needs it (a woken particle).
func _lower_level(s: NBodyState, tau: float) -> void:
	if tau > 0.0 and tau < INF:
		var want: int = clampi(floori(log(Gravity.ETA * tau / Gravity.UNIT) / LN2), 0, Gravity.MAX_LEVEL)
		if want < s.level:
			s.level = want
			s.level_up = 0


func _particle_tau(s: NBodyState) -> float:
	var tau: float = INF
	for p: int in s.p_mode.size():
		if s.p_mode[p] == AWAKE:
			tau = minf(tau, s.p_tau[p])
	return tau


# --- Forces ------------------------------------------------------------------

func _build_delta_index(s: NBodyState) -> void:
	var n: int = s.mass.size()
	_delta_start.resize(n + 1)
	_delta_start.fill(0)
	var count: int = s.delta_body.size()
	for d: int in count:
		_delta_start[s.delta_body[d] + 1] += 1
	for i: int in n:
		_delta_start[i + 1] += _delta_start[i]
	_delta_front.resize(count)
	_delta_mass.resize(count)
	var fill: PackedInt32Array = _delta_start.duplicate()
	for d: int in count:
		var at: int = fill[s.delta_body[d]]
		fill[s.delta_body[d]] += 1
		_delta_front[at] = s.delta_front[d]
		_delta_mass[at] = s.delta_mass[d]


## Squared radius each front has reached at time t (INF when instant).
func _fronts_reach(s: NBodyState, t: float) -> void:
	var count: int = s.front_time.size()
	_reach2.resize(count)
	for f: int in count:
		var speed: float = s.front_speed[f]
		if is_inf(speed):
			_reach2[f] = INF
		else:
			var reach: float = maxf(0.0, (t - s.front_time[f]) * speed)
			_reach2[f] = reach * reach


func _mask_at(s: NBodyState, x: float, y: float, z: float) -> int:
	var mask: int = 0
	var origin: PackedFloat64Array = s.front_origin
	for f: int in _reach2.size():
		var dx: float = x - origin[f * 3]
		var dy: float = y - origin[f * 3 + 1]
		var dz: float = z - origin[f * 3 + 2]
		if dx * dx + dy * dy + dz * dz <= _reach2[f]:
			mask |= 1 << f
	return mask


func _felt_mass(s: NBodyState, j: int, mask: int) -> float:
	var m: float = s.mass[j]
	for d: int in range(_delta_start[j], _delta_start[j + 1]):
		if mask & (1 << _delta_front[d]):
			m += _delta_mass[d]
	return m


## Accelerations of free bodies and ghosts at time t into _new_acc (rails
## already placed); returns the shortest dynamical time among free bodies.
func _body_forces(s: NBodyState, t: float) -> float:
	var n: int = s.mass.size()
	_new_acc.resize(n * 3)
	_new_acc.fill(0.0)
	_fronts_reach(s, t)
	var pos: PackedFloat64Array = s.pos
	var vel: PackedFloat64Array = s.vel
	var mass: PackedFloat64Array = s.mass
	var radius: PackedFloat64Array = s.radius
	var mode: PackedInt32Array = s.mode
	var g: float = Units.G * s.g_scale
	var soften: bool = not s.collisions_enabled
	var simple: bool = s.delta_body.is_empty()
	var tau2: float = INF
	for i: int in n:
		var mi: int = mode[i]
		if mi != FREE and mi != GHOST:
			continue
		var bi: int = i * 3
		var xi: float = pos[bi]
		var yi: float = pos[bi + 1]
		var zi: float = pos[bi + 2]
		var mask: int = 0 if simple else _mask_at(s, xi, yi, zi)
		var ax: float = 0.0
		var ay: float = 0.0
		var az: float = 0.0
		for j: int in n:
			if j == i:
				continue
			var mj: int = mode[j]
			if mj == GONE or (mi == GHOST and mj == GHOST):
				continue
			var m: float = mass[j] if simple else _felt_mass(s, j, mask)
			if m == 0.0:
				continue
			var bj: int = j * 3
			var dx: float = pos[bj] - xi
			var dy: float = pos[bj + 1] - yi
			var dz: float = pos[bj + 2] - zi
			var r2: float = dx * dx + dy * dy + dz * dz
			if soften or mi == GHOST:
				var soft: float = radius[i] + radius[j]
				r2 += soft * soft
			var r: float = sqrt(r2)
			var f: float = g * m / (r2 * r)
			ax += f * dx
			ay += f * dy
			az += f * dz
			if mi == FREE and mj != GHOST:
				var orbit2: float = r2 * r / (g * (m + maxf(mass[i], 0.0)))
				if orbit2 < tau2:
					tau2 = orbit2
				var dvx: float = vel[bj] - vel[bi]
				var dvy: float = vel[bj + 1] - vel[bi + 1]
				var dvz: float = vel[bj + 2] - vel[bi + 2]
				var v2: float = dvx * dvx + dvy * dvy + dvz * dvz
				if v2 > 0.0 and r2 / v2 < tau2:
					tau2 = r2 / v2
		_new_acc[bi] = ax
		_new_acc[bi + 1] = ay
		_new_acc[bi + 2] = az
	return sqrt(tau2)


## The pull at a point from every body (ghosts and travelling changes
## included), skipping one body. Returns [ax, ay, az, tau] where tau is the
## shortest dynamical time there (using the given velocity).
func _pull_at(
	s: NBodyState, x: float, y: float, z: float, skip: int, soften: bool, vx: float, vy: float, vz: float
) -> PackedFloat64Array:
	var n: int = s.mass.size()
	var pos: PackedFloat64Array = s.pos
	var vel: PackedFloat64Array = s.vel
	var g: float = Units.G * s.g_scale
	var simple: bool = s.delta_body.is_empty()
	var mask: int = 0 if simple else _mask_at(s, x, y, z)
	var ax: float = 0.0
	var ay: float = 0.0
	var az: float = 0.0
	var tau2: float = INF
	for j: int in n:
		if j == skip or s.mode[j] == GONE:
			continue
		var m: float = s.mass[j] if simple else _felt_mass(s, j, mask)
		if m == 0.0:
			continue
		var bj: int = j * 3
		var dx: float = pos[bj] - x
		var dy: float = pos[bj + 1] - y
		var dz: float = pos[bj + 2] - z
		var r2: float = dx * dx + dy * dy + dz * dz
		if soften:
			r2 += s.radius[j] * s.radius[j]
		var r: float = sqrt(r2)
		var f: float = g * m / (r2 * r)
		ax += f * dx
		ay += f * dy
		az += f * dz
		if s.mode[j] != GHOST:
			var orbit2: float = r2 * r / (g * m)
			if orbit2 < tau2:
				tau2 = orbit2
			var dvx: float = vel[bj] - vx
			var dvy: float = vel[bj + 1] - vy
			var dvz: float = vel[bj + 2] - vz
			var v2: float = dvx * dvx + dvy * dvy + dvz * dvz
			if v2 > 0.0 and r2 / v2 < tau2:
				tau2 = r2 / v2
	return PackedFloat64Array([ax, ay, az, sqrt(tau2)])


func _place_rails(s: NBodyState, t: float) -> void:
	var n: int = s.mass.size()
	_placed.resize(n)
	_placed.fill(0)
	for i: int in n:
		if s.mode[i] == RAILS:
			_place_one(s, i, t, s.pos, s.vel)


## Puts a rails body where its conic says at time t, after its parent.
func _place_one(s: NBodyState, i: int, t: float, positions: PackedFloat64Array, velocities: PackedFloat64Array) -> void:
	if _placed[i] == 1:
		return
	_placed[i] = 1
	var p: int = s.parent[i]
	if p >= 0 and s.mode[p] == RAILS:
		_place_one(s, p, t, positions, velocities)
	var state: PackedFloat64Array = Kepler.state_from_element_set(s.rail, i * ES, t)
	var b: int = i * 3
	for k: int in 3:
		positions[b + k] = (positions[p * 3 + k] if p >= 0 else 0.0) + state[k]
		velocities[b + k] = (velocities[p * 3 + k] if p >= 0 else 0.0) + state[k + 3]


# --- Collisions --------------------------------------------------------------

## Closest approach of two points moving in straight lines over a step:
## from a0, b0 to a1, b1 (relative offsets d0 = a0 - b0, d1 = a1 - b1).
## Returns [squared distance, fraction of the step].
static func _closest(
	d0x: float, d0y: float, d0z: float, d1x: float, d1y: float, d1z: float
) -> PackedFloat64Array:
	var ex: float = d1x - d0x
	var ey: float = d1y - d0y
	var ez: float = d1z - d0z
	var ee: float = ex * ex + ey * ey + ez * ez
	var u: float = 0.0
	if ee > 0.0:
		u = clampf(-(d0x * ex + d0y * ey + d0z * ez) / ee, 0.0, 1.0)
	var cx: float = d0x + u * ex
	var cy: float = d0y + u * ey
	var cz: float = d0z + u * ez
	return PackedFloat64Array([cx * cx + cy * cy + cz * cz, u])


func _sweep_bodies(s: NBodyState, collisions: PackedInt32Array) -> void:
	var n: int = s.mass.size()
	var pos: PackedFloat64Array = s.pos
	var hit: PackedByteArray = PackedByteArray()
	hit.resize(n)
	for i: int in n:
		if s.mode[i] != FREE or hit[i] == 1:
			continue
		var bi: int = i * 3
		for j: int in n:
			if j == i or hit[j] == 1:
				continue
			var mj: int = s.mode[j]
			if mj == GHOST or mj == GONE or (mj == FREE and j < i):
				continue
			var bj: int = j * 3
			var reach: float = s.radius[i] + s.radius[j]
			var d1x: float = pos[bi] - pos[bj]
			var d1y: float = pos[bi + 1] - pos[bj + 1]
			var d1z: float = pos[bi + 2] - pos[bj + 2]
			var d0x: float = _prev[bi] - _prev[bj]
			var d0y: float = _prev[bi + 1] - _prev[bj + 1]
			var d0z: float = _prev[bi + 2] - _prev[bj + 2]
			# Quick reject: both ends far apart and moving less than the gap.
			var gap: float = sqrt(minf(d0x * d0x + d0y * d0y + d0z * d0z, d1x * d1x + d1y * d1y + d1z * d1z))
			var moved: float = sqrt((d1x - d0x) * (d1x - d0x) + (d1y - d0y) * (d1y - d0y) + (d1z - d0z) * (d1z - d0z))
			if gap - moved > reach:
				continue
			var closest: PackedFloat64Array = _closest(d0x, d0y, d0z, d1x, d1y, d1z)
			if closest[0] < reach * reach:
				collisions.append(i)
				collisions.append(j)
				hit[i] = 1
				hit[j] = 1
				break


func _touches_body(s: NBodyState, x: float, y: float, z: float, skip: int) -> bool:
	for j: int in s.mass.size():
		if j == skip or s.mode[j] == GONE or s.mode[j] == GHOST:
			continue
		var b: int = j * 3
		var dx: float = x - s.view_pos[b]
		var dy: float = y - s.view_pos[b + 1]
		var dz: float = z - s.view_pos[b + 2]
		if dx * dx + dy * dy + dz * dz < s.radius[j] * s.radius[j]:
			return true
	return false


# --- Particles ---------------------------------------------------------------

## First pull on a newly awake particle; returns its dynamical time.
func _start_particle(s: NBodyState, p: int) -> float:
	_fronts_reach(s, s.time)
	var b: int = p * 3
	var pull: PackedFloat64Array = _pull_at(
		s, s.p_pos[b], s.p_pos[b + 1], s.p_pos[b + 2], -1, not s.collisions_enabled,
		s.p_vel[b], s.p_vel[b + 1], s.p_vel[b + 2]
	)
	s.p_acc[b] = pull[0]
	s.p_acc[b + 1] = pull[1]
	s.p_acc[b + 2] = pull[2]
	s.p_tau[p] = pull[3]
	s.p_last[p] = s.time
	s.p_level[p] = 0
	s.p_next[p] = s.time + SLEEP_CHECK_STEPS * Gravity.ETA * pull[3]
	return pull[3]


## Steps every awake particle whose turn it is; returns the shortest
## dynamical time among awake particles.
func _step_particles(s: NBodyState, h: float, impacts: PackedInt32Array, impact_data: PackedFloat64Array) -> float:
	var count: int = s.p_mode.size()
	if count == 0:
		return INF
	var n: int = s.mass.size()
	var t1: float = s.time
	var tau_min: float = INF
	var soften: bool = not s.collisions_enabled
	var pos: PackedFloat64Array = s.pos
	var vel: PackedFloat64Array = s.vel
	for p: int in count:
		if s.p_mode[p] != AWAKE:
			continue
		var level: int = s.p_level[p]
		if (s.step_count & ((1 << level) - 1)) != 0:
			tau_min = minf(tau_min, s.p_tau[p])
			continue
		var big_h: float = t1 - s.p_last[p]
		var b: int = p * 3
		var x0: float = s.p_pos[b]
		var y0: float = s.p_pos[b + 1]
		var z0: float = s.p_pos[b + 2]
		var half: float = 0.5 * big_h * big_h
		var x: float = x0 + s.p_vel[b] * big_h + s.p_acc[b] * half
		var y: float = y0 + s.p_vel[b + 1] * big_h + s.p_acc[b + 1] * half
		var z: float = z0 + s.p_vel[b + 2] * big_h + s.p_acc[b + 2] * half
		if s.collisions_enabled:
			var hit: int = -1
			var hit_u: float = 0.0
			for j: int in n:
				var mj: int = s.mode[j]
				if mj == GONE or mj == GHOST:
					continue
				var bj: int = j * 3
				var reach: float = s.radius[j] + s.p_radius[p]
				var d1x: float = x - pos[bj]
				var d1y: float = y - pos[bj + 1]
				var d1z: float = z - pos[bj + 2]
				var d0x: float = x0 - (pos[bj] - vel[bj] * big_h)
				var d0y: float = y0 - (pos[bj + 1] - vel[bj + 1] * big_h)
				var d0z: float = z0 - (pos[bj + 2] - vel[bj + 2] * big_h)
				var gap: float = sqrt(minf(d0x * d0x + d0y * d0y + d0z * d0z, d1x * d1x + d1y * d1y + d1z * d1z))
				var moved: float = sqrt((d1x - d0x) * (d1x - d0x) + (d1y - d0y) * (d1y - d0y) + (d1z - d0z) * (d1z - d0z))
				if gap - moved > reach:
					continue
				var closest: PackedFloat64Array = _closest(d0x, d0y, d0z, d1x, d1y, d1z)
				if closest[0] < reach * reach:
					hit = j
					hit_u = closest[1]
					break
			if hit >= 0:
				var bj: int = hit * 3
				# Where it struck, relative to the body's centre, and how fast.
				var nx: float = x0 + (x - x0) * hit_u - (pos[bj] - vel[bj] * big_h * (1.0 - hit_u))
				var ny: float = y0 + (y - y0) * hit_u - (pos[bj + 1] - vel[bj + 1] * big_h * (1.0 - hit_u))
				var nz: float = z0 + (z - z0) * hit_u - (pos[bj + 2] - vel[bj + 2] * big_h * (1.0 - hit_u))
				var length: float = maxf(sqrt(nx * nx + ny * ny + nz * nz), 1e-300)
				var dvx: float = s.p_vel[b] - vel[bj]
				var dvy: float = s.p_vel[b + 1] - vel[bj + 1]
				var dvz: float = s.p_vel[b + 2] - vel[bj + 2]
				s.p_mode[p] = P_GONE
				s.p_pos[b] = x
				s.p_pos[b + 1] = y
				s.p_pos[b + 2] = z
				impacts.append(p)
				impacts.append(hit)
				impact_data.append_array([
					t1 - big_h * (1.0 - hit_u), sqrt(dvx * dvx + dvy * dvy + dvz * dvz),
					nx / length, ny / length, nz / length,
				])
				continue
		var vx: float = s.p_vel[b] + s.p_acc[b] * big_h
		var vy: float = s.p_vel[b + 1] + s.p_acc[b + 1] * big_h
		var vz: float = s.p_vel[b + 2] + s.p_acc[b + 2] * big_h
		var pull: PackedFloat64Array = _pull_at(s, x, y, z, -1, soften, vx, vy, vz)
		var half_h: float = 0.5 * big_h
		s.p_vel[b] += (s.p_acc[b] + pull[0]) * half_h
		s.p_vel[b + 1] += (s.p_acc[b + 1] + pull[1]) * half_h
		s.p_vel[b + 2] += (s.p_acc[b + 2] + pull[2]) * half_h
		s.p_pos[b] = x
		s.p_pos[b + 1] = y
		s.p_pos[b + 2] = z
		s.p_acc[b] = pull[0]
		s.p_acc[b + 1] = pull[1]
		s.p_acc[b + 2] = pull[2]
		s.p_last[p] = t1
		var tau: float = pull[3]
		s.p_tau[p] = tau
		var want: int = Gravity.PARTICLE_MAX_LEVEL
		if tau < INF:
			want = clampi(floori(log(Gravity.ETA * tau / h) / LN2), 0, Gravity.PARTICLE_MAX_LEVEL)
		if want < level:
			level = want
		elif want > level and (s.step_count & ((1 << (level + 1)) - 1)) == 0:
			level += 1
		s.p_level[p] = level
		tau_min = minf(tau_min, tau)
		if t1 >= s.p_next[p]:
			if not _try_sleep(s, p):
				s.p_next[p] = t1 + SLEEP_CHECK_STEPS * Gravity.step_size(s.level) * (1 << level)
	return tau_min


## Puts an awake particle to sleep on a conic around its parent when
## nothing else is pulling it noticeably and no change is still travelling.
func _try_sleep(s: NBodyState, p: int) -> bool:
	if not s.delta_body.is_empty():
		return false
	var b: int = p * 3
	var x: float = s.p_pos[b]
	var y: float = s.p_pos[b + 1]
	var z: float = s.p_pos[b + 2]
	var primary: int = _primary_for(s, x, y, z)
	if primary < 0:
		return false
	var pb: int = primary * 3
	var rx: float = x - s.pos[pb]
	var ry: float = y - s.pos[pb + 1]
	var rz: float = z - s.pos[pb + 2]
	var r2: float = rx * rx + ry * ry + rz * rz
	var g: float = Units.G * s.g_scale
	var own: float = g * s.mass[primary] / r2
	# Tidal pull of everything else, relative to the parent.
	var tx: float = 0.0
	var ty: float = 0.0
	var tz: float = 0.0
	for j: int in s.mass.size():
		if j == primary or s.mode[j] == GONE or s.mode[j] == GHOST or s.mass[j] == 0.0:
			continue
		var bj: int = j * 3
		var dx: float = s.pos[bj] - x
		var dy: float = s.pos[bj + 1] - y
		var dz: float = s.pos[bj + 2] - z
		var d2: float = dx * dx + dy * dy + dz * dz
		var f: float = g * s.mass[j] / (d2 * sqrt(d2))
		var ex: float = s.pos[bj] - s.pos[pb]
		var ey: float = s.pos[bj + 1] - s.pos[pb + 1]
		var ez: float = s.pos[bj + 2] - s.pos[pb + 2]
		var e2: float = ex * ex + ey * ey + ez * ez
		var fe: float = g * s.mass[j] / (e2 * sqrt(e2))
		tx += f * dx - fe * ex
		ty += f * dy - fe * ey
		tz += f * dz - fe * ez
	if tx * tx + ty * ty + tz * tz > pow(Gravity.SLEEP_RATIO * own, 2.0):
		return false
	var mu: float = g * s.mass[primary]
	var elements: PackedFloat64Array = Kepler.elements_from_state(
		rx, ry, rz, s.p_vel[b] - s.vel[pb], s.p_vel[b + 1] - s.vel[pb + 1], s.p_vel[b + 2] - s.vel[pb + 2],
		mu, s.time
	)
	if elements.is_empty() or elements[0] <= 0.0 or elements[1] > 0.98:
		return false
	if elements[0] * (1.0 - elements[1]) < 3.0 * s.radius[primary]:
		return false
	for k: int in ES:
		s.p_elem[p * ES + k] = elements[k]
	s.p_mode[p] = ASLEEP
	s.p_primary[p] = primary
	s.p_last[p] = s.time
	s.p_next[p] = s.time
	_slept += 1
	return true


## The body a particle at a point is bound to: the one with the smallest
## Hill sphere containing it, else the strongest pull among the top bodies.
func _primary_for(s: NBodyState, x: float, y: float, z: float) -> int:
	var best: int = -1
	var best_hill: float = INF
	var best_pull: float = 0.0
	for j: int in s.mass.size():
		if s.mode[j] == GONE or s.mode[j] == GHOST or s.mass[j] <= 0.0:
			continue
		var b: int = j * 3
		var dx: float = x - s.pos[b]
		var dy: float = y - s.pos[b + 1]
		var dz: float = z - s.pos[b + 2]
		var d2: float = dx * dx + dy * dy + dz * dz
		var hill: float = s.hill[j]
		if hill < INF:
			if d2 < hill * hill and hill < best_hill:
				best = j
				best_hill = hill
		elif best_hill == INF:
			var pull: float = s.mass[j] / maxf(d2, 1e-300)
			if pull > best_pull:
				best = j
				best_pull = pull
	return best


func _build_queue(s: NBodyState, t_target: float) -> void:
	_queue.clear()
	_queue_head = 0
	_queue_limit = t_target
	if s.pristine:
		return
	for p: int in s.p_mode.size():
		if s.p_mode[p] == ASLEEP and s.p_next[p] <= t_target:
			_queue.append(p)
	var next: PackedFloat64Array = s.p_next
	_queue.sort_custom(func(a: int, b: int) -> bool:
		return next[a] < next[b] or (next[a] == next[b] and a < b))


## Checks the asleep particles whose time has come.
func _run_checks(s: NBodyState) -> void:
	while _queue_head < _queue.size():
		var p: int = _queue[_queue_head]
		if s.p_next[p] > s.time:
			return
		_queue_head += 1
		if s.p_mode[p] != ASLEEP:
			continue
		if _check_asleep(s, p):
			_wake(s, p)
		elif s.p_next[p] <= _queue_limit:
			_enqueue(s, p)


func _enqueue(s: NBodyState, p: int) -> void:
	var at: int = _queue.size()
	while at > _queue_head and s.p_next[_queue[at - 1]] > s.p_next[p]:
		at -= 1
	_queue.insert(at, p)


## Whether an asleep particle must wake now; otherwise schedules its next
## check from how soon anything could come close.
func _check_asleep(s: NBodyState, p: int) -> bool:
	var primary: int = s.p_primary[p]
	if primary < 0 or s.mode[primary] == GONE or s.mode[primary] == GHOST:
		return true
	var rel: PackedFloat64Array = Kepler.state_from_element_set(s.p_elem, p * ES, s.time)
	var pb: int = primary * 3
	var x: float = s.pos[pb] + rel[0]
	var y: float = s.pos[pb + 1] + rel[1]
	var z: float = s.pos[pb + 2] + rel[2]
	var vx: float = s.vel[pb] + rel[3]
	var vy: float = s.vel[pb + 1] + rel[4]
	var vz: float = s.vel[pb + 2] + rel[5]
	var r_primary: float = sqrt(rel[0] * rel[0] + rel[1] * rel[1] + rel[2] * rel[2])
	if r_primary < 3.0 * s.radius[primary]:
		return true
	var ancestors: PackedInt32Array = PackedInt32Array()
	var up: int = s.parent[primary]
	while up >= 0 and ancestors.size() < 8:
		ancestors.append(up)
		up = s.parent[up]
	var soonest: float = MAX_CHECK_INTERVAL
	for j: int in s.mass.size():
		if j == primary or s.mode[j] == GONE or s.mode[j] == GHOST or ancestors.has(j):
			continue
		var zone: float
		if s.hill[j] < INF:
			zone = Gravity.WAKE_HILL * s.hill[j]
		else:
			# A top body that is not this particle's ancestor (another star).
			zone = r_primary * pow(2.0 * s.mass[j] / (WAKE_TIDAL * maxf(s.mass[primary], 1e-300)), 1.0 / 3.0)
		zone = maxf(zone, 3.0 * s.radius[j])
		var b: int = j * 3
		var dx: float = x - s.pos[b]
		var dy: float = y - s.pos[b + 1]
		var dz: float = z - s.pos[b + 2]
		var distance: float = sqrt(dx * dx + dy * dy + dz * dz)
		if distance < zone:
			return true
		var dvx: float = vx - s.vel[b]
		var dvy: float = vy - s.vel[b + 1]
		var dvz: float = vz - s.vel[b + 2]
		var closing: float = 2.0 * sqrt(dvx * dvx + dvy * dvy + dvz * dvz) + 0.1
		soonest = minf(soonest, 0.5 * (distance - zone) / closing)
	# Mass changes whose front reached it since the last check.
	for f: int in s.front_time.size():
		var arrival: float = _significant_arrival_at(s, p, f, x, y, z, r_primary, primary)
		if is_nan(arrival):
			continue
		if arrival > s.p_last[p] and arrival <= s.time:
			return true
		if arrival > s.time:
			soonest = minf(soonest, arrival - s.time)
	s.p_last[p] = s.time
	s.p_next[p] = s.time + maxf(soonest, Gravity.step_size(s.level))
	return false


## When front f reaches particle p, if a mass change it carries matters to
## the particle; NAN otherwise.
func _significant_arrival(s: NBodyState, p: int, f: int) -> float:
	var primary: int = s.p_primary[p]
	if primary < 0:
		return NAN
	var rel: PackedFloat64Array = Kepler.state_from_element_set(s.p_elem, p * ES, s.time)
	var pb: int = primary * 3
	var r_primary: float = sqrt(rel[0] * rel[0] + rel[1] * rel[1] + rel[2] * rel[2])
	return _significant_arrival_at(s, p, f, s.pos[pb] + rel[0], s.pos[pb + 1] + rel[1], s.pos[pb + 2] + rel[2], r_primary, primary)


func _significant_arrival_at(
	s: NBodyState, _p: int, f: int, x: float, y: float, z: float, r_primary: float, primary: int
) -> float:
	var own: float = s.mass[primary] / maxf(r_primary * r_primary, 1e-300)
	var significant: bool = false
	for d: int in s.delta_body.size():
		if s.delta_front[d] != f:
			continue
		var b: int = s.delta_body[d] * 3
		var dx: float = x - s.pos[b]
		var dy: float = y - s.pos[b + 1]
		var dz: float = z - s.pos[b + 2]
		var d2: float = maxf(dx * dx + dy * dy + dz * dz, 1e-300)
		if absf(s.delta_mass[d]) / d2 > Gravity.FRONT_WAKE_RATIO * own:
			significant = true
			break
	if not significant:
		return NAN
	var ox: float = x - s.front_origin[f * 3]
	var oy: float = y - s.front_origin[f * 3 + 1]
	var oz: float = z - s.front_origin[f * 3 + 2]
	var speed: float = s.front_speed[f]
	if is_inf(speed):
		return s.front_time[f]
	return s.front_time[f] + sqrt(ox * ox + oy * oy + oz * oz) / speed


func _wake(s: NBodyState, p: int) -> void:
	var primary: int = s.p_primary[p]
	var b: int = p * 3
	if primary >= 0:
		var rel: PackedFloat64Array = Kepler.state_from_element_set(s.p_elem, p * ES, s.time)
		var pb: int = primary * 3
		for k: int in 3:
			s.p_pos[b + k] = s.pos[pb + k] + rel[k]
			s.p_vel[b + k] = s.vel[pb + k] + rel[k + 3]
	s.p_mode[p] = AWAKE
	_lower_level(s, _start_particle(s, p))
	_woken += 1


# --- Upkeep ------------------------------------------------------------------

## Reviews parents, Hill spheres and rails. Returns true when a body
## changed between rails and free (accelerations must then be redone).
func _maintain(s: NBodyState) -> bool:
	var valid: bool = s.acc_valid
	var n: int = s.mass.size()
	var order: Array[int] = []
	for i: int in n:
		if s.mode[i] == FREE or s.mode[i] == RAILS:
			order.append(i)
	var mass: PackedFloat64Array = s.mass
	order.sort_custom(func(a: int, b: int) -> bool:
		return mass[a] > mass[b] or (mass[a] == mass[b] and a < b))
	var changed: bool = false
	for k: int in order.size():
		var i: int = order[k]
		var bi: int = i * 3
		var best: int = -1
		var best_hill: float = INF
		var best_pull: float = 0.0
		for q: int in k:
			var j: int = order[q]
			var bj: int = j * 3
			var dx: float = s.pos[bi] - s.pos[bj]
			var dy: float = s.pos[bi + 1] - s.pos[bj + 1]
			var dz: float = s.pos[bi + 2] - s.pos[bj + 2]
			var d2: float = dx * dx + dy * dy + dz * dz
			var hill: float = s.hill[j]
			if hill < INF:
				if d2 < hill * hill and hill < best_hill:
					best = j
					best_hill = hill
			elif best_hill == INF:
				var pull: float = mass[j] / maxf(d2, 1e-300)
				if pull > best_pull:
					best = j
					best_pull = pull
		if s.mode[i] == RAILS:
			var rails_parent: int = s.parent[i]
			var stays: bool = (
				s.rails_tau > 0.0 and best == rails_parent
				and _orbit_tau(s, i, rails_parent) < 1.25 * s.rails_tau
				and not _disturbed(s, i, rails_parent)
			)
			if not stays:
				s.mode[i] = FREE
				changed = true
		s.parent[i] = best
		if best >= 0:
			var bb: int = best * 3
			var dx: float = s.pos[bi] - s.pos[bb]
			var dy: float = s.pos[bi + 1] - s.pos[bb + 1]
			var dz: float = s.pos[bi + 2] - s.pos[bb + 2]
			s.hill[i] = sqrt(dx * dx + dy * dy + dz * dz) * pow(mass[i] / (3.0 * maxf(mass[best], 1e-300)), 1.0 / 3.0)
		else:
			s.hill[i] = INF
		if (
			s.mode[i] == FREE and s.rails_tau > 0.0 and best >= 0 and mass[i] < RAILS_MAX_MASS
			and _orbit_tau(s, i, best) < 0.8 * s.rails_tau and not _disturbed(s, i, best)
		):
			if s.set_rails_from_state(i, best):
				var e: float = s.rail[i * ES + 1]
				if e > 0.95 or s.rail[i * ES] <= 0.0:
					s.mode[i] = FREE
				else:
					changed = true
	for i: int in n:
		if s.mode[i] == GHOST or s.mode[i] == GONE:
			s.hill[i] = 0.0
	s.acc_valid = valid
	return changed


func _orbit_tau(s: NBodyState, i: int, p: int) -> float:
	var bi: int = i * 3
	var bp: int = p * 3
	var dx: float = s.pos[bi] - s.pos[bp]
	var dy: float = s.pos[bi + 1] - s.pos[bp + 1]
	var dz: float = s.pos[bi + 2] - s.pos[bp + 2]
	var d2: float = dx * dx + dy * dy + dz * dz
	return sqrt(d2 * sqrt(d2) / (Units.G * s.g_scale * (s.mass[i] + s.mass[p])))


## True when a third body has come inside the parent's Hill sphere (a moon
## on rails would miss its pull).
func _disturbed(s: NBodyState, i: int, p: int) -> bool:
	var hill: float = s.hill[p]
	if hill == INF:
		return false
	var bp: int = p * 3
	for j: int in s.mass.size():
		if j == i or j == p or s.mode[j] == GONE or s.mode[j] == GHOST or s.parent[j] == p:
			continue
		if s.mass[j] < 1e-3 * s.mass[i]:
			continue
		var bj: int = j * 3
		var dx: float = s.pos[bj] - s.pos[bp]
		var dy: float = s.pos[bj + 1] - s.pos[bp + 1]
		var dz: float = s.pos[bj + 2] - s.pos[bp + 2]
		if dx * dx + dy * dy + dz * dz < hill * hill:
			return true
	return false
