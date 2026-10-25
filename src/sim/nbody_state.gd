class_name NBodyState
extends RefCounted
## The committed state of the gravity simulation, kept in plain packed
## arrays that both gravity kernels (native and GDScript) read and write.
##
## Massive bodies are integrated ("free": every body pulls them) or ride a
## fixed conic around a parent ("rails"). A removed body becomes a "ghost"
## that keeps pulling the bodies its removal has not reached yet. Particles
## (asteroids, comets, debris) are pulled but pull nothing: asleep they ride
## a conic around a parent, awake they are integrated.
##
## A change of mass travels at the speed of light: each one is a "delta" on
## a body, felt only by receivers the front has reached. Units: AU, M☉,
## years since J2000.0.

## The array fields, in the order saves and snapshots store them.
const ARRAY_FIELDS: Array[StringName] = [
	&"pos", &"vel", &"acc", &"mass", &"radius", &"mode", &"parent", &"hill", &"rail",
	&"delta_body", &"delta_front", &"delta_mass", &"light_base", &"light_body", &"light_front", &"light_change",
	&"front_origin", &"front_time", &"front_speed",
	&"p_mode", &"p_primary", &"p_level", &"p_kind", &"p_elem", &"p_pos", &"p_vel", &"p_acc",
	&"p_last", &"p_next", &"p_radius", &"p_tau",
]
const SCALAR_FIELDS: Array[StringName] = [
	&"time", &"level", &"level_up", &"step_count", &"g_scale", &"collisions_enabled", &"acc_valid",
	&"pristine", &"rails_tau",
]

## Committed time, in years since J2000.0.
var time: float = 0.0
## Current step: 2^level × Gravity.UNIT years (-1: not chosen yet).
var level: int = -1
var level_up: int = 0
var step_count: int = 0
## World law: multiplies G.
var g_scale: float = 1.0
var collisions_enabled: bool = true
## False after any change made outside the kernel: accelerations, parents
## and Hill spheres are then worked out afresh before the next step.
var acc_valid: bool = false
## True while every body still follows its original orbit (the untouched
## preset): nothing is integrated and the kernel only places particles.
var pristine: bool = false
## Free bodies whose orbit around their parent takes less than about this
## (in years, as a dynamical time) ride rails instead, so very fast time
## stays affordable; 0 never does that. Set from the time speed.
var rails_tau: float = 0.0

# Massive bodies (3 numbers per body for vectors).
var pos: PackedFloat64Array = []
var vel: PackedFloat64Array = []
var acc: PackedFloat64Array = []
## Mass felt by receivers before any travelling change (M☉).
var mass: PackedFloat64Array = []
var radius: PackedFloat64Array = []
var mode: PackedInt32Array = []
## Rails: the body it circles. Free: the body it is bound to (for Hill
## spheres and sleeping particles), or -1.
var parent: PackedInt32Array = []
## Radius of its Hill sphere around its parent (INF at the top).
var hill: PackedFloat64Array = []
## Rails: Kepler element set around the parent (Gravity.ELEMENT_SIZE per body).
var rail: PackedFloat64Array = []

# Mass changes still travelling: receivers inside the front feel mass + delta.
var delta_body: PackedInt32Array = []
var delta_front: PackedInt32Array = []
var delta_mass: PackedFloat64Array = []

# Light: a star's brightness as seen by a receiver is light_base plus the
# changes whose front has reached it (the kernel does not use these).
var light_base: PackedFloat64Array = []
var light_body: PackedInt32Array = []
var light_front: PackedInt32Array = []
var light_change: PackedFloat64Array = []

# Fronts (geometry only; Simulation keeps what each one carries).
var front_origin: PackedFloat64Array = []
var front_time: PackedFloat64Array = []
## AU per year; INF for the "instant" world law.
var front_speed: PackedFloat64Array = []

# Particles.
var p_mode: PackedInt32Array = []
## Asleep: the body it circles.
var p_primary: PackedInt32Array = []
## Awake: steps once every 2^p_level global steps (-1: needs its first pull).
var p_level: PackedInt32Array = []
## What it is (ParticleKind), for drawing and events; kernels ignore it.
var p_kind: PackedInt32Array = []
var p_elem: PackedFloat64Array = []
var p_pos: PackedFloat64Array = []
var p_vel: PackedFloat64Array = []
var p_acc: PackedFloat64Array = []
## Awake: the time of its last step. Asleep: of its last check.
var p_last: PackedFloat64Array = []
## When it is next checked: asleep, whether to wake; awake, whether to sleep.
var p_next: PackedFloat64Array = []
var p_radius: PackedFloat64Array = []
## Awake: its dynamical time at its last step (years).
var p_tau: PackedFloat64Array = []

# Where things are drawn: written by the kernel's preview().
var view_pos: PackedFloat64Array = []
var view_vel: PackedFloat64Array = []
var p_view: PackedFloat64Array = []


func body_count() -> int:
	return mass.size()


func particle_count() -> int:
	return p_mode.size()


func add_body(
	x: float, y: float, z: float, vx: float, vy: float, vz: float,
	body_mass: float, body_radius: float, body_mode: Gravity.Mode, parent_index: int
) -> int:
	pos.append_array([x, y, z])
	vel.append_array([vx, vy, vz])
	acc.append_array([0.0, 0.0, 0.0])
	view_pos.append_array([x, y, z])
	view_vel.append_array([vx, vy, vz])
	mass.append(body_mass)
	radius.append(body_radius)
	mode.append(body_mode)
	parent.append(parent_index)
	hill.append(INF)
	light_base.append(0.0)
	var empty: PackedFloat64Array = PackedFloat64Array()
	empty.resize(Gravity.ELEMENT_SIZE)
	rail.append_array(empty)
	acc_valid = false
	return mass.size() - 1


