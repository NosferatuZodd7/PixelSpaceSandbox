class_name PixelIcons
extends RefCounted
## Pixel icons from data/icons.json: each is a square grid of characters,
## '.' transparent and every other character a palette colour named in the
## file's legend. Textures are made once and shared.

const PATH: String = "res://data/icons.json"

static var _data: Dictionary = {}
static var _textures: Dictionary[StringName, Texture2D] = {}


static func load_data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_data = parsed
	return _data


static func ids() -> Array[StringName]:
	var found: Array[StringName] = []
	var icons: Variant = load_data().get("icons", {})
	if icons is Dictionary:
		for id: Variant in icons:
			found.append(StringName(str(id)))
	return found


static func rows(id: StringName) -> PackedStringArray:
	var icons: Variant = load_data().get("icons", {})
	if icons is Dictionary and (icons as Dictionary).get(String(id)) is Array:
		return PackedStringArray((icons as Dictionary)[String(id)])
	return PackedStringArray()


## What is wrong with an icon's definition (empty when nothing is).
static func check(id: StringName) -> PackedStringArray:
	var errors: PackedStringArray = []
	var lines: PackedStringArray = rows(id)
	var legend: Variant = load_data().get("legend", {})
	if lines.is_empty():
		errors.append("no rows")
		return errors
	for line: String in lines:
		if line.length() != lines.size():
			errors.append("row '%s' is not %d characters (icons are square)" % [line, lines.size()])
		for character: String in line:
			if character == ".":
				continue
			if not (legend is Dictionary and (legend as Dictionary).has(character)):
				errors.append("'%s' is not in the legend" % character)
			elif not Palette.has(StringName(str((legend as Dictionary)[character]))):
				errors.append("'%s' names no palette colour" % character)
	return errors


## The icon as a texture, or null when there is no such icon.
static func texture(id: StringName) -> Texture2D:
	if _textures.has(id):
		return _textures[id]
	var lines: PackedStringArray = rows(id)
	if lines.is_empty():
		return null
	var legend: Dictionary = load_data().get("legend", {})
	var image: Image = Image.create_empty(lines[0].length(), lines.size(), false, Image.FORMAT_RGBA8)
	for y: int in lines.size():
		for x: int in lines[y].length():
			var character: String = lines[y][x]
			if character != ".":
				image.set_pixel(x, y, Palette.color(StringName(str(legend.get(character, "")))))
	var made: ImageTexture = ImageTexture.create_from_image(image)
	_textures[id] = made
	return made
