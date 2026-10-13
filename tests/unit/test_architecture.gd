extends TestCase
## The simulation stays plain data plus systems: nothing under src/sim/ may
## use nodes, scenes, the palette, the theme, input or the renderer, so it
## can run headless and on worker threads.

const SIM_DIR: String = "res://src/sim"
const FORBIDDEN: Array[String] = [
	"extends Node", "extends Control", "extends CanvasItem", "Palette.", "UiTheme.", "get_tree(",
	"RenderingServer", "DisplayServer", "Input.", "InputEvent", "load(\"res://scenes", "App.",
]


func test_simulation_does_not_depend_on_the_presentation() -> void:
	var files: int = 0
	for file: String in DirAccess.get_files_at(SIM_DIR):
		if not file.ends_with(".gd"):
			continue
		files += 1
		var lines: PackedStringArray = FileAccess.get_file_as_string(SIM_DIR.path_join(file)).split("\n")
		for number: int in lines.size():
			for word: String in FORBIDDEN:
				if lines[number].contains(word):
					fail("%s:%d uses %s" % [file, number + 1, word])
	assert_true(files > 0, "found simulation scripts")
