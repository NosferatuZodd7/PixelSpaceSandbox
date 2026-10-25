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
## What happened as time ran, oldest first, for notifications: for now
## {"kind": "merge", "body": survivor, "other": absorbed, "time": years}.
## Whoever reads them may clear the list.
var events: Array[Dictionary] = []
## Counts the changes made to the system (places, removals, flings), so
## views know when to redraw what they cache.
var changes: int = 0
## Named small bodies (comets): particle index by name key.
var particle_names: Dictionary[String, int] = {}
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
	particle_names = SmallBodies.populate(state, system, clock.time, state.g_scale)


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
	# Each body keeps circling what it circled (the kernel reviews this
	# before its first step; until then it is what the screen shows).
	for i: int in count:
		state.hill[i] = _hill_radius(i)
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
		if state.particle_count() > 0:
			_core.call(&"preview", state, clock.time)
	else:
		lagging = false
		if not clock.paused:
			state.rails_tau = clock.speed() * FRAME_SECONDS / TARGET_STEPS / Gravity.ETA / Units.YEAR_SECONDS
			var target: float = clock.time + real_seconds * clock.years_per_second()
			lagging = not _run_to(target, max_steps_per_frame, max_usec_per_frame)
			clock.time = state.time if lagging else target
		_core.call(&"preview", state, clock.time)
		_show_view()
	_update_fronts()


## The particle of a named small body (a comet), or -1.
func particle_named(name_key: String) -> int:
	return particle_names.get(name_key, -1)


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
	var parent: int = dominant_body(x, y, z)
	var index: int = system.add(body)
	state.add_body(x, y, z, vx, vy, vz, 0.0, body.radius, Gravity.Mode.FREE, parent)
	var front: int = emit_front(x, y, z, body.luminosity > 0.0, true, label_key, index)
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
	var light: float = state.final_light(index)
	var front: int = emit_front(state.pos[b], state.pos[b + 1], state.pos[b + 2], light > 0.0, true, label_key, index)
	if front < 0:
		state.mode[index] = Gravity.Mode.GONE
		_forget_changes(index)
		state.mass[index] = 0.0
		state.light_base[index] = 0.0
	else:
		# All of it goes, including any arrival of its own still on its way.
		state.mode[index] = Gravity.Mode.GHOST
		_change_mass(index, front, -state.final_mass(index))
		_change_light(index, front, -light)
	# Its moons now circle what it circled (the kernel reviews this before
	# its next step; until then it is what the screen shows).
	for child: int in state.body_count():
		if state.parent[child] == index:
			state.parent[child] = state.parent[index]
			if state.mode[child] == Gravity.Mode.RAILS:
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
	var mass: float = state.final_mass(index)
	var light: float = state.final_light(index)
	var front: int = emit_front(state.pos[b], state.pos[b + 1], state.pos[b + 2], light > 0.0, true, label_key, index)
	if front >= 0:
		_leave_ghost(index, front)
		_change_mass(index, front, mass)
		_change_light(index, front, light)
	state.vel[b] = vx
	state.vel[b + 1] = vy
	state.vel[b + 2] = vz
	_after_change(front)


## Two bodies that touch become one. The heavier keeps its name (a black
## hole always does) and takes the other's mass and momentum, at their
## centre of mass; the volumes add up, a black hole's horizon grows with its
## mass, and two stars make one brighter by the mass-luminosity law. Where
## the news has not arrived, both pull on as ghosts along their old paths,
## so the far field does not jump. Returns the survivor.
func merge(first: int, second: int, label_key: String) -> int:
	leave_pristine()
	var big: int = first
	var small: int = second
	var first_hole: bool = system.body(first).kind == CelestialBody.Kind.BLACK_HOLE
	var second_hole: bool = system.body(second).kind == CelestialBody.Kind.BLACK_HOLE
	if (second_hole and not first_hole) or (second_hole == first_hole and state.final_mass(second) > state.final_mass(first)):
		big = second
		small = first
	_absorb(big, small, label_key, big, true)
	events.append({"kind": "merge", "body": big, "other": small, "time": state.time})
	return big


