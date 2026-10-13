class_name Astro
extends RefCounted
## Plain physics formulas used across the game (inspection, habitable zone,
## climate). Inputs in simulation units unless the name says otherwise.

## Stefan–Boltzmann constant (W m⁻² K⁻⁴).
const STEFAN_BOLTZMANN: float = 5.670374419e-8


## Habitable zone around a star of the given luminosity (L☉), in AU:
## inner ≈ √(L/1.1), outer ≈ √(L/0.53).
static func habitable_zone_inner(luminosity: float) -> float:
	return sqrt(luminosity / 1.1)


static func habitable_zone_outer(luminosity: float) -> float:
	return sqrt(luminosity / 0.53)


static func in_habitable_zone(distance_au: float, luminosity: float) -> bool:
	return distance_au >= habitable_zone_inner(luminosity) and distance_au <= habitable_zone_outer(luminosity)


## Surface gravity in m/s².
static func surface_gravity(mass: float, radius: float) -> float:
	var radius_m: float = Units.km_from_au(radius) * 1000.0
	return Units.G_SI * Units.kg_from_solar_masses(mass) / (radius_m * radius_m)


## Escape velocity from the surface in km/s.
static func escape_velocity(mass: float, radius: float) -> float:
	var radius_m: float = Units.km_from_au(radius) * 1000.0
	return sqrt(2.0 * Units.G_SI * Units.kg_from_solar_masses(mass) / radius_m) / 1000.0


## Equilibrium temperature (K) of a fast-rotating body at a distance (AU)
## from a star of the given luminosity (L☉), with a Bond albedo.
static func equilibrium_temperature(luminosity: float, distance_au: float, albedo: float) -> float:
	var flux: float = luminosity * Units.SOLAR_LUMINOSITY_W / (4.0 * PI * pow(Units.km_from_au(distance_au) * 1000.0, 2.0))
	return pow(flux * (1.0 - albedo) / (4.0 * STEFAN_BOLTZMANN), 0.25)
