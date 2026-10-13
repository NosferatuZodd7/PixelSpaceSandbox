class_name OrbitModel
extends RefCounted
## How a body moves around its parent on a fixed ("on rails") orbit.
##
## Positions are relative to the parent, in AU, in the J2000 ecliptic frame;
## velocities in AU per year. Time is in years since J2000.0.


## Position and velocity at time t: [x, y, z, vx, vy, vz].
func state_at(_t: float) -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])


## How long one orbit takes, in years.
func period_years() -> float:
	return 1.0


## Shape of the orbit at time t, for inspection: {"a": AU, "e": …, "i_deg": …}.
func elements_at(_t: float) -> Dictionary:
	return {"a": 0.0, "e": 0.0, "i_deg": 0.0}


## Points along one full orbit around the parent, as x, y, z triples (AU),
## for drawing. By default samples the motion over one period.
func path(t: float, count: int) -> PackedFloat64Array:
	var points: PackedFloat64Array = []
	var period: float = period_years()
	for k: int in count:
		var state: PackedFloat64Array = state_at(t + period * k / count)
		points.append(state[0])
		points.append(state[1])
		points.append(state[2])
	return points