## One body takes another's mass and momentum at their centre of mass
## (see merge); grow says whether the other's volume adds to its own (not
## for a body torn into a ring). The front's label names label_body.
func _absorb(big: int, small: int, label_key: String, label_body: int, grow: bool) -> void:
	_free_from_rails(big)
	_free_from_rails(small)
	var m_big: float = state.final_mass(big)
	var m_small: float = state.final_mass(small)
	var total: float = m_big + m_small
	var share: float = m_small / total if total > 0.0 else 0.5
	var bb: int = big * 3
	var bs: int = small * 3
	var merged: PackedFloat64Array = PackedFloat64Array()
	for k: int in 3:
		merged.append(lerpf(state.pos[bb + k], state.pos[bs + k], share))
	for k: int in 3:
		merged.append(lerpf(state.vel[bb + k], state.vel[bs + k], share))
	var keeper: CelestialBody = system.body(big)
	var absorbed: CelestialBody = system.body(small)
	var light: float = state.final_light(big)
	if keeper.kind == CelestialBody.Kind.BLACK_HOLE:
		light = 0.0
	elif keeper.is_star() and absorbed.is_star() and m_big > 0.0:
		light *= pow(total / m_big, 3.5)
	var radius: float = state.radius[big]
	if keeper.kind == CelestialBody.Kind.BLACK_HOLE:
		radius = 2.0 * Units.G * total / (Units.C * Units.C)
	elif grow:
		radius = pow(pow(state.radius[big], 3.0) + pow(state.radius[small], 3.0), 1.0 / 3.0)
	var front: int = emit_front(
		merged[0], merged[1], merged[2], light > 0.0 or state.final_light(small) > 0.0, true, label_key, label_body
	)
	if front < 0:
		_forget_changes(big)
		state.mass[big] = total
		state.light_base[big] = light
		_forget_changes(small)
		state.mode[small] = Gravity.Mode.GONE
		state.mass[small] = 0.0
		state.light_base[small] = 0.0
	else:
		_leave_ghost(big, front)
		_change_mass(big, front, total)
		_change_light(big, front, light)
		state.mode[small] = Gravity.Mode.GHOST
		_change_mass(small, front, -m_small)
		_change_light(small, front, -state.final_light(small))
	for k: int in 3:
		state.pos[bb + k] = merged[k]
		state.vel[bb + k] = merged[k + 3]
	state.radius[big] = radius
	keeper.mass = total
	keeper.radius = radius
	keeper.luminosity = light
	for child: int in state.body_count():
		if state.parent[child] == small:
			state.parent[child] = big
	if state.parent[big] == small:
		state.parent[big] = state.parent[small]
	_after_change(front)


## The body a new body at a point would circle: the one with the smallest
## Hill sphere around the point, else the one pulling hardest there.
func dominant_body(x: float, y: float, z: float) -> int:
	var best: int = -1
	var best_hill: float = INF
	var best_pull: float = 0.0
	for j: int in state.body_count():
		var mass: float = state.final_mass(j)
		if not is_present(j) or mass <= 0.0:
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
		elif best_hill == INF and mass / maxf(d2, 1e-300) > best_pull:
			best = j
			best_pull = mass / maxf(d2, 1e-300)
	return best


## The point in space under a point of the screen (which shows space from
## above, x and y in AU): at the height of the body that dominates there,
## so a body placed there circles in that body's plane.
func point_in_plane(x: float, y: float) -> PackedFloat64Array:
	var z: float = 0.0
	for attempt: int in 2:
		var j: int = dominant_body(x, y, z)
		if j < 0:
			break
		z = state.view_pos[j * 3 + 2]
	return PackedFloat64Array([x, y, z])


## The velocity (AU/yr) of a circular orbit through a point around the body
## that dominates there, prograde in the ecliptic plane, for a body of this
## mass (M☉).
func circular_velocity(x: float, y: float, z: float, mass: float = 0.0) -> PackedFloat64Array:
	var j: int = dominant_body(x, y, z)
	if j < 0:
		return PackedFloat64Array([0.0, 0.0, 0.0])
	var b: int = j * 3
	var rx: float = x - state.view_pos[b]
	var ry: float = y - state.view_pos[b + 1]
	var r: float = sqrt(rx * rx + ry * ry)
	if r <= 0.0:
		return state.view_vel.slice(b, b + 3)
	var speed: float = sqrt(Units.G * state.g_scale * (state.final_mass(j) + mass) / r)
	return PackedFloat64Array([
		state.view_vel[b] - speed * ry / r, state.view_vel[b + 1] + speed * rx / r, state.view_vel[b + 2],
	])


