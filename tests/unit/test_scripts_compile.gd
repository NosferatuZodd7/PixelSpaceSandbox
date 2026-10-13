extends TestCase
## Every script compiles, including scripts nothing loads yet, so typing
## errors (untyped declarations are errors) surface in the test run.

const DIRECTORIES: Array[String] = ["res://src", "res://tests", "res://tools"]


func test_every_script_compiles() -> void:
	var count: int = 0
	for directory: String in DIRECTORIES:
		for path: String in _scripts(directory):
			var script: GDScript = load(path) as GDScript
			assert_true(script != null and script.can_instantiate(), "%s compiles" % path)
			count += 1
	assert_true(count > 0, "found scripts")


func _scripts(directory: String) -> PackedStringArray:
	var found: PackedStringArray = []
	if not DirAccess.dir_exists_absolute(directory):
		return found
	for file: String in DirAccess.get_files_at(directory):
		if file.ends_with(".gd"):
			found.append(directory.path_join(file))
	for subdirectory: String in DirAccess.get_directories_at(directory):
		found.append_array(_scripts(directory.path_join(subdirectory)))
	return found
