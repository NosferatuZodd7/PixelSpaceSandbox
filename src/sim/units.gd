class_name Units
extends RefCounted
## Physical constants and unit conversions.
##
## The simulation works in astronomical units (AU), solar masses (M☉) and
## Julian years, counted from J2000.0 (2000-01-01 12:00 TT). Every distance,
## mass and time inside src/sim/ uses these units; conversions to km, kg,
## seconds or dates happen at the edges.

const AU_KM: float = 149597870.7
const DAY_SECONDS: float = 86400.0
const YEAR_DAYS: float = 365.25
const YEAR_SECONDS: float = YEAR_DAYS * DAY_SECONDS
const CENTURY_YEARS: float = 100.0

const SOLAR_MASS_KG: float = 1.98847e30
const EARTH_MASS_KG: float = 5.9722e24
const SOLAR_RADIUS_KM: float = 695700.0
const EARTH_RADIUS_KM: float = 6371.0
const SOLAR_LUMINOSITY_W: float = 3.828e26

## Newton's G in SI units (m³ kg⁻¹ s⁻²).
const G_SI: float = 6.6743e-11
## G in AU³ / (M☉ · yr²): a 1 AU orbit around 1 M☉ takes one year.
const G: float = 4.0 * PI * PI

## Speed of light: 299,792.458 km/s, or about 63,241.077 AU per year.
const C_KM_S: float = 299792.458
const C: float = C_KM_S * YEAR_SECONDS / AU_KM

const J2000_JD: float = 2451545.0
## Unix time of J2000.0 (2000-01-01 12:00 TT = 11:58:55.816 UTC).
const J2000_UNIX: float = 946727935.816
## Obliquity of the ecliptic at J2000.0, in degrees.
const OBLIQUITY_J2000_DEG: float = 23.4392911


static func years_from_unix(unix_seconds: float) -> float:
	return (unix_seconds - J2000_UNIX) / YEAR_SECONDS


static func unix_from_years(years: float) -> float:
	return J2000_UNIX + years * YEAR_SECONDS


static func years_from_julian_date(julian_date: float) -> float:
	return (julian_date - J2000_JD) / YEAR_DAYS


static func julian_date(years: float) -> float:
	return J2000_JD + years * YEAR_DAYS


static func au_from_km(km: float) -> float:
	return km / AU_KM


static func km_from_au(au: float) -> float:
	return au * AU_KM


static func solar_masses_from_kg(kg: float) -> float:
	return kg / SOLAR_MASS_KG


static func kg_from_solar_masses(solar_masses: float) -> float:
	return solar_masses * SOLAR_MASS_KG


## How long light takes to cross a distance in AU, in seconds.
static func light_time_seconds(distance_au: float) -> float:
	return distance_au * AU_KM / C_KM_S
