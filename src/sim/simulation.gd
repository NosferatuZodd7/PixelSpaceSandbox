class_name Simulation
extends RefCounted
## Runs a star system through time.
##
## While nobody has touched it, every body follows its fixed orbit, so
## positions are a pure function of time, exact at any speed, as in the real
## sky. Once something changes the system, every body is integrated under
## n-body gravity by the gravity kernel (an NBodyState moved by
## Gravity.create_core()), in steps that do not depend on the frames.

## A frame of play, for sizing the work done per frame.
const FRAME_SECONDS: float = 1.0 / 60.0
## How many kernel steps a frame should need at most: moons whose orbits are
## too fast for that at the current speed ride rails around their planet
## (at one week per second, Phobos; at one year per second, every moon but
## ours and the farthest).
const TARGET_STEPS: float = 60.0

var system: StarSystem
var clock: SimClock
## The committed physical state the kernel moves.
var state: NBodyState
## Changes spreading at the speed of light.
var fronts: Array[WaveFront] = []
## Most work per frame; past it the clock waits for the simulation.
var max_steps_per_frame: int = 4000
var max_usec_per_frame: int = 6000
## True when the last frame ran out of budget (the game runs slower than
## the chosen speed).
var lagging: bool = false
## World law: how fast changes travel (AU per year). INF makes every change
## felt at once everywhere (the classic sandbox).
var light_speed: float = Units.C

var _core: Object


func _init(star_system: StarSystem, sim_clock: SimClock) -> void:
	system = star_system
	clock = sim_clock
	_core = Gravity.create_core()
	system.place_on_orbits(clock.time)
	state = NBodyState.new()
	state.pristine = true
	for i: int in system.size():
		var b: CelestialBody = system.body(i)
		state.add_body(
			system.x(i), system.y(i), system.z(i),
			system.velocities[i * 3], system.velocities[i * 3 + 1], system.velocities[i * 3 + 2],
			b.mass, b.radius, Gravity.Mode.RAILS, b.parent
		)
		state.light_base[i] = b.luminosity
	_copy_rails_into_state()


func is_pristine() -> bool:
	return state.pristine


## From now on every body is integrated under n-body gravity, starting from
## exactly where its orbit puts it, in a frame where the system's centre of
## mass is at rest.
func leave_pristine() -> void:
	if not state.pristine:
		return
	system.place_on_orbits(clock.time)
	_copy_rails_into_state()
	var count: int = state.body_count()
	var total_mass: float = 0.0
	# 64-bit sums (Vector3 is 32-bit).
	var momentum: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
	for i: int in count:
		total_mass += state.mass[i]
		for k: int in 3:
			momentum[k] += state.vel[i * 3 + k] * state.mass[i]
	for i: int in count:
		for k: int in 3:
			state.vel[i * 3 + k] -= momentum[k] / total_mass
		state.mode[i] = Gravity.Mode.FREE
		state.parent[i] = -1
	state.pristine = false
	state.level = -1
	state.acc_valid = false
	_core.call(&"preview", state, clock.time)
	_show_view()


## Advances by a real duration (seconds) at the clock's speed.
func advance(real_seconds: float) -> void:
	if state.pristine:
		clock.advance(real_seconds)
		system.place_on_orbits(clock.time)
		_copy_rails_into_state()
	else:
		lagging = false
		if not clock.paused:
			state.rails_tau = clock.speed() * FRAME_SECONDS / TARGET_STEPS / Gravity.ETA / Units.YEAR_SECONDS
			var target: float = clock.time + real_seconds * clock.years_per_second()
			var result: Dictionary = _core.call(&"advance", state, target, max_steps_per_frame, max_usec_per_frame)
			lagging = int(result["status"]) == Gravity.Status.BUDGET
			clock.time = state.time if lagging else target
		_core.call(&"preview", state, clock.time)
		_show_view()
	_update_fronts()


## Whether a body is still part of the system (not removed, not a ghost).
func is_present(index: int) -> bool:
	return state.mode[index] == Gravity.Mode.FREE or state.mode[index] == Gravity.Mode.RAILS


