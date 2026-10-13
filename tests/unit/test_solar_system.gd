extends TestCase
## The Solar System preset matches its sources, and puts the planets and
## the Moon where they really were on known dates.

const PRESET: String = "res://data/presets/solar_system.json"

var _system: StarSystem


func before_each() -> void:
	var loaded: Dictionary = PresetLoader.load_file(PRESET)
	var errors: PackedStringArray = loaded["errors"]
	assert_true(errors.is_empty(), "preset errors: %s" % "; ".join(errors))
	_system = loaded["system"]


func _at(iso_utc: String) -> float:
	return Units.years_from_unix(Time.get_unix_time_from_datetime_string(iso_utc))


func _longitude(index: int) -> float:
	return rad_to_deg(atan2(_system.y(index), _system.x(index)))


func _angle_between(ax: float, ay: float, az: float, bx: float, by: float, bz: float) -> float:
	var dot: float = ax * bx + ay * by + az * bz
	var la: float = sqrt(ax * ax + ay * ay + az * az)
	var lb: float = sqrt(bx * bx + by * by + bz * bz)
	return rad_to_deg(acos(clampf(dot / (la * lb), -1.0, 1.0)))


## Angle Sun–Earth–Moon as seen from the Earth, in degrees.
func _moon_elongation() -> float:
	var earth: int = _system.index_of(&"earth")
	var moon: int = _system.index_of(&"moon")
	return _angle_between(
		-_system.x(earth), -_system.y(earth), -_system.z(earth),
		_system.x(moon) - _system.x(earth), _system.y(moon) - _system.y(earth), _system.z(moon) - _system.z(earth)
	)


func test_bodies_are_all_there() -> void:
	var counts: Dictionary[CelestialBody.Kind, int] = {}
	for b: CelestialBody in _system.bodies:
		counts[b.kind] = counts.get(b.kind, 0) + 1
	assert_eq(counts.get(CelestialBody.Kind.STAR, 0), 1, "one star")
	assert_eq(counts.get(CelestialBody.Kind.PLANET, 0), 8, "eight planets")
	assert_eq(counts.get(CelestialBody.Kind.DWARF_PLANET, 0), 3, "Ceres, Pluto, Eris")
	assert_true(counts.get(CelestialBody.Kind.MOON, 0) >= 20, "major moons")


func test_values_match_the_sources() -> void:
	# JPL Approximate Positions of the Planets, Table 1 (1800–2050).
	var earth: KeplerOrbit = _system.body(_system.index_of(&"earth")).orbit as KeplerOrbit
	assert_almost_eq(earth.a, 1.00000261, 1e-12, "Earth a")
	assert_almost_eq(earth.mean_longitude_deg, 100.46457166, 1e-9, "Earth L")
	assert_almost_eq(earth.mean_motion_deg_per_century, 35999.37244981, 1e-6, "Earth L rate")
	var jupiter: KeplerOrbit = _system.body(_system.index_of(&"jupiter")).orbit as KeplerOrbit
	assert_almost_eq(jupiter.e, 0.04838624, 1e-12, "Jupiter e")
	assert_almost_eq(jupiter.node_deg, 100.47390909, 1e-9, "Jupiter node")
	# NASA fact sheets.
	var expected_masses: Dictionary[StringName, float] = {
		&"earth": 5.9722e24, &"jupiter": 1.89813e27, &"moon": 7.346e22, &"mars": 6.4171e23,
	}
	for id: StringName in expected_masses:
		var mass_kg: float = Units.kg_from_solar_masses(_system.body(_system.index_of(id)).mass)
		assert_almost_eq(mass_kg / expected_masses[id], 1.0, 1e-9, "%s mass" % id)
	assert_almost_eq(Units.km_from_au(_system.body(_system.index_of(&"earth")).radius), 6371.0, 1e-6, "Earth radius")


func test_periods() -> void:
	var expected: Dictionary[StringName, float] = {
		&"earth": 1.0000174, &"mars": 1.8808, &"jupiter": 11.862, &"neptune": 164.79,
	}
	for id: StringName in expected:
		var period: float = _system.body(_system.index_of(id)).orbit.period_years()
		assert_almost_eq(period, expected[id], expected[id] * 2e-4, "%s period" % id)
	assert_almost_eq(_system.body(_system.index_of(&"moon")).orbit.period_years() * Units.YEAR_DAYS, 27.3217, 1e-3, "Moon")


func test_earth_at_j2000() -> void:
	_system.place_on_orbits(0.0)
	var earth: int = _system.index_of(&"earth")
	assert_almost_eq(_longitude(earth), 100.38, 0.05, "heliocentric longitude")
	assert_almost_eq(_system.distance(0, earth), 0.98330, 0.0002, "near perihelion in January")


