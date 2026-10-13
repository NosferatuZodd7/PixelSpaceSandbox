class_name KeplerOrbit
extends OrbitModel
## An elliptic orbit from classical elements.
##
## The elements may drift slowly and linearly per century (the form of
## JPL's "Approximate Positions of the Planets"), and may be measured in a
## tilted frame, such as a planet's equator for its moons.

## Linear drifts are only valid near the interval they were fitted to.
## Beyond this many centuries from the epoch the orbit's shape stops
## drifting, while the body keeps moving along it.
const DRIFT_LIMIT_CENTURIES: float = 50.0

var a: float = 1.0
var e: float = 0.0
var inclination_deg: float = 0.0
## Mean longitude at the epoch (L = M + ϖ).
var mean_longitude_deg: float = 0.0
## Longitude of periapsis (ϖ = Ω + ω).
var periapsis_longitude_deg: float = 0.0
var node_deg: float = 0.0
## Epoch of the elements, in years since J2000.0.
var epoch: float = 0.0
## How fast the mean longitude grows, in degrees per century.
var mean_motion_deg_per_century: float = 36000.0
var a_rate: float = 0.0
var e_rate: float = 0.0
var inclination_rate: float = 0.0
var periapsis_rate: float = 0.0
var node_rate: float = 0.0
## The frame the elements are measured in: its x, y and z axes in ecliptic
## coordinates (9 numbers). Empty means the ecliptic itself.
var frame: PackedFloat64Array = []


## Elements in the JPL form: mean longitude and longitude of periapsis.
static func from_mean_longitude(
	semi_major: float, ecc: float, incl_deg: float, mean_long_deg: float,
	peri_long_deg: float, asc_node_deg: float, elements_epoch: float, mean_motion: float
) -> KeplerOrbit:
	var orbit: KeplerOrbit = KeplerOrbit.new()
	orbit.a = semi_major
	orbit.e = ecc
	orbit.inclination_deg = incl_deg
	orbit.mean_longitude_deg = mean_long_deg
	orbit.periapsis_longitude_deg = peri_long_deg
	orbit.node_deg = asc_node_deg
	orbit.epoch = elements_epoch
	orbit.mean_motion_deg_per_century = mean_motion
	return orbit


## Classical elements: argument of periapsis and mean anomaly.
static func from_anomaly(
	semi_major: float, ecc: float, incl_deg: float, asc_node_deg: float, arg_peri_deg: float,
	mean_anomaly_deg: float, elements_epoch: float, mean_motion: float
) -> KeplerOrbit:
	var peri_long: float = asc_node_deg + arg_peri_deg
	return from_mean_longitude(
		semi_major, ecc, incl_deg, mean_anomaly_deg + peri_long, peri_long,
		asc_node_deg, elements_epoch, mean_motion
	)


## The frame of a body's equator, from the direction of its north pole
## (right ascension and declination, J2000 equatorial). The x axis points to
## where the equator crosses the ecliptic going north.
static func equator_frame(pole_ra_deg: float, pole_dec_deg: float) -> PackedFloat64Array:
	var ra: float = deg_to_rad(pole_ra_deg)
	var dec: float = deg_to_rad(pole_dec_deg)
	var eps: float = deg_to_rad(Units.OBLIQUITY_J2000_DEG)
	var qx: float = cos(dec) * cos(ra)
	var qy: float = cos(dec) * sin(ra)
	var qz: float = sin(dec)
	# Equatorial to ecliptic: rotate about x by the obliquity.
	var zx: float = qx
	var zy: float = qy * cos(eps) + qz * sin(eps)
	var zz: float = -qy * sin(eps) + qz * cos(eps)
	# x axis: the ascending node of the equator on the ecliptic (ecliptic pole × pole).
	var xx: float = -zy
	var xy: float = zx
	var length: float = sqrt(xx * xx + xy * xy)
	if length < 1e-12:
		xx = 1.0
		xy = 0.0
	else:
		xx /= length
		xy /= length
	# y axis: z × x.
	var yx: float = zy * 0.0 - zz * xy
	var yy: float = zz * xx - zx * 0.0
	var yz: float = zx * xy - zy * xx
	return PackedFloat64Array([xx, xy, 0.0, yx, yy, yz, zx, zy, zz])


func state_at(t: float) -> PackedFloat64Array:
	var centuries: float = (t - epoch) / Units.CENTURY_YEARS
	var drift: float = clampf(centuries, -DRIFT_LIMIT_CENTURIES, DRIFT_LIMIT_CENTURIES)
	var periapsis: float = periapsis_longitude_deg + periapsis_rate * drift
	var node: float = node_deg + node_rate * drift
	var mean_longitude: float = mean_longitude_deg + mean_motion_deg_per_century * centuries
	var state: PackedFloat64Array = Kepler.state_from_elements(
		a + a_rate * drift,
		clampf(e + e_rate * drift, 0.0, 0.99),
		deg_to_rad(inclination_deg + inclination_rate * drift),
		deg_to_rad(node),
		deg_to_rad(periapsis - node),
		deg_to_rad(fmod(mean_longitude - periapsis, 360.0)),
		deg_to_rad(mean_motion_deg_per_century) / Units.CENTURY_YEARS
	)
	return _to_ecliptic(state)


func period_years() -> float:
	return 360.0 * Units.CENTURY_YEARS / absf(mean_motion_deg_per_century)


func elements_at(t: float) -> Dictionary:
	var drift: float = clampf((t - epoch) / Units.CENTURY_YEARS, -DRIFT_LIMIT_CENTURIES, DRIFT_LIMIT_CENTURIES)
	return {
		"a": a + a_rate * drift,
		"e": clampf(e + e_rate * drift, 0.0, 0.99),
		"i_deg": inclination_deg + inclination_rate * drift,
	}


## The ellipse itself, sampled evenly in eccentric anomaly (smooth at any eccentricity).
func path(t: float, count: int) -> PackedFloat64Array:
	var drift: float = clampf((t - epoch) / Units.CENTURY_YEARS, -DRIFT_LIMIT_CENTURIES, DRIFT_LIMIT_CENTURIES)
	var semi_major: float = a + a_rate * drift
	var ecc: float = clampf(e + e_rate * drift, 0.0, 0.99)
	var node: float = node_deg + node_rate * drift
	var periapsis: float = periapsis_longitude_deg + periapsis_rate * drift
	var inclination: float = deg_to_rad(inclination_deg + inclination_rate * drift)
	var root: float = sqrt(1.0 - ecc * ecc)
	var points: PackedFloat64Array = []
	for k: int in count:
		var anomaly: float = TAU * k / count
		var state: PackedFloat64Array = Kepler.rotate_from_orbit_plane(
			semi_major * (cos(anomaly) - ecc), semi_major * root * sin(anomaly), 0.0, 0.0,
			inclination, deg_to_rad(node), deg_to_rad(periapsis - node)
		)
		state = _to_ecliptic(state)
		points.append(state[0])
		points.append(state[1])
		points.append(state[2])
	return points


func _to_ecliptic(state: PackedFloat64Array) -> PackedFloat64Array:
	if frame.is_empty():
		return state
	var f: PackedFloat64Array = frame
	var out: PackedFloat64Array = PackedFloat64Array()
	out.resize(6)
	for offset: int in [0, 3]:
		var x: float = state[offset]
		var y: float = state[offset + 1]
		var z: float = state[offset + 2]
		out[offset] = f[0] * x + f[3] * y + f[6] * z
		out[offset + 1] = f[1] * x + f[4] * y + f[7] * z
		out[offset + 2] = f[2] * x + f[5] * y + f[8] * z
	return out