## Adds a body at a point with a velocity (AU, AU/yr) at the committed
## moment. Its pull and light spread from there at the speed of light.
## Returns its index.
func place_body(
	body: CelestialBody, x: float, y: float, z: float, vx: float, vy: float, vz: float, label_key: String
) -> int:
	leave_pristine()
	var index: int = system.add(body)
	state.add_body(x, y, z, vx, vy, vz, 0.0, body.radius, Gravity.Mode.FREE, -1)
	var front: int = emit_front(x, y, z, body.luminosity > 0.0, true, label_key)
	_change_mass(index, front, body.mass)
	_change_light(index, front, body.luminosity)
	_after_change(front)
	return index


## Removes a body. Where the news has not arrived it keeps pulling, along
## its last path, as a ghost, and a star keeps shining there.
func remove_body(index: int, label_key: String) -> void:
	leave_pristine()
	if not is_present(index):
		return
	_free_from_rails(index)
	var b: int = index * 3
	var front: int = emit_front(
		state.pos[b], state.pos[b + 1], state.pos[b + 2], state.light_base[index] > 0.0, true, label_key
	)
	state.mode[index] = Gravity.Mode.GHOST
	_change_mass(index, front, -state.mass[index])
	_change_light(index, front, -state.light_base[index])
	if front < 0:
		state.mode[index] = Gravity.Mode.GONE
	for child: int in state.body_count():
		if state.mode[child] == Gravity.Mode.RAILS and state.parent[child] == index:
			state.mode[child] = Gravity.Mode.FREE
	_after_change(front)


## Gives a body a new velocity (AU/yr). Where the news has not arrived the
## old motion still pulls, as a ghost on the old path; the body keeps its
## index.
func fling(index: int, vx: float, vy: float, vz: float, label_key: String) -> void:
	leave_pristine()
	if not is_present(index):
		return
	_free_from_rails(index)
	var b: int = index * 3
	var front: int = emit_front(state.pos[b], state.pos[b + 1], state.pos[b + 2], false, true, label_key)
	if front >= 0:
		var original: CelestialBody = system.body(index)
		var ghost_body: CelestialBody = CelestialBody.new()
		ghost_body.id = StringName("%s_ghost_%d" % [original.id, state.body_count()])
		ghost_body.name_key = original.name_key
		ghost_body.kind = original.kind
		ghost_body.mass = original.mass
		ghost_body.radius = original.radius
		ghost_body.look = original.look
		var ghost: int = system.add(ghost_body)
		state.add_body(
			state.pos[b], state.pos[b + 1], state.pos[b + 2], state.vel[b], state.vel[b + 1], state.vel[b + 2],
			state.mass[index], state.radius[index], Gravity.Mode.GHOST, -1
		)
		_change_mass(ghost, front, -state.mass[index])
		var mass: float = state.mass[index]
		state.mass[index] = 0.0
		_change_mass(index, front, mass)
	state.vel[b] = vx
	state.vel[b + 1] = vy
	state.vel[b + 2] = vz
	_after_change(front)


## The body a new body at a point would circle: the one with the smallest
## Hill sphere around the point, else the one pulling hardest there.
func dominant_body(x: float, y: float, z: float) -> int:
	var best: int = -1
	var best_hill: float = INF
	var best_pull: float = 0.0
	for j: int in state.body_count():
		if not is_present(j) or state.mass[j] <= 0.0:
			continue
		var b: int = j * 3
		var dx: float = x - state.view_pos[b]
		var dy: float = y - state.view_pos[b + 1]
		var dz: float = z - state.view_pos[b + 2]
		var d2: float = dx * dx + dy * dy + dz * dz
		var hill: float = _hill_radius(j)
		if hill < INF:
			if d2 < hill * hill and hill < best_hill:
				best = j
				best_hill = hill
		elif best_hill == INF and state.mass[j] / maxf(d2, 1e-300) > best_pull:
			best = j
			best_pull = state.mass[j] / maxf(d2, 1e-300)
	return best