func test_oppositions_happen_on_the_real_dates() -> void:
	# At opposition the planet and the Earth line up on the same side of the Sun.
	var oppositions: Dictionary[StringName, String] = {
		&"mars": "2025-01-16T02:00:00",
		&"saturn": "2025-09-21T04:00:00",
		&"jupiter": "2026-01-10T08:00:00",
	}
	var earth: int = _system.index_of(&"earth")
	for id: StringName in oppositions:
		_system.place_on_orbits(_at(oppositions[id]))
		var difference: float = absf(wrapf(_longitude(_system.index_of(id)) - _longitude(earth), -180.0, 180.0))
		assert_true(difference < 1.5, "%s opposition: %.2f° apart" % [id, difference])


func test_eclipses_happen_on_the_real_dates() -> void:
	_system.place_on_orbits(_at("2025-09-07T18:12:00"))
	assert_true(_moon_elongation() > 178.5, "total lunar eclipse: Moon opposite the Sun (%.2f°)" % _moon_elongation())
	_system.place_on_orbits(_at("2024-04-08T18:17:00"))
	assert_true(_moon_elongation() < 1.5, "total solar eclipse: Moon in front of the Sun (%.2f°)" % _moon_elongation())


func test_earth_and_moon_orbit_their_shared_centre() -> void:
	var t: float = _at("2026-03-01T00:00:00")
	_system.place_on_orbits(t)
	var earth: int = _system.index_of(&"earth")
	var moon: int = _system.index_of(&"moon")
	var me: float = _system.body(earth).mass
	var mm: float = _system.body(moon).mass
	var barycenter: PackedFloat64Array = _system.body(earth).orbit.state_at(t)
	for k: int in 3:
		var combined: float = (me * _system.positions[earth * 3 + k] + mm * _system.positions[moon * 3 + k]) / (me + mm)
		assert_almost_eq(combined, barycenter[k], 1e-12, "barycentre axis %d" % k)
	for day: int in 30:
		_system.place_on_orbits(t + day / Units.YEAR_DAYS)
		var km: float = Units.km_from_au(_system.distance(earth, moon))
		assert_true(km > 356000.0 and km < 407000.0, "Earth–Moon %d km" % roundi(km))


func test_moons_orbit_in_their_planets_equator() -> void:
	var uranus: int = _system.index_of(&"uranus")
	var titania: CelestialBody = _system.body(_system.index_of(&"titania"))
	var path: PackedFloat64Array = titania.orbit.path(0.0, 64)
	var highest: float = 0.0
	for k: int in 64:
		highest = maxf(highest, absf(path[k * 3 + 2]))
	var a: float = (titania.orbit.elements_at(0.0) as Dictionary)["a"]
	assert_true(highest > 0.95 * a, "Uranus lies on its side, so its moons circle almost upright")
	assert_eq(titania.parent, uranus)
	var io: CelestialBody = _system.body(_system.index_of(&"io"))
	var io_path: PackedFloat64Array = io.orbit.path(0.0, 64)
	var io_a: float = (io.orbit.elements_at(0.0) as Dictionary)["a"]
	var io_high: float = 0.0
	for k: int in 64:
		io_high = maxf(io_high, absf(io_path[k * 3 + 2]))
	assert_true(io_high < 0.06 * io_a, "Jupiter is nearly upright, so Io stays close to the ecliptic")


func test_parents_come_first_and_moons_orbit_planets() -> void:
	for i: int in _system.size():
		var b: CelestialBody = _system.body(i)
		assert_true(b.parent < i, "%s listed after its parent" % b.id)
		if b.kind == CelestialBody.Kind.MOON:
			var host: CelestialBody = _system.body(b.parent)
			assert_true(host.kind == CelestialBody.Kind.PLANET or host.kind == CelestialBody.Kind.DWARF_PLANET, "%s orbits a planet" % b.id)


func test_loader_reports_bad_presets() -> void:
	assert_false((PresetLoader.parse({}) as Dictionary)["errors"].is_empty(), "no bodies")
	var bad: Dictionary = {"bodies": [
		{"id": "sun", "kind": "star", "mass_kg": 2e30, "radius_km": 7e5, "luminosity_lsun": 1.0},
		{"id": "x", "kind": "planet", "parent": "nowhere", "mass_kg": 1e24, "radius_km": 6000},
		{"id": "y", "kind": "planet", "parent": "sun", "mass_kg": 1e24, "radius_km": 6000,
			"orbit": {"model": "elements", "a_au": 1.0, "e": 1.5}},
		{"id": "z", "kind": "comet?", "parent": "sun", "mass_kg": 1e24, "radius_km": 6000,
			"orbit": {"model": "warp"}},
	]}
	var errors: PackedStringArray = (PresetLoader.parse(bad) as Dictionary)["errors"]
	assert_true(errors.size() >= 4, "every problem reported: %s" % "; ".join(errors))
