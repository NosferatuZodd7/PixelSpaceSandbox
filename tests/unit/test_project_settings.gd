extends TestCase
## The project keeps the decided technology: Compatibility renderer with the
## ANGLE fallback, pixel-perfect 640×360 output, typed GDScript, and Windows
## and Linux export presets.


func _setting(name: String) -> Variant:
	return ProjectSettings.get_setting(name)


func test_uses_the_compatibility_renderer() -> void:
	assert_eq(_setting("rendering/renderer/rendering_method"), "gl_compatibility")
	assert_eq(_setting("rendering/renderer/rendering_method.mobile"), "gl_compatibility")


func test_windows_falls_back_to_angle() -> void:
	assert_eq(_setting("rendering/gl_compatibility/driver.windows"), "opengl3")
	assert_eq(_setting("rendering/gl_compatibility/fallback_to_angle"), true)


func test_internal_resolution_is_640_by_360() -> void:
	assert_eq(_setting("display/window/size/viewport_width"), 640)
	assert_eq(_setting("display/window/size/viewport_height"), 360)


func test_output_is_pixel_perfect() -> void:
	assert_eq(_setting("display/window/stretch/mode"), "viewport", "stretch mode")
	assert_eq(_setting("display/window/stretch/scale_mode"), "integer", "integer scaling")
	assert_eq(_setting("display/window/stretch/aspect"), "keep", "aspect")
	assert_eq(_setting("rendering/textures/canvas_textures/default_texture_filter"), 0, "nearest filter")
	assert_eq(_setting("rendering/2d/snap/snap_2d_transforms_to_pixel"), true, "snap transforms")
	assert_eq(_setting("rendering/2d/snap/snap_2d_vertices_to_pixel"), true, "snap vertices")


func test_default_window_is_an_integer_multiple() -> void:
	var width: int = _setting("display/window/size/window_width_override")
	var height: int = _setting("display/window/size/window_height_override")
	assert_eq(width % 640, 0, "window width")
	assert_eq(height % 360, 0, "window height")
	assert_eq(width / 640.0, height / 360.0, "same scale on both axes")


func test_fonts_are_not_smoothed() -> void:
	assert_eq(_setting("gui/theme/default_font_antialiasing"), 0)
	assert_eq(_setting("gui/theme/default_font_hinting"), 0)
	assert_eq(_setting("gui/theme/default_font_subpixel_positioning"), 0)


func test_untyped_code_is_an_error() -> void:
	assert_eq(_setting("debug/gdscript/warnings/untyped_declaration"), 2)


func test_main_scene_loads() -> void:
	var path: String = _setting("application/run/main_scene")
	assert_true(ResourceLoader.exists(path), "main scene '%s' exists" % path)
	assert_true(load(path) is PackedScene, "main scene is a scene")


func test_export_presets_cover_windows_and_linux() -> void:
	var presets: ConfigFile = ConfigFile.new()
	assert_eq(presets.load("res://export_presets.cfg"), OK, "export_presets.cfg loads")
	var platforms: Dictionary[String, String] = {}
	for section: String in presets.get_sections():
		if section.begins_with("preset.") and section.count(".") == 1:
			platforms[presets.get_value(section, "platform")] = section
	assert_true(platforms.has("Windows Desktop"), "Windows preset")
	assert_true(platforms.has("Linux"), "Linux preset")
	for platform: String in platforms:
		var options: String = platforms[platform] + ".options"
		assert_eq(presets.get_value(options, "binary_format/architecture"), "x86_64", platform)
	if platforms.has("Windows Desktop"):
		var windows: String = platforms["Windows Desktop"] + ".options"
		assert_eq(presets.get_value(windows, "application/export_angle"), 1, "Windows ships ANGLE")