## The velocity (AU/yr) of a circular orbit through a point around the body
## that dominates there, prograde in the ecliptic plane.
func circular_velocity(x: float, y: float, z: float) -> PackedFloat64Array:
	var j: int = dominant_body(x, y, z)
	if j < 0:
		return PackedFloat64Array([0.0, 0.0, 0.0])
	var b: int = j * 3
	var rx: float = x - state.view_pos[b]
	var ry: float = y - state.view_pos[b + 1]
	var r: float = sqrt(rx * rx + ry * ry)
	if r <= 0.0:
		return state.view_vel.slice(b, b + 3)
	var speed: float = sqrt(Units.G * state.g_scale * state.mass[j] / r)
	return PackedFloat64Array([
		state.view_vel[b] - speed * ry / r, state.view_vel[b + 1] + speed * rx / r, state.view_vel[b + 2],
	])


## Where a small body starting at a point with a velocity would go over a
## duration (years), as samples x, y, z (NAN once it hits something). For
## previews: the system itself is not changed.
func predict_particle(
	x: float, y: float, z: float, vx: float, vy: float, vz: float, duration: float, samples: int
) -> PackedFloat64Array:
	var copy: NBodyState = state.copy()
	if copy.pristine:
		copy.pristine = false
		for i: int in copy.body_count():
			copy.mode[i] = Gravity.Mode.FREE
			copy.parent[i] = -1
	copy.time = clock.time
	copy.pos = state.view_pos.duplicate()
	copy.vel = state.view_vel.duplicate()
	copy.level = -1
	copy.acc_valid = false
	var particle: int = copy.add_particle(x, y, z, vx, vy, vz, 0.0, 0)
	return _core.call(&"predict", copy, PackedInt32Array(), PackedInt32Array([particle]), duration, samples, 20000)


## Brightness (L☉) of a body as seen at a point now: light travels too.
func felt_luminosity(index: int, x: float, y: float, z: float) -> float:
	return state.light_felt_at(index, x, y, z, clock.time)


## Starts a front at a point at the committed moment, carrying a change of
## light, of gravity or both. Returns its index, or -1 when changes are
## felt at once (the "instant" world law).
func emit_front(x: float, y: float, z: float, carries_light: bool, carries_gravity: bool, label_key: String) -> int:
	if is_inf(light_speed):
		return -1
	if fronts.size() >= Gravity.MAX_FRONTS:
		_fold_front(0)
	state.front_origin.append_array([x, y, z])
	state.front_time.append(state.time)
	state.front_speed.append(light_speed)
	var front: WaveFront = WaveFront.create(WaveFront.Kind.GRAVITY if carries_gravity else WaveFront.Kind.LIGHT, x, y, z, state.time)
	front.light = carries_light
	front.gravity = carries_gravity
	front.speed = light_speed
	front.label_key = label_key
	fronts.append(front)
	return fronts.size() - 1


## Jumps to a moment (years since J2000.0). An integrated system can only go
## forward, step by step, with no limit on the work.
func set_time(t: float) -> void:
	if state.pristine:
		clock.time = t
		system.place_on_orbits(t)
		_copy_rails_into_state()
		return
	if t < state.time:
		push_error("Simulation.set_time: an integrated system cannot go back to %s (it is at %s)" % [t, state.time])
		return
	_core.call(&"advance", state, t, 1 << 30, 1 << 30)
	clock.time = t
	_core.call(&"preview", state, t)
	_show_view()
	_update_fronts()


## A body's Hill sphere: from the kernel once integrated, else from its
## preset orbit around its parent (INF at the top).
func _hill_radius(index: int) -> float:
	if not state.pristine:
		return state.hill[index]
	var parent: int = system.body(index).parent
	if parent < 0:
		return INF
	return system.distance(index, parent) * pow(state.mass[index] / (3.0 * state.mass[parent]), 1.0 / 3.0)


func _change_mass(index: int, front: int, change: float) -> void:
	if change == 0.0:
		return
	if front < 0:
		state.mass[index] += change
	else:
		state.delta_body.append(index)
		state.delta_front.append(front)
		state.delta_mass.append(change)


