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
	_drop_finished_fronts()


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


## A front is finished once it has passed every body by a safe margin.
func _drop_finished_fronts() -> void:
	if fronts.is_empty():
		return
	var kept: Array[WaveFront] = []
	for front: WaveFront in fronts:
		if not front.has_passed_all(system, clock.time):
			kept.append(front)
	fronts = kept