## The velocity (AU/yr) of a body sweeping through a point on its way
## across the system: it passes closest to the star it falls towards there,
## prograde, and leaves at speed_far (AU/yr) once far away.
func flyby_velocity(x: float, y: float, z: float, speed_far: float) -> PackedFloat64Array:
	var j: int = dominant_body(x, y, z)
	while j >= 0 and parent_of(j) >= 0:
		j = parent_of(j)
	if j < 0:
		return PackedFloat64Array([0.0, speed_far, 0.0])
	var b: int = j * 3
	var rx: float = x - state.view_pos[b]
	var ry: float = y - state.view_pos[b + 1]
	var rz: float = z - state.view_pos[b + 2]
	var r: float = sqrt(rx * rx + ry * ry)
	if r <= 0.0:
		return PackedFloat64Array([0.0, speed_far, 0.0])
	var escape_squared: float = 2.0 * Units.G * state.g_scale * state.final_mass(j) / sqrt(r * r + rz * rz)
	var speed: float = sqrt(speed_far * speed_far + escape_squared)
	return PackedFloat64Array([
		state.view_vel[b] - speed * ry / r, state.view_vel[b + 1] + speed * rx / r, state.view_vel[b + 2],
	])


## The body a body circles now, or -1: its parent while the system is
## untouched; once integrated, the one whose Hill sphere it is in (else the
## one pulling hardest), as the kernel last reviewed it.
func parent_of(index: int) -> int:
	return state.parent[index]


## A body's orbit around what it circles, as it is at the shown moment: a
## Kepler element set (see Kepler.elements_from_state), or empty when it
## circles nothing.
func orbit_elements(index: int) -> PackedFloat64Array:
	var p: int = parent_of(index)
	if p < 0 or not is_present(index):
		return PackedFloat64Array()
	var b: int = index * 3
	var q: int = p * 3
	var view: PackedFloat64Array = state.view_pos
	var view_vel: PackedFloat64Array = state.view_vel
	return Kepler.elements_from_state(
		view[b] - view[q], view[b + 1] - view[q + 1], view[b + 2] - view[q + 2],
		view_vel[b] - view_vel[q], view_vel[b + 1] - view_vel[q + 1], view_vel[b + 2] - view_vel[q + 2],
		Units.G * state.g_scale * (state.final_mass(p) + state.final_mass(index)), clock.time
	)


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


## The starlight arriving at a point now, in L☉ per AU² (about 1 at the
## Earth): every star counts once its light has got there.
func flux_at(x: float, y: float, z: float) -> float:
	var total: float = 0.0
	for i: int in system.size():
		if system.body(i).is_star():
			total += _starlight(i, x, y, z)
	return total


## The star lighting a point the most now, or -1 in the dark.
func main_star_at(x: float, y: float, z: float) -> int:
	var best: int = -1
	var best_light: float = 0.0
	for i: int in system.size():
		if system.body(i).is_star():
			var light: float = _starlight(i, x, y, z)
			if light > best_light:
				best = i
				best_light = light
	return best


## The news still on its way to a body: for each front that has not
## reached it yet, {"front": index, "body": what changed, "label_key",
## "seconds": simulated seconds until it arrives}, soonest first.
func news_for(index: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var b: int = index * 3
	for f: int in fronts.size():
		var front: WaveFront = fronts[f]
		if front.body == index:
			continue
		var distance: float = front.distance_to(state.view_pos[b], state.view_pos[b + 1], state.view_pos[b + 2])
		var left: float = front.emitted_at + distance / front.speed - clock.time
		if left > 0.0:
			found.append({"front": f, "body": front.body, "label_key": front.label_key, "seconds": left * Units.YEAR_SECONDS})
	found.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return a["seconds"] < c["seconds"])
	return found


## The next moment a front reaches a body that is still in the system
## (moons left out when skip_moons is true): {"time": years, "body",
## "front"}, or empty when no news is travelling.
func next_arrival(skip_moons: bool = false) -> Dictionary:
	var best: Dictionary = {}
	for i: int in system.size():
		if not is_present(i) or (skip_moons and system.body(i).kind == CelestialBody.Kind.MOON):
			continue
		var news: Array[Dictionary] = news_for(i)
		if news.is_empty():
			continue
		var at: float = clock.time + float(news[0]["seconds"]) / Units.YEAR_SECONDS
		if best.is_empty() or at < float(best["time"]):
			best = {"time": at, "body": i, "front": news[0]["front"]}
	return best


