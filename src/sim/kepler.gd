class_name Kepler
extends RefCounted
## Kepler's equation and the conversion from orbital elements to position
## and velocity. Angles in radians, distances in AU, time in years.

const TOLERANCE: float = 1e-14
const MAX_ITERATIONS: int = 64


## Solves Kepler's equation M = E − e·sin E for the eccentric anomaly E,
## for elliptic orbits (0 ≤ e < 1). Newton's method from a safe start.
static func eccentric_anomaly(mean_anomaly: float, e: float) -> float:
	var m: float = wrapf(mean_anomaly, -PI, PI)
	var anomaly: float = m if e < 0.8 else PI * signf(m)
	for i: int in MAX_ITERATIONS:
		var step: float = (anomaly - e * sin(anomaly) - m) / (1.0 - e * cos(anomaly))
		anomaly -= step
		if absf(step) < TOLERANCE:
			break
	return anomaly


## Position and velocity on an elliptic orbit, relative to the focus:
## [x, y, z, vx, vy, vz]. mean_motion is in radians per year. The elements
## are measured in whatever frame the caller works in (usually the ecliptic).
static func state_from_elements(
	a: float, e: float, inclination: float, node: float, arg_periapsis: float,
	mean_anomaly: float, mean_motion: float
) -> PackedFloat64Array:
	var anomaly: float = eccentric_anomaly(mean_anomaly, e)
	var cos_e: float = cos(anomaly)
	var sin_e: float = sin(anomaly)
	var root: float = sqrt(1.0 - e * e)
	# In the orbit's own plane, x towards periapsis.
	var px: float = a * (cos_e - e)
	var py: float = a * root * sin_e
	var anomaly_rate: float = mean_motion / (1.0 - e * cos_e)
	var vx: float = -a * sin_e * anomaly_rate
	var vy: float = a * root * cos_e * anomaly_rate
	return rotate_from_orbit_plane(px, py, vx, vy, inclination, node, arg_periapsis)


## Turns in-plane coordinates (x towards periapsis) into the reference frame.
static func rotate_from_orbit_plane(
	px: float, py: float, vx: float, vy: float, inclination: float, node: float, arg_periapsis: float
) -> PackedFloat64Array:
	var cw: float = cos(arg_periapsis)
	var sw: float = sin(arg_periapsis)
	var cn: float = cos(node)
	var sn: float = sin(node)
	var ci: float = cos(inclination)
	var si: float = sin(inclination)
	var xx: float = cw * cn - sw * sn * ci
	var xy: float = -sw * cn - cw * sn * ci
	var yx: float = cw * sn + sw * cn * ci
	var yy: float = -sw * sn + cw * cn * ci
	var zx: float = sw * si
	var zy: float = cw * si
	return PackedFloat64Array([
		xx * px + xy * py, yx * px + yy * py, zx * px + zy * py,
		xx * vx + xy * vy, yx * vx + yy * vy, zx * vx + zy * vy,
	])


## Orbital period in years for a semi-major axis (AU) around a total mass (M☉).
static func period_years(a: float, total_mass: float) -> float:
	return TAU * sqrt(a * a * a / (Units.G * total_mass))


## Mean motion in radians per year.
static func mean_motion(a: float, total_mass: float) -> float:
	return sqrt(Units.G * total_mass / (a * a * a))
