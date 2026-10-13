extends TestCase
## Player settings: sensible defaults, saved and read back, and a broken
## settings file never breaks the game.

const PATH: String = "user://test_game_settings.cfg"


func before_each() -> void:
	_remove()


func after_each() -> void:
	_remove()
	TranslationServer.set_locale("en")


func test_first_launch_language_follows_the_system() -> void:
	assert_eq(GameSettings.default_locale("pt_PT"), "pt_PT")
	assert_eq(GameSettings.default_locale("pt_BR"), "pt_PT")
	assert_eq(GameSettings.default_locale("en_US"), "en")
	assert_eq(GameSettings.default_locale("fr_FR"), "en")


func test_every_translation_is_offered_by_its_own_name() -> void:
	var locales: PackedStringArray = GameSettings.available_locales()
	assert_true(locales.has("en") and locales.has("pt_PT"), "both languages: %s" % ", ".join(locales))
	assert_eq(GameSettings.language_name("en"), "English")
	assert_eq(GameSettings.language_name("pt_PT"), "Português")


func test_settings_survive_a_restart() -> void:
	var saved: GameSettings = GameSettings.new(PATH)
	saved.locale = "pt_PT"
	saved.fullscreen = true
	saved.vsync = false
	assert_eq(saved.write(), OK)
	var loaded: GameSettings = GameSettings.new(PATH)
	loaded.read()
	assert_eq(loaded.locale, "pt_PT")
	assert_eq(loaded.fullscreen, true)
	assert_eq(loaded.vsync, false)


func test_missing_file_keeps_the_defaults() -> void:
	var settings: GameSettings = GameSettings.new(PATH)
	settings.read()
	assert_eq(settings.locale, GameSettings.default_locale(OS.get_locale()))
	assert_false(settings.fullscreen, "windowed by default")
	assert_true(settings.vsync, "vsync on by default")


func test_invalid_values_fall_back_to_the_defaults() -> void:
	var file: ConfigFile = ConfigFile.new()
	file.set_value(GameSettings.SECTION, "locale", "tlh")
	file.set_value(GameSettings.SECTION, "fullscreen", "yes")
	file.set_value(GameSettings.SECTION, "vsync", 3)
	file.save(PATH)
	var settings: GameSettings = GameSettings.new(PATH)
	settings.read()
	assert_eq(settings.locale, GameSettings.default_locale(OS.get_locale()), "unknown language ignored")
	assert_false(settings.fullscreen, "non-boolean fullscreen ignored")
	assert_true(settings.vsync, "non-boolean vsync ignored")


func test_garbage_file_keeps_the_defaults() -> void:
	var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("%%% not a settings file [[[")
	file.close()
	var settings: GameSettings = GameSettings.new(PATH)
	settings.read()
	assert_false(settings.fullscreen)
	assert_true(settings.vsync)


func test_change_applies_saves_and_announces() -> void:
	var settings: GameSettings = GameSettings.new(PATH)
	settings.locale = "en"
	var announced: Array[int] = [0]
	settings.changed.connect(func() -> void: announced[0] += 1)
	settings.change(&"locale", "pt_PT")
	assert_eq(TranslationServer.get_locale(), "pt_PT", "applied")
	assert_eq(announced[0], 1, "announced once")
	var loaded: GameSettings = GameSettings.new(PATH)
	loaded.read()
	assert_eq(loaded.locale, "pt_PT", "saved")


func _remove() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