func _change_light(index: int, front: int, change: float) -> void:
	if change == 0.0:
		return
	if front < 0:
		state.light_base[index] += change
	else:
		state.light_body.append(index)
		state.light_front.append(front)
		state.light_change.append(change)


## A body on rails is integrated again before it is changed.
func _free_from_rails(index: int) -> void:
	if state.mode[index] == Gravity.Mode.RAILS:
		state.mode[index] = Gravity.Mode.FREE


func _after_change(front: int) -> void:
	state.acc_valid = false
	if front >= 0:
		_core.call(&"schedule_front", state, front)
	_core.call(&"preview", state, clock.time)
	_show_view()


func _copy_rails_into_state() -> void:
	state.time = clock.time
	state.pos = system.positions.duplicate()
	state.vel = system.velocities.duplicate()
	state.view_pos = system.positions.duplicate()
	state.view_vel = system.velocities.duplicate()


## Where the kernel says everything is at the shown moment.
func _show_view() -> void:
	system.positions = state.view_pos.duplicate()
	system.velocities = state.view_vel.duplicate()


## A front is finished once it has passed every body and particle by a
## safe margin: its changes are then folded into the masses and brightness
## everyone feels, and a ghost whose removal is known everywhere is gone.
func _update_fronts() -> void:
	var f: int = 0
	while f < fronts.size():
		if _front_passed_everything(f):
			_fold_front(f)
		else:
			f += 1


func _front_passed_everything(f: int) -> bool:
	var speed: float = state.front_speed[f]
	if is_inf(speed):
		return true
	var reach: float = (clock.time - state.front_time[f]) * speed
	var ox: float = state.front_origin[f * 3]
	var oy: float = state.front_origin[f * 3 + 1]
	var oz: float = state.front_origin[f * 3 + 2]
	for i: int in state.body_count():
		if state.mode[i] == Gravity.Mode.GONE:
			continue
		var b: int = i * 3
		var dx: float = state.view_pos[b] - ox
		var dy: float = state.view_pos[b + 1] - oy
		var dz: float = state.view_pos[b + 2] - oz
		if sqrt(dx * dx + dy * dy + dz * dz) * 1.01 > reach:
			return false
	for p: int in state.particle_count():
		if state.p_mode[p] == Gravity.ParticleMode.GONE:
			continue
		var b: int = p * 3
		var dx: float = state.p_view[b] - ox
		var dy: float = state.p_view[b + 1] - oy
		var dz: float = state.p_view[b + 2] - oz
		if sqrt(dx * dx + dy * dy + dz * dz) * 1.01 > reach:
			return false
	return true


func _fold_front(f: int) -> void:
	var bodies: PackedInt32Array = []
	var front_ids: PackedInt32Array = []
	var changes: PackedFloat64Array = []
	for d: int in state.delta_body.size():
		if state.delta_front[d] == f:
			state.mass[state.delta_body[d]] += state.delta_mass[d]
		else:
			bodies.append(state.delta_body[d])
			front_ids.append(state.delta_front[d] - (1 if state.delta_front[d] > f else 0))
			changes.append(state.delta_mass[d])
	state.delta_body = bodies
	state.delta_front = front_ids
	state.delta_mass = changes
	var lit: PackedInt32Array = []
	var lit_fronts: PackedInt32Array = []
	var lit_changes: PackedFloat64Array = []
	for d: int in state.light_body.size():
		if state.light_front[d] == f:
			state.light_base[state.light_body[d]] += state.light_change[d]
		else:
			lit.append(state.light_body[d])
			lit_fronts.append(state.light_front[d] - (1 if state.light_front[d] > f else 0))
			lit_changes.append(state.light_change[d])
	state.light_body = lit
	state.light_front = lit_fronts
	state.light_change = lit_changes
	for k: int in 3:
		state.front_origin.remove_at(f * 3)
	state.front_time.remove_at(f)
	state.front_speed.remove_at(f)
	fronts.remove_at(f)
	for i: int in state.body_count():
		if state.mode[i] == Gravity.Mode.GHOST and not state.delta_body.has(i):
			state.mode[i] = Gravity.Mode.GONE
			state.mass[i] = 0.0
	state.acc_valid = false
