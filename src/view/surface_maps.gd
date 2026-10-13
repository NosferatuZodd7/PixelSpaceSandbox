class_name SurfaceMaps
extends RefCounted
## Draws a body's surface as a small wrap-around map (equirectangular: x is
## longitude, y is latitude), using only palette colours, from a look in
## data/body_looks.json. The same seed always draws the same map.
##
## Milestone 5 replaces these with real planet maps (terrain, climate, life);
## until then they give every world its own recognisable face.

const LOOKS_PATH: String = "res://data/body_looks.json"
const WIDTH: int = 64
const HEIGHT: int = 32
const BAYER_4X4: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

static var _looks: Dictionary = {}


static func looks() -> Dictionary:
	if _looks.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOOKS_PATH))
		if data is Dictionary and (data as Dictionary).get("looks") is Dictionary:
			_looks = (data as Dictionary)["looks"]
	return _looks


## The map for a look (falls back to a plain rocky look if unknown).
static func generate(look_name: StringName, map_seed: int) -> Image:
	var look: Dictionary = looks().get(String(look_name), {"style": "rocky", "colors": ["rock", "regolith"]})
	var colors: PackedColorArray = _palette(look.get("colors", ["rock"]))
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = map_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.frequency = 1.6
	var detail: FastNoiseLite = FastNoiseLite.new()
	detail.seed = map_seed + 101
	detail.frequency = 4.0
	var image: Image = Image.create_empty(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	var style: String = str(look.get("style", "rocky"))
	for y: int in HEIGHT:
		var latitude: float = (float(y) + 0.5) / HEIGHT * 2.0 - 1.0
		for x: int in WIDTH:
			var angle: float = TAU * (float(x) + 0.5) / WIDTH
			# Sample the noise on a cylinder so the map wraps around seamlessly.
			var px: float = cos(angle)
			var py: float = sin(angle)
			var n: float = noise.get_noise_3d(px, py, latitude * 1.5) * 0.5 + 0.5
			var threshold: float = (BAYER_4X4[(y & 3) * 4 + (x & 3)] + 0.5) / 16.0
			var c: Color
			match style:
				"star":
					c = _ramp(colors, 0.25 + 0.6 * n, threshold)
				"banded":
					c = _banded(look, colors, latitude, angle, n, threshold)
				"clouds":
					var swirl: float = latitude * 2.5 + (n - 0.5) * 1.6
					c = _ramp(colors, 0.5 + 0.5 * sin(swirl * PI), threshold)
				"terran":
					c = _terran(look, colors, latitude, n, detail.get_noise_3d(px * 2.0, py * 2.0, latitude * 3.0), threshold)
				"volcanic":
					c = _ramp(colors, n, threshold)
					var spot: float = detail.get_noise_3d(px * 1.5, py * 1.5, latitude * 2.0)
					var spots: PackedColorArray = _palette(look.get("spots", ["lava"]))
					if spot > 0.45:
						c = spots[0]
					elif spot > 0.38:
						c = spots[spots.size() - 1]
				"icy":
					c = _ramp(colors, 0.3 + 0.7 * n, threshold)
					var crack: float = absf(detail.get_noise_3d(px * 3.0, py * 3.0, latitude * 4.0))
					if crack < 0.04:
						c = Palette.color(StringName(str(look.get("cracks", "dust"))))
				"two_tone":
					c = colors[0] if (cos(angle) + (n - 0.5) * 0.8) > 0.0 else colors[colors.size() - 1]
				_:
					c = _rocky(look, colors, latitude, n, detail.get_noise_3d(px * 2.5, py * 2.5, latitude * 3.0), threshold)
			image.set_pixel(x, y, c)
	return image


static func _rocky(look: Dictionary, colors: PackedColorArray, latitude: float, n: float, d: float, threshold: float) -> Color:
	var c: Color = _ramp(colors, n, threshold)
	var craters: float = float(look.get("craters", 0.0))
	if craters > 0.0 and d > 1.0 - craters * 0.55:
		c = colors[0]
	if look.has("ice") and absf(latitude) > 0.82 - n * 0.1:
		c = Palette.color(StringName(str(look["ice"])))
	return c


static func _banded(look: Dictionary, colors: PackedColorArray, latitude: float, angle: float, n: float, threshold: float) -> Color:
	var bands: float = float(look.get("bands", 5))
	var wave: float = latitude * bands + (n - 0.5) * 0.9
	var c: Color = _ramp(colors, 0.5 + 0.5 * sin(wave * PI), threshold)
	if look.has("spot"):
		# One great storm in the southern hemisphere.
		var dx: float = wrapf(angle - 2.0, -PI, PI) / 0.45
		var dy: float = (latitude - 0.35) / 0.12
		if dx * dx + dy * dy < 1.0:
			c = Palette.color(StringName(str(look["spot"])))
	return c


static func _terran(look: Dictionary, ocean: PackedColorArray, latitude: float, n: float, clouds: float, threshold: float) -> Color:
	var land: PackedColorArray = _palette(look.get("land", ["grass"]))
	var share: float = float(look.get("land_share", 0.3))
	var polar: float = absf(latitude)
	if polar > 0.84:
		return Palette.color(StringName(str(look.get("ice", "snow"))))
	if clouds > 0.42:
		return Palette.color(StringName(str(look.get("clouds", "white"))))
	if n < 1.0 - share:
		return ocean[0] if n < 0.5 else ocean[ocean.size() - 1]
	# Deserts near the tropics, forests and grass in between, tundra near the poles.
	var band: float = clampf(polar * 1.25 + (n - 0.5) * 0.5, 0.0, 0.999)
	var index: int = int(band * land.size())
	if polar < 0.18:
		index = 1
	return land[clampi(index, 0, land.size() - 1)]


static func _ramp(colors: PackedColorArray, value: float, threshold: float) -> Color:
	var level: float = clampf(value, 0.0, 0.999) * (colors.size() - 1)
	var base: int = int(level)
	var index: int = base + 1 if level - base > threshold else base
	return colors[clampi(index, 0, colors.size() - 1)]


static func _palette(names: Variant) -> PackedColorArray:
	var colors: PackedColorArray = []
	if names is Array:
		for color_name: Variant in names:
			colors.append(Palette.color(StringName(str(color_name))))
	if colors.is_empty():
		colors.append(Palette.color(&"rock"))
	return colors
