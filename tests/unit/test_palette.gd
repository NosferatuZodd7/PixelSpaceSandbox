extends TestCase
## The shared palette is valid, small, and the only source of colours.

const SOURCE_DIR: String = "res://src"


func before_each() -> void:
	Palette.load_file()


func test_palette_file_loads() -> void:
	assert_eq(Palette.load_file(), OK)


func test_palette_is_limited() -> void:
	var count: int = Palette.ids().size()
	assert_true(count >= 32 and count <= 64, "between 32 and 64 colours, has %d" % count)


func test_colours_are_distinct() -> void:
	var seen: Dictionary[String, StringName] = {}
	for id: StringName in Palette.ids():
		var hex: String = Palette.color(id).to_html(false)
		assert_false(seen.has(hex), "'%s' repeats the colour of '%s'" % [id, seen.get(hex, "")])
		seen[hex] = id


func test_aliases_resolve_to_palette_colours() -> void:
	var aliases: Dictionary[StringName, StringName] = Palette.aliases()
	assert_true(aliases.has(&"ui_text"), "ui_text alias")
	for alias: StringName in aliases:
		assert_eq(Palette.color(alias), Palette.color(aliases[alias]), String(alias))


func test_nearest_id_finds_exact_colours() -> void:
	for id: StringName in Palette.ids():
		assert_eq(Palette.nearest_id(Palette.color(id)), id)


func test_parse_rejects_bad_data() -> void:
	assert_false(_errors(42).is_empty(), "root not an object")
	assert_false(_errors({"colors": []}).is_empty(), "no colours")
	assert_false(_errors({"colors": [{"id": "a", "hex": "#zzzzzz"}]}).is_empty(), "bad hex")
	assert_false(_errors({"colors": [{"id": "a", "hex": "#fff"}]}).is_empty(), "short hex")
	assert_false(_errors({"colors": [{"id": "bad id", "hex": "#ffffff"}]}).is_empty(), "bad id")
	var duplicate: Dictionary = {"colors": [{"id": "a", "hex": "#ffffff"}, {"id": "a", "hex": "#000000"}]}
	assert_false(_errors(duplicate).is_empty(), "duplicate id")
	var one: Array = [{"id": "a", "hex": "#ffffff"}]
	assert_false(_errors({"colors": one, "aliases": {"b": "missing"}}).is_empty(), "alias to unknown")
	assert_false(_errors({"colors": one, "aliases": {"a": "a"}}).is_empty(), "alias hides an id")
	assert_true(_errors({"colors": one, "aliases": {"b": "a"}}).is_empty(), "valid data")


func test_every_named_colour_in_the_code_exists() -> void:
	var name_pattern: RegEx = RegEx.create_from_string("&\"([a-z0-9_]+)\"")
	var call_pattern: RegEx = RegEx.create_from_string("Palette\\.color\\(&\"([a-z0-9_]+)\"\\)")
	for path: String in _scripts(SOURCE_DIR):
		var text: String = FileAccess.get_file_as_string(path)
		for found: RegExMatch in call_pattern.search_all(text):
			assert_true(Palette.has(StringName(found.get_string(1))), "%s uses '%s'" % [path, found.get_string(1)])
		# Palette ramps declared as constants (…_RAMP / …_TINTS).
		for line: String in text.split("\n"):
			if line.begins_with("const ") and (line.contains("_RAMP") or line.contains("_TINTS")):
				for found: RegExMatch in name_pattern.search_all(line):
					assert_true(Palette.has(StringName(found.get_string(1))), "%s ramp uses '%s'" % [path, found.get_string(1)])


func test_no_hard_coded_colours_outside_the_palette() -> void:
	var forbidden: RegEx = RegEx.create_from_string("Color\\(|Color8\\(|Color\\.html\\(|Color\\.from_|\"#[0-9a-fA-F]{6}\"|Color\\.[A-Z_]{3,}")
	for path: String in _scripts(SOURCE_DIR):
		if path.ends_with("/palette.gd"):
			continue
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for number: int in lines.size():
			var found: RegExMatch = forbidden.search(lines[number])
			if found != null:
				fail("%s:%d hard-codes a colour: %s" % [path, number + 1, lines[number].strip_edges()])


func _errors(data: Variant) -> PackedStringArray:
	return Palette.parse(data)["errors"]


func _scripts(directory: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for file: String in DirAccess.get_files_at(directory):
		if file.ends_with(".gd"):
			found.append(directory.path_join(file))
	for subdirectory: String in DirAccess.get_directories_at(directory):
		found.append_array(_scripts(directory.path_join(subdirectory)))
	return found
