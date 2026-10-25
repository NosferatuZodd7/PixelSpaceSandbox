class_name CelestialBody
extends RefCounted
## One star, planet, dwarf planet, moon or black hole: what it is and how
## it moves.
## Units: masses in M☉, distances in AU, time in years.

enum Kind { STAR, PLANET, DWARF_PLANET, MOON, BLACK_HOLE }

var id: StringName = &""
var name_key: String = ""
## For bodies the player adds: the name is name_key with this number
## ("Star 2"); 0 for bodies named by name_key alone.
var name_number: int = 0
var kind: Kind = Kind.PLANET
## Index of the body it orbits in its StarSystem, or -1.
var parent: int = -1
var mass: float = 0.0
var radius: float = 0.0
## Stars: luminosity (L☉) and effective temperature (K).
var luminosity: float = 0.0
var temperature: float = 0.0
## Bond albedo: the share of starlight reflected back to space.
var albedo: float = 0.3
## Sidereal rotation period in hours; negative means retrograde.
var rotation_hours: float = 24.0
var axial_tilt_deg: float = 0.0
## North pole direction (J2000 equatorial), used for moons' and rings' planes.
var pole_ra_deg: float = 0.0
var pole_dec_deg: float = 90.0
## Name of the look in data/body_looks.json (presentation only).
var look: StringName = &""
## Rings: [{"inner": AU, "outer": AU, "color": palette id, "density": 0..1}].
var rings: Array[Dictionary] = []
## How it moves around its parent; null for a body that does not orbit.
var orbit: OrbitModel = null
## A moon massive enough that this body's orbit is really the pair's centre
## of mass (Earth and the Moon, Pluto and Charon). -1 when none.
var barycenter_partner: int = -1
## True when the body's place along its orbit is approximate (no exact
## ephemeris was available for it).
var approximate_phase: bool = false


func is_star() -> bool:
	return kind == Kind.STAR
