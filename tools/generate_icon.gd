extends SceneTree
## Generates the game icon (icon.png): a ringed planet lit from a small star,
## drawn pixel by pixel with palette colours and ordered dithering.
##
##   godot --headless --path . --script res://tools/generate_icon.gd

const SIZE: int = 64
const OUT_PATH: String = "res://icon.png"
const BAYER_4X4: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


func _initialize() -> void:
	var image: Image = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	_draw_background(image)
	_draw_ring(image, false)
	_draw_planet(image)
	_draw_ring(image, true)
	_draw_star(image, Vector2i(52, 11))
	var error: Error = image.save_png(OUT_PATH)
	print("Saved %s: %s" % [OUT_PATH, error_string(error)])
	quit(0 if error == OK else 1)


## A rounded square of deep space with a few pixel stars.
func _draw_background(image: Image) -> void:
	var deep: Color = Palette.color(&"space_deep")
	var navy: Color = Palette.color(&"space_navy")
	for y: int in SIZE:
		for x: int in SIZE:
			if _outside_rounded_square(x, y, 6):
				continue
			var level: float = float(y) / SIZE
			image.set_pixel(x, y, navy if level > _threshold(x, y) + 0.35 else deep)
	for p: Vector2i in [Vector2i(9, 9), Vector2i(20, 5), Vector2i(7, 40), Vector2i(57, 30), Vector2i(44, 57), Vector2i(13, 55)]:
		image.set_pixelv(p, Palette.color(&"star_mid"))


## A banded gas giant, lit from the upper right, with a dithered terminator.
func _draw_planet(image: Image) -> void:
	var center: Vector2 = Vector2(31.5, 33.5)
	var radius: float = 16.6
	var light: Vector3 = Vector3(0.65, -0.55, 0.52).normalized()
	var bands: Array[StringName] = [&"sand", &"desert", &"sand", &"dust", &"desert", &"sand"]
	var shadow: Array[StringName] = [&"dust", &"crater", &"void"]
	for y: int in SIZE:
		for x: int in SIZE:
			var offset: Vector2 = (Vector2(x, y) + Vector2(0.5, 0.5) - center) / radius
			if offset.length_squared() > 1.0:
				continue
			var normal: Vector3 = Vector3(offset.x, offset.y, sqrt(1.0 - offset.length_squared()))
			var lit: float = normal.dot(light)
			var band: int = clampi(int((offset.y + 1.0) * 0.5 * bands.size() + offset.x * 0.4), 0, bands.size() - 1)
			var c: Color = Palette.color(bands[band])
			# Darken towards the night side in dithered steps.
			var darkness: float = clampf((0.35 - lit) * 3.0, 0.0, float(shadow.size()))
			var step: int = int(darkness) + (1 if darkness - int(darkness) > _threshold(x, y) else 0)
			if step > 0:
				c = Palette.color(shadow[mini(step, shadow.size()) - 1])
			image.set_pixel(x, y, c)


## The ring as a thin tilted ellipse: the back half goes behind the planet,
## the front half over it.
func _draw_ring(image: Image, front: bool) -> void:
	var center: Vector2 = Vector2(31.5, 33.5)
	var tilt: float = -0.32
	for y: int in SIZE:
		for x: int in SIZE:
			var p: Vector2 = (Vector2(x, y) + Vector2(0.5, 0.5) - center).rotated(-tilt)
			var r: float = Vector2(p.x, p.y * 3.6).length()
			if r < 23.0 or r > 29.0:
				continue
			if (p.y > 0.0) != front:
				continue
			var shade: StringName = &"star_mid" if r < 25.0 or r > 27.0 else &"ice"
			image.set_pixel(x, y, Palette.color(shade))


func _draw_star(image: Image, at: Vector2i) -> void:
	image.set_pixelv(at, Palette.color(&"white"))
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		image.set_pixelv(at + d, Palette.color(&"star_g"))
	for d: Vector2i in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		image.set_pixelv(at + d, Palette.color(&"star_k"))


func _threshold(x: int, y: int) -> float:
	return (BAYER_4X4[(y & 3) * 4 + (x & 3)] + 0.5) / 16.0


func _outside_rounded_square(x: int, y: int, corner: int) -> bool:
	var cx: int = clampi(x, corner, SIZE - 1 - corner)
	var cy: int = clampi(y, corner, SIZE - 1 - corner)
	return Vector2(x - cx, y - cy).length() > corner + 0.25