## Adds an awake particle at a position and velocity.
func add_particle(
	x: float, y: float, z: float, vx: float, vy: float, vz: float,
	particle_radius: float, kind: int
) -> int:
	p_mode.append(Gravity.ParticleMode.AWAKE)
	p_primary.append(-1)
	p_level.append(-1)
	p_kind.append(kind)
	var empty: PackedFloat64Array = PackedFloat64Array()
	empty.resize(Gravity.ELEMENT_SIZE)
	p_elem.append_array(empty)
	p_pos.append_array([x, y, z])
	p_vel.append_array([vx, vy, vz])
	p_acc.append_array([0.0, 0.0, 0.0])
	p_view.append_array([x, y, z])
	p_last.append(time)
	p_next.append(time)
	p_radius.append(particle_radius)
	p_tau.append(INF)
	return p_mode.size() - 1


## Adds an asleep particle riding a Kepler element set around a body.
func add_sleeping_particle(primary: int, elements: PackedFloat64Array, particle_radius: float, kind: int) -> int:
	var index: int = add_particle(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, particle_radius, kind)
	p_mode[index] = Gravity.ParticleMode.ASLEEP
	p_primary[index] = primary
	for k: int in Gravity.ELEMENT_SIZE:
		p_elem[index * Gravity.ELEMENT_SIZE + k] = elements[k]
	return index


## Puts a body on rails around a parent from its current state.
func set_rails_from_state(index: int, parent_index: int) -> bool:
	var mu: float = Units.G * g_scale * (mass[parent_index] + mass[index])
	var elements: PackedFloat64Array = Kepler.elements_from_state(
		pos[index * 3] - pos[parent_index * 3], pos[index * 3 + 1] - pos[parent_index * 3 + 1],
		pos[index * 3 + 2] - pos[parent_index * 3 + 2], vel[index * 3] - vel[parent_index * 3],
		vel[index * 3 + 1] - vel[parent_index * 3 + 1], vel[index * 3 + 2] - vel[parent_index * 3 + 2],
		mu, time
	)
	if elements.is_empty():
		return false
	for k: int in Gravity.ELEMENT_SIZE:
		rail[index * Gravity.ELEMENT_SIZE + k] = elements[k]
	mode[index] = Gravity.Mode.RAILS
	parent[index] = parent_index
	acc_valid = false
	return true


## Effective mass of a body as felt at a point: its mass plus the changes
## whose fronts have reached the point at time t.
func mass_felt_at(index: int, x: float, y: float, z: float, t: float) -> float:
	var felt: float = mass[index]
	for d: int in delta_body.size():
		if delta_body[d] != index:
			continue
		var f: int = delta_front[d]
		var dx: float = x - front_origin[f * 3]
		var dy: float = y - front_origin[f * 3 + 1]
		var dz: float = z - front_origin[f * 3 + 2]
		var reach: float = (t - front_time[f]) * front_speed[f]
		if is_inf(front_speed[f]) or reach * reach >= dx * dx + dy * dy + dz * dz:
			felt += delta_mass[d]
	return felt


## Brightness (L☉) of a body as seen at a point at time t: its base plus the
## changes whose front has arrived there.
func light_felt_at(index: int, x: float, y: float, z: float, t: float) -> float:
	var felt: float = light_base[index]
	for d: int in light_body.size():
		if light_body[d] != index:
			continue
		var f: int = light_front[d]
		var dx: float = x - front_origin[f * 3]
		var dy: float = y - front_origin[f * 3 + 1]
		var dz: float = z - front_origin[f * 3 + 2]
		var reach: float = (t - front_time[f]) * front_speed[f]
		if is_inf(front_speed[f]) or reach * reach >= dx * dx + dy * dy + dz * dz:
			felt += light_change[d]
	return felt


## A deep copy: arrays in GDScript are shared references, so each one is
## duplicated.
func copy() -> NBodyState:
	var other: NBodyState = NBodyState.new()
	for field: StringName in SCALAR_FIELDS:
		other.set(field, get(field))
	for field: StringName in ARRAY_FIELDS:
		other.set(field, get(field).duplicate())
	other.view_pos = view_pos.duplicate()
	other.view_vel = view_vel.duplicate()
	other.p_view = p_view.duplicate()
	return other


func to_dict() -> Dictionary:
	var data: Dictionary = {}
	for field: StringName in SCALAR_FIELDS:
		data[field] = get(field)
	for field: StringName in ARRAY_FIELDS:
		data[field] = get(field).duplicate()
	return data


static func from_dict(data: Dictionary) -> NBodyState:
	var state: NBodyState = NBodyState.new()
	for field: StringName in SCALAR_FIELDS:
		if data.has(field):
			state.set(field, data[field])
	for field: StringName in ARRAY_FIELDS:
		if data.has(field):
			state.set(field, (data[field] as Variant).duplicate())
	state.view_pos = state.pos.duplicate()
	state.view_vel = state.vel.duplicate()
	state.p_view = state.p_pos.duplicate()
	state.acc_valid = false
	return state
