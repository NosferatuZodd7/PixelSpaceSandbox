extends TestCase
## The god powers come from data/powers.json: each has a tab, an icon, a
## name and a hint, and a power that places a body describes that body with
## values typical for its kind.

const SOLAR_SYSTEM: String = "res://data/presets/solar_system.json"
const TABS_PATH: String = "res://data/power_tabs.json"


static func _system() -> StarSystem:
	return (PresetLoader.load_file(SOLAR_SYSTEM) as Dictionary)["system"]


static func _power(id: String) -> Dictionary:
	for power: Dictionary in (PowerCatalog.load_file() as Dictionary)["powers"]:
		if power["id"] == id:
			return power
	return {}


func test_every_power_is_complete() -> void:
	var loaded: Dictionary = PowerCatalog.load_file()
	var errors: PackedStringArray = loaded["errors"]
	assert_true(errors.is_empty(), "; ".join(errors))
	var powers: Array[Dictionary] = loaded["powers"]
	assert_eq(powers.filter(func(power: Dictionary) -> bool: return power["tab"] == "cosmos").size(), 11, "the Cosmos powers")
	assert_eq(powers.filter(func(power: Dictionary) -> bool: return power["tab"] == "tools").size(), 11, "and the tools")
	var tab_ids: PackedStringArray = []
	for tab: Variant in (JSON.parse_string(FileAccess.get_file_as_string(TABS_PATH)) as Dictionary)["tabs"]:
		tab_ids.append(str((tab as Dictionary)["id"]))
	TranslationServer.set_locale("en")
	for power: Dictionary in powers:
		var id: String = power["id"]
		assert_true(tab_ids.has(str(power["tab"])), "%s: its tab exists" % id)
		assert_true(PixelIcons.texture(StringName(str(power["icon"]))) != null, "%s: its icon exists" % id)
		for key: String in ["name_key", "hint_key"]:
			assert_ne(tr(str(power[key])), str(power[key]), "%s: %s is translated" % [id, key])
		if power["action"] == "place":
			var body: CelestialBody = PowerCatalog.make_body(power, _system())
			assert_ne(tr(body.name_key), body.name_key, "%s: the body's name is translated" % id)


func test_a_sun_like_star_is_like_the_sun() -> void:
	var star: CelestialBody = PowerCatalog.make_body(_power("sun_like_star"), _system())
	assert_eq(star.kind, CelestialBody.Kind.STAR)
	assert_eq(star.mass, 1.0, "one solar mass")
	assert_almost_eq(star.radius, Units.au_from_km(695700.0), 1e-15)
	assert_eq(star.luminosity, 1.0)
	assert_eq(star.temperature, 5772.0)
	assert_eq(star.look, &"sun")
	assert_eq(star.parent, -1, "placed bodies have no preset orbit")
	assert_eq(star.orbit, null)


func test_planets_and_moons_are_measured_in_earths() -> void:
	var planet: CelestialBody = PowerCatalog.make_body(_power("rocky_planet"), _system())
	assert_eq(planet.kind, CelestialBody.Kind.PLANET)
	assert_almost_eq(planet.mass, Units.solar_masses_from_kg(Units.EARTH_MASS_KG), 1e-15, "one Earth mass")
	assert_eq(planet.luminosity, 0.0, "planets do not shine")
	var moon: CelestialBody = PowerCatalog.make_body(_power("moon"), _system())
	assert_eq(moon.kind, CelestialBody.Kind.MOON)
	assert_almost_eq(moon.mass, 0.0123 * planet.mass, 1e-15)


func test_a_black_hole_is_massive_and_dark() -> void:
	var hole: CelestialBody = PowerCatalog.make_body(_power("black_hole"), _system())
	assert_eq(hole.kind, CelestialBody.Kind.BLACK_HOLE)
	assert_eq(hole.mass, 10.0)
	assert_eq(hole.luminosity, 0.0)
	assert_false(hole.is_star(), "not a star: it gives no light")


func test_placed_bodies_are_numbered_by_name() -> void:
	var system: StarSystem = _system()
	var first: CelestialBody = PowerCatalog.make_body(_power("sun_like_star"), system)
	system.add(first)
	var second: CelestialBody = PowerCatalog.make_body(_power("red_dwarf"), system)
	system.add(second)
	var planet: CelestialBody = PowerCatalog.make_body(_power("gas_giant"), system)
	system.add(planet)
	assert_eq(first.name_number, 1, "Star 1")
	assert_eq(second.name_number, 2, "stars share their numbering: Star 2")
	assert_eq(planet.name_number, 1, "Planet 1")
	var ids: Array[StringName] = [first.id, second.id, planet.id]
	for id: StringName in ids:
		assert_true(String(id).is_valid_ascii_identifier(), "%s is a valid id" % id)
		assert_eq(ids.count(id), 1, "%s is unique" % id)
	assert_eq(system.index_of(first.id), system.size() - 3, "found by its id")


func test_bad_powers_are_reported() -> void:
	var loaded: Dictionary = PowerCatalog.parse({"powers": [
		{"id": "boom", "tab": "cosmos", "action": "explode", "icon": "power_star", "name_key": "A", "hint_key": "B"},
		{"id": "empty", "tab": "cosmos", "action": "place", "icon": "power_star", "name_key": "A", "hint_key": "B"},
		{"id": "comet", "tab": "cosmos", "action": "place", "icon": "power_star", "name_key": "A", "hint_key": "B",
			"body": {"kind": "comet", "mass_suns": 1.0, "radius_km": 10, "name_key": "C"}},
		{"id": "fine", "tab": "cosmos", "action": "delete", "icon": "power_delete", "name_key": "A", "hint_key": "B"},
		{"id": "layer", "tab": "tools", "action": "overlay", "icon": "tool_hz", "name_key": "A", "hint_key": "B"},
	]})
	var errors: PackedStringArray = loaded["errors"]
	assert_eq(errors.size(), 4, "; ".join(errors))
	assert_eq((loaded["powers"] as Array).size(), 1, "only the good power is kept")
	assert_eq(PowerCatalog.parse(42)["errors"].size(), 1, "not a catalog at all")
