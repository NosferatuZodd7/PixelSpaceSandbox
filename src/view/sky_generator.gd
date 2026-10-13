class_name SkyGenerator
extends RefCounted
## Builds the deep-space backdrop from a seed: nebula bands drawn with ordered
## (Bayer) dithering and a field of pixel stars. Pure functions with no nodes,
## safe to call from a worker thread, and deterministic: the same seed and size
## always give the same sky.

## 4×4 Bayer matrix: the threshold order for ordered dithering.
const BAYER_4X4: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

## Palette ramps, darkest first. The first entry of each nebula ramp is the
## empty sky, so a band fades into the background.
const BACKGROUND_RAMP: Array[StringName] = [&"void", &"space_deep", &"space_navy"]
const NEBULA_RAMP: Array[StringName] = [
	&"space_deep", &"nebula_1", &"nebula_2", &"nebula_3", &"nebula_4", &"nebula_5"
]
const NEBULA_BLUE_RAMP: Array[StringName] = [&"space_deep", &"nebula_blue_1", &"nebula_blue_2"]

## Star ramps: [dim, normal, bright]. A star twinkles by moving along its ramp.
const FAINT_STAR_RAMP: Array[StringName] = [&"space_indigo_light", &"star_dim", &"star_mid"]
const WHITE_STAR_RAMP: Array[StringName] = [&"star_dim", &"star_mid", &"white"]
## Tints for the brighter stars, weighted towards blue-white and yellow.
const STAR_TINTS: Array[StringName] = [
	&"star_b", &"star_a", &"star_a", &"star_f", &"star_g", &"star_g", &"star_k", &"star_m", &"star_o"
]


## A generated star field, as parallel arrays (one entry per star).
class StarField:
	var positions: PackedVector2Array = []
	## Three palette colours per star (dim, normal, bright), flattened.
	var ramps: PackedColorArray = []
	## Resting brightness: index into the star's ramp.
	var levels: PackedByteArray = []
	## Whether the star is drawn as a small cross instead of a single pixel.
	var crosses: PackedByteArray = []
	var phases: PackedFloat32Array = []
	var speeds: PackedFloat32Array = []

	func size() -> int:
		return positions.size()

	## The star's colour at a moment in time (seconds). Stars sparkle briefly
	## and dim briefly, each on its own rhythm.
	func color_at(index: int, time: float) -> Color:
		var wave: float = sin(time * speeds[index] + phases[index])
		var level: int = levels[index]
		if wave > 0.93:
			level += 1
		elif wave < -0.96:
			level -= 1
		return ramps[index * 3 + clampi(level, 0, 2)]


## Resolves a ramp of palette names to colours. Call on the main thread before
## handing ramps to a worker thread.
static func resolve_ramp(names: Array[StringName]) -> PackedColorArray:
	var colors: PackedColorArray = []
	for color_name: StringName in names:
		colors.append(Palette.color(color_name))
	return colors


## The ramps the nebula needs, resolved from the palette.
static func default_ramps() -> Dictionary:
	return {
		"background": resolve_ramp(BACKGROUND_RAMP),
		"nebula": resolve_ramp(NEBULA_RAMP),
		"nebula_blue": resolve_ramp(NEBULA_BLUE_RAMP),
	}


