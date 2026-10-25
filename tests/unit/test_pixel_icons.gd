extends TestCase
## Pixel icons come from data/icons.json: every icon is a square grid of
## palette colours, drawn pixel for pixel.


func test_every_icon_is_a_square_of_palette_colours() -> void:
	var data: Dictionary = PixelIcons.load_data()
	assert_true(PixelIcons.ids().size() > 0, "icons are defined")
	for id: StringName in PixelIcons.ids():
		var errors: PackedStringArray = PixelIcons.check(id)
		assert_true(errors.is_empty(), "%s: %s" % [id, "; ".join(errors)])
	assert_true(data.has("legend"), "a legend maps letters to palette colours")


func test_an_icon_becomes_a_texture_pixel_for_pixel() -> void:
	var texture: Texture2D = PixelIcons.texture(&"pause")
	assert_true(texture != null, "the pause icon exists")
	var image: Image = texture.get_image()
	var rows: PackedStringArray = PixelIcons.rows(&"pause")
	assert_eq(image.get_width(), rows[0].length(), "one texel per character")
	assert_eq(image.get_height(), rows.size())
	var legend: Dictionary = PixelIcons.load_data()["legend"]
	for y: int in rows.size():
		for x: int in rows[y].length():
			var key: String = rows[y][x]
			var expected: Color = Color(0, 0, 0, 0) if key == "." else Palette.color(StringName(legend[key]))
			assert_eq(image.get_pixel(x, y), expected, "pixel %d,%d" % [x, y])


func test_an_unknown_icon_has_no_texture() -> void:
	assert_eq(PixelIcons.texture(&"no_such_icon"), null)