## Runs time on to just after the next arrival (a second after it; bodies
## move while the news travels, so it checks and goes on if needed).
func jump_to_next_arrival() -> void:
	var next: Dictionary = next_arrival()
	if next.is_empty():
		return
	set_time(float(next["time"]) + 1.0 / Units.YEAR_SECONDS)
	for attempt: int in 3:
		var left: Array[Dictionary] = news_for(next["body"]).filter(
			func(news: Dictionary) -> bool: return news["front"] == next["front"])
		if left.is_empty():
			return
		set_time(clock.time + (float(left[0]["seconds"]) + 1.0) / Units.YEAR_SECONDS)


## Starts a front at a point at the committed moment, carrying a change of
## light, of gravity or both, about a body (or -1). Returns its index, or -1
## when changes are felt at once (the "instant" world law).
func emit_front(
	x: float, y: float, z: float, carries_light: bool, carries_gravity: bool, label_key: String, body: int = -1
) -> int:
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
	front.body = body
	fronts.append(front)
	return fronts.size() - 1


## Jumps to a moment (years since J2000.0). An integrated system can only go
## forward, step by step, with no limit on the work.
func set_time(t: float) -> void:
	if state.pristine:
		clock.time = t
		system.place_on_orbits(t)
		_copy_rails_into_state()
		_core.call(&"preview", state, t)
		return
	if t < state.time:
		push_error("Simulation.set_time: an integrated system cannot go back to %s (it is at %s)" % [t, state.time])
		return
	_run_to(t, 1 << 30, 1 << 30)
	clock.time = t
	_core.call(&"preview", state, t)
	_show_view()
	_update_fronts()


## A body's Hill sphere around what it circles (INF at the top), from the
## masses everyone will feel once the news has spread: placing and
## circling bodies should not wait for the light.
func _hill_radius(index: int) -> float:
	var parent: int = parent_of(index)
	if parent < 0:
		return INF
	var b: int = index * 3
	var q: int = parent * 3
	var dx: float = state.view_pos[b] - state.view_pos[q]
	var dy: float = state.view_pos[b + 1] - state.view_pos[q + 1]
	var dz: float = state.view_pos[b + 2] - state.view_pos[q + 2]
	var parent_mass: float = state.final_mass(parent)
	if parent_mass <= 0.0:
		return INF
	var share: float = state.final_mass(index) / (3.0 * parent_mass)
	return sqrt(dx * dx + dy * dy + dz * dz) * pow(share, 1.0 / 3.0)


func _starlight(star: int, x: float, y: float, z: float) -> float:
	var b: int = star * 3
	var dx: float = x - state.view_pos[b]
	var dy: float = y - state.view_pos[b + 1]
	var dz: float = z - state.view_pos[b + 2]
	return felt_luminosity(star, x, y, z) / maxf(dx * dx + dy * dy + dz * dz, 1e-12)


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


## The lighter of two bodies that came within its Roche limit of the
## heavier is torn apart: its material spreads into a ring around the
## heavier body, whose mass and momentum it joins.
func _tear_apart(primary: int, satellite: int) -> void:
	var b: int = satellite * 3
	var q: int = primary * 3
	var dx: float = state.view_pos[b] - state.view_pos[q]
	var dy: float = state.view_pos[b + 1] - state.view_pos[q + 1]
	var dz: float = state.view_pos[b + 2] - state.view_pos[q + 2]
	var distance: float = sqrt(dx * dx + dy * dy + dz * dz)
	var torn: CelestialBody = system.body(satellite)
	var color: StringName = &"dust"
	if torn.is_star():
		color = &"accretion"
	elif torn.radius > 0.0:
		var radius_m: float = Units.km_from_au(torn.radius) * 1000.0
		var density: float = Units.kg_from_solar_masses(state.final_mass(satellite)) / (4.0 / 3.0 * PI * pow(radius_m, 3.0))
		if density < 2000.0:
			color = &"ice"
	_absorb(primary, satellite, "FRONT_TORN", satellite, false)
	system.body(primary).rings.append({
		"inner": maxf(0.8 * distance, 1.1 * state.radius[primary]), "outer": maxf(1.2 * distance, 1.3 * state.radius[primary]),
		"color": color, "density": 0.5,
	})
	events.append({"kind": "disrupt", "body": primary, "other": satellite, "time": state.time})