## Renders the nebula backdrop as an RGB8 image of the given size. strength
## scales how bright the nebulae get (1 on the title, lower behind the game).
static func nebula_image(sky_seed: int, size: Vector2i, ramps: Dictionary, strength: float = 1.0) -> Image:
	var background: PackedColorArray = ramps["background"]
	var purple: PackedColorArray = ramps["nebula"]
	var blue: PackedColorArray = ramps["nebula_blue"]
	var width: int = size.x
	var height: int = size.y

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = sky_seed

	# Cloud detail and a slow "warp" that bends the bands.
	var detail: PackedByteArray = _noise_bytes(sky_seed, size, 1.0 / 70.0, 5)
	var warp: PackedByteArray = _noise_bytes(sky_seed + 7919, size, 1.0 / 220.0, 2)

	# Main purple band: a wide diagonal through the middle of the view.
	var angle1: float = rng.randf_range(-0.65, -0.25)
	var center1: Vector2 = Vector2(width * rng.randf_range(0.35, 0.65), height * rng.randf_range(0.4, 0.6))
	var normal1: Vector2 = Vector2(-sin(angle1), cos(angle1))
	var inv_width1_sq: float = 1.0 / pow(height * rng.randf_range(0.2, 0.28), 2.0)
	# Secondary blue band: narrower and fainter, crossing at another angle.
	var angle2: float = angle1 + rng.randf_range(0.6, 1.1) * (1.0 if rng.randf() < 0.5 else -1.0)
	var center2: Vector2 = Vector2(width * rng.randf_range(0.2, 0.8), height * rng.randf_range(0.3, 0.7))
	var normal2: Vector2 = Vector2(-sin(angle2), cos(angle2))
	var inv_width2_sq: float = 1.0 / pow(height * rng.randf_range(0.1, 0.15), 2.0)
	var warp_amount: float = height * 0.35

	var purple_top: float = purple.size() - 1
	var blue_top: float = blue.size() - 1
	var background_top: float = background.size() - 1

	var pixels: PackedByteArray = PackedByteArray()
	pixels.resize(width * height * 3)
	var out: int = 0
	for y: int in height:
		var bayer_row: int = (y & 3) * 4
		var gradient: float = float(y) / float(height)
		for x: int in width:
			var i: int = y * width + x
			var threshold: float = (BAYER_4X4[bayer_row + (x & 3)] + 0.5) / 16.0
			var cloud: float = detail[i] / 255.0
			var bend: float = (warp[i] / 255.0 - 0.5) * warp_amount

			var d1: float = (x - center1.x) * normal1.x + (y - center1.y) * normal1.y + bend
			var v1: float = clampf((exp(-d1 * d1 * inv_width1_sq) * (0.1 + 1.15 * cloud) - 0.12) * strength, 0.0, 1.0)
			var d2: float = (x - center2.x) * normal2.x + (y - center2.y) * normal2.y - bend * 0.6
			var v2: float = clampf((exp(-d2 * d2 * inv_width2_sq) * (0.2 + 0.9 * cloud) - 0.2) * strength, 0.0, 1.0)

			var c: Color
			var level: int = _dither(v1 * purple_top, threshold)
			if level > 0:
				c = purple[level]
			else:
				level = _dither(v2 * blue_top, threshold)
				if level > 0:
					c = blue[level]
				else:
					var haze: float = clampf(0.55 + 0.35 * gradient + 0.25 * (cloud - 0.5), 0.0, 1.0)
					c = background[_dither(haze * background_top, threshold)]
			pixels[out] = c.r8
			pixels[out + 1] = c.g8
			pixels[out + 2] = c.b8
			out += 3
	return Image.create_from_data(width, height, false, Image.FORMAT_RGB8, pixels)


## Scatters pixel stars over the given area.
static func star_field(sky_seed: int, size: Vector2i, count: int) -> StarField:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = sky_seed ^ 0x5eed5
	var faint: PackedColorArray = resolve_ramp(FAINT_STAR_RAMP)
	var white: PackedColorArray = resolve_ramp(WHITE_STAR_RAMP)
	var stars: StarField = StarField.new()
	for i: int in count:
		stars.positions.append(Vector2(rng.randi_range(1, size.x - 2), rng.randi_range(1, size.y - 2)))
		var roll: float = rng.randf()
		var ramp: PackedColorArray
		var level: int = 1
		var cross: bool = false
		if roll < 0.62:
			ramp = faint
			level = rng.randi_range(0, 1)
		elif roll < 0.9:
			ramp = white
		else:
			var tint: StringName = STAR_TINTS[rng.randi_range(0, STAR_TINTS.size() - 1)]
			ramp = PackedColorArray([Palette.color(&"star_mid"), Palette.color(tint), Palette.color(&"white")])
			cross = roll > 0.975
		stars.ramps.append_array(ramp)
		stars.levels.append(level)
		stars.crosses.append(1 if cross else 0)
		stars.phases.append(rng.randf_range(0.0, TAU))
		stars.speeds.append(rng.randf_range(0.6, 2.4))
	return stars


## Picks the ramp step for a fractional level using a dither threshold.
static func _dither(level: float, threshold: float) -> int:
	var base: int = int(level)
	return base + 1 if level - base > threshold else base


static func _noise_bytes(noise_seed: int, size: Vector2i, frequency: float, octaves: int) -> PackedByteArray:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.frequency = frequency
	var image: Image = noise.get_image(size.x, size.y)
	image.convert(Image.FORMAT_L8)
	return image.get_data()
