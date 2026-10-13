extends TestCase
## Body looks are complete, use only palette colours, and draw the same map
## for the same seed.

const PRESET: String = "res://data/presets/solar_system.json"


func _system() -> StarSystem:
	return (PresetLoader.load_file(PRESET) as Dictionary)["system"]


func test_every_body_has_a_look() -> void:
	var looks: Dictionary = SurfaceMaps.looks()
	for b: CelestialBody in _system().bodies:
		assert_true(looks.has(String(b.look)), "%s uses look '%s'" % [b.id, b.look])


func test_looks_and_rings_name_palette_colours() -> void:
	var looks: Dictionary = SurfaceMaps.looks()
	for look_name: Variant in looks:
		var look: Dictionary = looks[look_name]
		for key: Variant in look:
			var value: Variant = look[key]
			var names: Array = value if value is Array else [value]
			if str(key) in ["colors", "land", "spots", "ice", "clouds", "spot", "cracks"]:
				for color_name: Variant in names:
					assert_true(Palette.has(StringName(str(color_name))), "%s.%s: '%s'" % [look_name, key, color_name])
	for b: CelestialBody in _system().bodies:
		for ring: Dictionary in b.rings:
			assert_true(Palette.has(ring["color"]), "%s ring colour %s" % [b.id, ring["color"]])


func test_maps_are_deterministic_and_use_only_the_palette() -> void:
	var allowed: Dictionary[Color, bool] = {}
	for id: StringName in Palette.ids():
		allowed[Palette.color(id)] = true
	for look_name: Variant in SurfaceMaps.looks():
		var a: Image = SurfaceMaps.generate(StringName(str(look_name)), 42)
		var b: Image = SurfaceMaps.generate(StringName(str(look_name)), 42)
		assert_eq(a.get_data(), b.get_data(), "%s is the same twice" % look_name)
		assert_eq(a.get_size(), Vector2i(SurfaceMaps.WIDTH, SurfaceMaps.HEIGHT))
		var bad: int = 0
		for y: int in a.get_height():
			for x: int in a.get_width():
				var c: Color = a.get_pixel(x, y)
				if not allowed.has(Color(c.r, c.g, c.b, 1.0)):
					bad += 1
		assert_eq(bad, 0, "%s pixels outside the palette" % look_name)