## Runs the kernel up to a moment, merging bodies that touch on the way
## and tearing apart those that come within their Roche limit. False when
## the work allowed ran out first.
func _run_to(target: float, max_steps: int, max_usec: int) -> bool:
	var started: int = Time.get_ticks_usec()
	var steps_left: int = max_steps
	while true:
		var spent: int = Time.get_ticks_usec() - started
		var result: Dictionary = _core.call(&"advance", state, target, steps_left, maxi(max_usec - spent, 0))
		var status: int = int(result["status"])
		steps_left -= int(result["steps"])
		if status == Gravity.Status.EVENTS:
			var pairs: PackedInt32Array = result["collisions"]
			var gaps: PackedFloat64Array = result["collision_gaps"]
			for k: int in range(0, pairs.size(), 2):
				var i: int = pairs[k]
				var j: int = pairs[k + 1]
				if not is_present(i) or not is_present(j):
					continue
				if gaps[k >> 1] <= state.radius[i] + state.radius[j]:
					merge(i, j, "FRONT_MERGED")
				elif state.final_mass(i) < state.final_mass(j):
					_tear_apart(j, i)
				else:
					_tear_apart(i, j)
			if steps_left <= 0 or Time.get_ticks_usec() - started > max_usec:
				return state.time + Gravity.step_size(state.level) > target
			continue
		return status != Gravity.Status.BUDGET
	return true


## Leaves a ghost of a body on its old path, as the far side of the system
## still knows it: with its mass, light and changes still on their way,
## until the news of this front arrives. The body itself starts again from
## nothing behind the front (the caller adds what it now is).
func _leave_ghost(index: int, front: int) -> int:
	var b: int = index * 3
	var original: CelestialBody = system.body(index)
	var ghost_body: CelestialBody = CelestialBody.new()
	ghost_body.id = StringName("%s_ghost_%d" % [original.id, state.body_count()])
	ghost_body.name_key = original.name_key
	ghost_body.name_number = original.name_number
	ghost_body.kind = original.kind
	ghost_body.mass = original.mass
	ghost_body.radius = original.radius
	ghost_body.luminosity = original.luminosity
	ghost_body.temperature = original.temperature
	ghost_body.look = original.look
	var mass: float = state.final_mass(index)
	var light: float = state.final_light(index)
	var ghost: int = system.add(ghost_body)
	state.add_body(
		state.pos[b], state.pos[b + 1], state.pos[b + 2], state.vel[b], state.vel[b + 1], state.vel[b + 2],
		state.mass[index], state.radius[index], Gravity.Mode.GHOST, -1
	)
	state.light_base[ghost] = state.light_base[index]
	_move_changes(index, ghost)
	_change_mass(ghost, front, -mass)
	_change_light(ghost, front, -light)
	state.mass[index] = 0.0
	state.light_base[index] = 0.0
	return ghost


## Hands the changes still travelling for one body over to another.
func _move_changes(from: int, to: int) -> void:
	for d: int in state.delta_body.size():
		if state.delta_body[d] == from:
			state.delta_body[d] = to
	for d: int in state.light_body.size():
		if state.light_body[d] == from:
			state.light_body[d] = to


## Drops the changes still travelling for a body.
func _forget_changes(index: int) -> void:
	for d: int in range(state.delta_body.size() - 1, -1, -1):
		if state.delta_body[d] == index:
			state.delta_body.remove_at(d)
			state.delta_front.remove_at(d)
			state.delta_mass.remove_at(d)
	for d: int in range(state.light_body.size() - 1, -1, -1):
		if state.light_body[d] == index:
			state.light_body.remove_at(d)
			state.light_front.remove_at(d)
			state.light_change.remove_at(d)


## A body on rails is integrated again before it is changed.
func _free_from_rails(index: int) -> void:
	if state.mode[index] == Gravity.Mode.RAILS:
		state.mode[index] = Gravity.Mode.FREE


func _after_change(front: int) -> void:
	changes += 1
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


## A front is finished once it has passed every body and awake particle by
## a safe margin: its changes are then folded into the masses and brightness
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
	# Asleep particles ride fixed conics and notice a change only when they
	# are next checked, which the kernel schedules for when its news
	# arrives; they need not hold a front back.
	for p: int in state.particle_count():
		if state.p_mode[p] != Gravity.ParticleMode.AWAKE:
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
