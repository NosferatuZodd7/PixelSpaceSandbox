class_name StarSystem
extends RefCounted
## A star system: its bodies and where they are.
##
## Positions and velocities are 64-bit, three numbers per body (x, y, z),
## in AU and AU per year, in the J2000 ecliptic frame centred on the first
## star. Bodies are stored parents first.

var name_key: String = ""
var bodies: Array[CelestialBody] = []
var positions: PackedFloat64Array = []
var velocities: PackedFloat64Array = []
## Crowds of small bodies, as the preset describes them (see SmallBodies).
var belts: Array[Dictionary] = []
## Named comets, as the preset describes them (see SmallBodies).
var comets: Array[Dictionary] = []


func size() -> int:
	return bodies.size()


func add(body: CelestialBody) -> int:
	bodies.append(body)
	positions.append_array([0.0, 0.0, 0.0])
	velocities.append_array([0.0, 0.0, 0.0])
	return bodies.size() - 1


func body(index: int) -> CelestialBody:
	return bodies[index]


func index_of(id: StringName) -> int:
	for i: int in bodies.size():
		if bodies[i].id == id:
			return i
	return -1


func x(index: int) -> float:
	return positions[index * 3]


func y(index: int) -> float:
	return positions[index * 3 + 1]


func z(index: int) -> float:
	return positions[index * 3 + 2]


func distance(from: int, to: int) -> float:
	var dx: float = positions[to * 3] - positions[from * 3]
	var dy: float = positions[to * 3 + 1] - positions[from * 3 + 1]
	var dz: float = positions[to * 3 + 2] - positions[from * 3 + 2]
	return sqrt(dx * dx + dy * dy + dz * dz)


func speed(index: int) -> float:
	var vx: float = velocities[index * 3]
	var vy: float = velocities[index * 3 + 1]
	var vz: float = velocities[index * 3 + 2]
	return sqrt(vx * vx + vy * vy + vz * vz)


## The star a body ultimately orbits (itself for a star), or -1.
func host_star(index: int) -> int:
	var current: int = index
	while current != -1 and not bodies[current].is_star():
		current = bodies[current].parent
	return current


## Indices of the bodies that orbit this one directly.
func children_of(index: int) -> PackedInt32Array:
	var found: PackedInt32Array = []
	for i: int in bodies.size():
		if bodies[i].parent == index:
			found.append(i)
	return found


## Total luminosity of the stars (L☉).
func total_luminosity() -> float:
	var total: float = 0.0
	for b: CelestialBody in bodies:
		if b.is_star():
			total += b.luminosity
	return total


## Moves every body to where its orbit puts it at time t.
func place_on_orbits(t: float) -> void:
	var count: int = bodies.size()
	var relative: Array[PackedFloat64Array] = []
	relative.resize(count)
	for i: int in count:
		var orbit: OrbitModel = bodies[i].orbit
		relative[i] = orbit.state_at(t) if orbit != null else PackedFloat64Array([0, 0, 0, 0, 0, 0])
	for i: int in count:
		var b: CelestialBody = bodies[i]
		var state: PackedFloat64Array = relative[i].duplicate()
		if b.barycenter_partner != -1:
			# The orbit is the pair's centre of mass: step back from it by the
			# partner's share of their separation.
			var partner: CelestialBody = bodies[b.barycenter_partner]
			var share: float = partner.mass / (partner.mass + b.mass)
			var offset: PackedFloat64Array = relative[b.barycenter_partner]
			for k: int in 6:
				state[k] -= share * offset[k]
		var base: int = i * 3
		var parent_base: int = b.parent * 3
		for k: int in 3:
			var parent_position: float = positions[parent_base + k] if b.parent != -1 else 0.0
			var parent_velocity: float = velocities[parent_base + k] if b.parent != -1 else 0.0
			positions[base + k] = parent_position + state[k]
			velocities[base + k] = parent_velocity + state[k + 3]
