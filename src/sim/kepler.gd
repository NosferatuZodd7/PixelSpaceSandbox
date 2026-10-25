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


## Solves the hyperbolic Kepler equation M = e·sinh H − H for H (e > 1).
static func hyperbolic_anomaly(mean_anomaly: float, e: float) -> float:
	var anomaly: float = 0.0
	if mean_anomaly != 0.0:
		anomaly = signf(mean_anomaly) * log(2.0 * absf(mean_anomaly) / e + 1.8)
	for i: int in MAX_ITERATIONS:
		var step: float = (e * sinh(anomaly) - anomaly - mean_anomaly) / (e * cosh(anomaly) - 1.0)
		anomaly -= step
		if absf(step) < TOLERANCE * maxf(1.0, absf(anomaly)):
			break
	return anomaly


## A conic as a compact element set, used for bodies and particles that
## ride a fixed orbit around a parent ("on rails" or asleep), laid out as
## [a, e, n, M0, t0, Px, Py, Pz, Qx, Qy, Qz, mu] (Gravity.ELEMENT_SIZE
## numbers). a < 0 marks a hyperbolic orbit. P points to periapsis with
## length |a|; Q points 90° ahead along the motion with length
## |a|·√|1 − e²|. Returns an empty array for a radial (degenerate) orbit.
static func elements_from_state(
	rx: float, ry: float, rz: float, vx: float, vy: float, vz: float, mu: float, t0: float
) -> PackedFloat64Array:
	var r: float = sqrt(rx * rx + ry * ry + rz * rz)
	var v2: float = vx * vx + vy * vy + vz * vz
	var hx: float = ry * vz - rz * vy
	var hy: float = rz * vx - rx * vz
	var hz: float = rx * vy - ry * vx
	var h: float = sqrt(hx * hx + hy * hy + hz * hz)
	if r <= 0.0 or mu <= 0.0 or h <= 1e-9 * r * sqrt(v2 + mu / r):
		return PackedFloat64Array()
	var energy: float = 0.5 * v2 - mu / r
	if absf(energy) < 1e-12 * mu / r:
		energy = -1e-12 * mu / r
	var a: float = -mu / (2.0 * energy)
	var ex: float = (vy * hz - vz * hy) / mu - rx / r
	var ey: float = (vz * hx - vx * hz) / mu - ry / r
	var ez: float = (vx * hy - vy * hx) / mu - rz / r
	var e: float = sqrt(ex * ex + ey * ey + ez * ez)
	if a > 0.0 and e >= 1.0:
		e = 1.0 - 1e-12
	elif a < 0.0 and e <= 1.0:
		e = 1.0 + 1e-12
	var px: float = rx / r
	var py: float = ry / r
	var pz: float = rz / r
	if e > 1e-11:
		px = ex / e
		py = ey / e
		pz = ez / e
	var qx: float = (hy * pz - hz * py) / h
	var qy: float = (hz * px - hx * pz) / h
	var qz: float = (hx * py - hy * px) / h
	var size_p: float = absf(a)
	var size_q: float = absf(a) * sqrt(absf(1.0 - e * e))
	var rp: float = rx * px + ry * py + rz * pz
	var rq: float = rx * qx + ry * qy + rz * qz
	var mean_anomaly: float
	if a > 0.0:
		var anomaly: float = atan2(rq / size_q, rp / a + e)
		mean_anomaly = anomaly - e * sin(anomaly)
	else:
		var anomaly: float = asinh(rq / size_q)
		mean_anomaly = e * sinh(anomaly) - anomaly
	return PackedFloat64Array([
		a, e, sqrt(mu / absf(a * a * a)), mean_anomaly, t0,
		px * size_p, py * size_p, pz * size_p, qx * size_q, qy * size_q, qz * size_q, mu,
	])


## Position and velocity relative to the parent at time t from an element
## set (see elements_from_state), starting at offset in the array.
static func state_from_element_set(elements: PackedFloat64Array, offset: int, t: float) -> PackedFloat64Array:
	var a: float = elements[offset]
	var e: float = elements[offset + 1]
	var n: float = elements[offset + 2]
	var mean_anomaly: float = elements[offset + 3] + n * (t - elements[offset + 4])
	var cp: float
	var cq: float
	var rate_p: float
	var rate_q: float
	if a > 0.0:
		var anomaly: float = eccentric_anomaly(mean_anomaly, e)
		var c: float = cos(anomaly)
		var s: float = sin(anomaly)
		var rate: float = n / (1.0 - e * c)
		cp = c - e
		cq = s
		rate_p = -s * rate
		rate_q = c * rate
	else:
		var anomaly: float = hyperbolic_anomaly(mean_anomaly, e)
		var ch: float = cosh(anomaly)
		var sh: float = sinh(anomaly)
		var rate: float = n / (e * ch - 1.0)
		cp = e - ch
		cq = sh
		rate_p = -sh * rate
		rate_q = ch * rate
	var out: PackedFloat64Array = PackedFloat64Array()
	out.resize(6)
	for k: int in 3:
		var p: float = elements[offset + 5 + k]
		var q: float = elements[offset + 8 + k]
		out[k] = cp * p + cq * q
		out[k + 3] = rate_p * p + rate_q * q
	return out
