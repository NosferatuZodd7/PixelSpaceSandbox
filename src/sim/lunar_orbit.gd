class_name LunarOrbit
extends OrbitModel
## The Moon around the Earth, from the low-precision lunar formulae of the
## Astronomical Almanac (about 0.3° in longitude, 0.2° in latitude): good
## enough to put the Moon in its real phase on any date.

const SIDEREAL_MONTH_DAYS: float = 27.321661
const EARTH_EQUATORIAL_RADIUS_KM: float = 6378.14
## General precession in longitude, degrees per century (date → J2000).
const PRECESSION_DEG_PER_CENTURY: float = 1.396971
## Step for the velocity estimate (central difference), in years.
const VELOCITY_STEP: float = 1e-4


func state_at(t: float) -> PackedFloat64Array:
	var p: PackedFloat64Array = _position(t)
	var before: PackedFloat64Array = _position(t - VELOCITY_STEP)
	var after: PackedFloat64Array = _position(t + VELOCITY_STEP)
	var h: float = 2.0 * VELOCITY_STEP
	return PackedFloat64Array([
		p[0], p[1], p[2],
		(after[0] - before[0]) / h, (after[1] - before[1]) / h, (after[2] - before[2]) / h,
	])


func period_years() -> float:
	return SIDEREAL_MONTH_DAYS / Units.YEAR_DAYS


## One month of the real motion (no velocities needed, so three times cheaper).
func path(t: float, count: int) -> PackedFloat64Array:
	var points: PackedFloat64Array = []
	var period: float = period_years()
	for k: int in count:
		points.append_array(_position(t + period * k / count))
	return points


func elements_at(_t: float) -> Dictionary:
	return {"a": Units.au_from_km(384399.0), "e": 0.0549, "i_deg": 5.145}


## Geocentric ecliptic longitude, latitude (degrees, mean equinox of date)
## and distance (km).
static func ecliptic_coordinates(t: float) -> PackedFloat64Array:
	var c: float = t / Units.CENTURY_YEARS
	var longitude: float = (
		218.32 + 481267.881 * c
		+ 6.29 * _sin_deg(135.0 + 477198.87 * c)
		- 1.27 * _sin_deg(259.3 - 413335.36 * c)
		+ 0.66 * _sin_deg(235.7 + 890534.22 * c)
		+ 0.21 * _sin_deg(269.9 + 954397.74 * c)
		- 0.19 * _sin_deg(357.5 + 35999.05 * c)
		- 0.11 * _sin_deg(186.5 + 966404.03 * c)
	)
	var latitude: float = (
		5.13 * _sin_deg(93.3 + 483202.02 * c)
		+ 0.28 * _sin_deg(228.2 + 960400.89 * c)
		- 0.28 * _sin_deg(318.3 + 6003.15 * c)
		- 0.17 * _sin_deg(217.6 - 407332.21 * c)
	)
	var parallax: float = (
		0.9508
		+ 0.0518 * _cos_deg(135.0 + 477198.87 * c)
		+ 0.0095 * _cos_deg(259.3 - 413335.36 * c)
		+ 0.0078 * _cos_deg(235.7 + 890534.22 * c)
		+ 0.0028 * _cos_deg(269.9 + 954397.74 * c)
	)
	var distance_km: float = EARTH_EQUATORIAL_RADIUS_KM / _sin_deg(parallax)
	return PackedFloat64Array([fposmod(longitude, 360.0), latitude, distance_km])


func _position(t: float) -> PackedFloat64Array:
	var coordinates: PackedFloat64Array = ecliptic_coordinates(t)
	var longitude: float = deg_to_rad(coordinates[0] - PRECESSION_DEG_PER_CENTURY * t / Units.CENTURY_YEARS)
	var latitude: float = deg_to_rad(coordinates[1])
	var r: float = Units.au_from_km(coordinates[2])
	return PackedFloat64Array([
		r * cos(latitude) * cos(longitude),
		r * cos(latitude) * sin(longitude),
		r * sin(latitude),
	])


static func _sin_deg(degrees: float) -> float:
	return sin(deg_to_rad(fmod(degrees, 360.0)))


static func _cos_deg(degrees: float) -> float:
	return cos(deg_to_rad(fmod(degrees, 360.0)))
