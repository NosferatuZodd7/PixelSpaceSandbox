extends TestCase
## The sky is deterministic and drawn only with palette colours.

const SIZE: Vector2i = Vector2i(160, 90)


func _nebula(sky_seed: int) -> Image:
	return SkyGenerator.nebula_image(sky_seed, SIZE, SkyGenerator.default_ramps())


func _palette_colours() -> Dictionary[Color, bool]:
	var colours: Dictionary[Color, bool] = {}
	for id: StringName in Palette.ids():
		colours[Palette.color(id)] = true
	return colours


func test_same_seed_gives_the_same_nebula() -> void:
	assert_eq(_nebula(42).get_data(), _nebula(42).get_data())


func test_different_seeds_give_different_nebulae() -> void:
	assert_ne(_nebula(42).get_data(), _nebula(43).get_data())


func test_nebula_has_the_requested_size() -> void:
	var image: Image = _nebula(1)
	assert_eq(image.get_size(), SIZE)
	assert_eq(image.get_format(), Image.FORMAT_RGB8)


func test_nebula_uses_only_palette_colours() -> void:
	var allowed: Dictionary[Color, bool] = _palette_colours()
	var image: Image = _nebula(7)
	var bad: int = 0
	for y: int in SIZE.y:
		for x: int in SIZE.x:
			if not allowed.has(image.get_pixel(x, y)):
				bad += 1
	assert_eq(bad, 0, "pixels outside the palette")


func test_nebula_is_not_empty_sky() -> void:
	var image: Image = _nebula(7)
	var background: Dictionary[Color, bool] = {}
	for c: Color in SkyGenerator.resolve_ramp(SkyGenerator.BACKGROUND_RAMP):
		background[c] = true
	var nebula_pixels: int = 0
	for y: int in SIZE.y:
		for x: int in SIZE.x:
			if not background.has(image.get_pixel(x, y)):
				nebula_pixels += 1
	var share: float = nebula_pixels / float(SIZE.x * SIZE.y)
	assert_true(share > 0.05 and share < 0.8, "nebula covers %d%% of the sky" % roundi(share * 100.0))


## No regular grid of dots: the clouds are smooth bands of colour, so a
## pixel unlike all four of its neighbours (a lone dot) is rare.
func test_nebula_has_no_dot_pattern() -> void:
	for sky_seed: int in [7, 2026]:
		var image: Image = SkyGenerator.nebula_image(sky_seed, SIZE, SkyGenerator.default_ramps(), 0.45)
		var dots: int = 0
		for y: int in range(1, SIZE.y - 1):
			for x: int in range(1, SIZE.x - 1):
				var c: Color = image.get_pixel(x, y)
				if c != image.get_pixel(x - 1, y) and c != image.get_pixel(x + 1, y) \
						and c != image.get_pixel(x, y - 1) and c != image.get_pixel(x, y + 1):
					dots += 1
		var share: float = dots / float(SIZE.x * SIZE.y)
		assert_true(share < 0.005, "seed %d: %.1f%% of the pixels are lone dots" % [sky_seed, share * 100.0])


func test_star_field_is_deterministic_and_inside_the_view() -> void:
	var a: SkyGenerator.StarField = SkyGenerator.star_field(5, SIZE, 100)
	var b: SkyGenerator.StarField = SkyGenerator.star_field(5, SIZE, 100)
	assert_eq(a.size(), 100)
	assert_eq(a.positions, b.positions)
	assert_eq(a.ramps, b.ramps)
	var bounds: Rect2 = Rect2(Vector2.ONE, Vector2(SIZE) - Vector2(2, 2))
	for p: Vector2 in a.positions:
		assert_true(bounds.has_point(p), "star at %s inside the view" % p)
		assert_eq(p, p.floor(), "stars sit on whole pixels")


func test_twinkling_stays_in_the_palette() -> void:
	var allowed: Dictionary[Color, bool] = _palette_colours()
	var stars: SkyGenerator.StarField = SkyGenerator.star_field(9, SIZE, 60)
	for i: int in stars.size():
		for step: int in 40:
			var c: Color = stars.color_at(i, step * 0.37)
			assert_true(allowed.has(c), "star %d colour %s" % [i, c.to_html(false)])
