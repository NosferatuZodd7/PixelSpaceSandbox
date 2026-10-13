extends TestCase
## The title screen starts, draws a sky, and its menu and settings screen
## work with the keyboard, with no errors along the way.

const MAIN_SCENE: String = "res://scenes/main.tscn"
const SETTINGS_PATH: String = "user://test_title_settings.cfg"

var _main: Node
var _settings: GameSettings


func before_each() -> void:
	_remove_settings_file()
	_settings = GameSettings.new(SETTINGS_PATH)
	_settings.locale = "en"
	_settings.apply()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.set(&"settings", _settings)
	tree.root.add_child(_main)
	await wait_frames(1)


func after_each() -> void:
	TranslationServer.set_locale("en")
	_main.queue_free()
	await wait_frames(2)
	_remove_settings_file()


func test_sky_is_generated() -> void:
	var sky: StarfieldBackground = _main.get_node("Sky")
	var ready: bool = await wait_until(func() -> bool: return not sky.is_generating(), 10.0)
	assert_true(ready, "sky generated within 10 s")
	await wait_frames(2)
	assert_eq(sky.sky_seed, 7, "default seed")


func test_new_sky_request_while_generating_uses_the_latest_seed() -> void:
	var sky: StarfieldBackground = _main.get_node("Sky")
	var seeds: Array[int] = []
	sky.sky_ready.connect(func(sky_seed: int) -> void: seeds.append(sky_seed))
	sky.generate(11)
	sky.generate(12)
	var done: bool = await wait_until(func() -> bool: return seeds.has(12) and not sky.is_generating(), 20.0)
	assert_true(done, "latest sky generated")
	assert_false(seeds.has(11), "the superseded seed is skipped")


func test_menu_offers_settings_and_quit() -> void:
	var new_system: Button = _main.get_node("UI/Root/Center/Menu/NewSystem")
	var settings: Button = _main.get_node("UI/Root/Center/Menu/Settings")
	var quit: Button = _main.get_node("UI/Root/Center/Menu/Quit")
	assert_true(new_system.disabled, "new system waits for milestone 1")
	assert_false(settings.disabled, "settings enabled")
	assert_false(quit.disabled, "quit enabled")
	assert_true(settings.has_focus(), "keyboard starts on Settings")


func test_settings_open_and_close_with_escape() -> void:
	_main.call(&"open_settings")
	await wait_frames(1)
	var panel: SettingsPanel = _main.get_node("UI/Root/Center/SettingsPanel")
	assert_true(panel.visible, "settings shown")
	assert_false((_main.get_node("UI/Root/Center/Menu") as Control).visible, "menu hidden")
	assert_eq(panel.rows().size(), 3, "language, display, vsync")
	assert_true(panel.rows()[0].has_focus(), "first row focused")

	_press(&"ui_cancel")
	await wait_frames(1)
	assert_false(panel.visible, "Esc closes the settings")
	assert_true((_main.get_node("UI/Root/Center/Menu") as Control).visible, "menu back")
	assert_true((_main.get_node("UI/Root/Center/Menu/Settings") as Button).has_focus(), "focus back on Settings")


func test_language_row_switches_language_and_saves() -> void:
	_main.call(&"open_settings")
	await wait_frames(1)
	var language: SettingRow = (_main.get_node("UI/Root/Center/SettingsPanel") as SettingsPanel).rows()[0]
	assert_eq(language.value_text(), "English")
	language.step(1)
	await wait_frames(1)
	assert_eq(TranslationServer.get_locale(), "pt_PT")
	assert_eq(language.value_text(), "Português")
	assert_eq(tr("MENU_SETTINGS"), "Definições")
	var saved: GameSettings = GameSettings.new(SETTINGS_PATH)
	saved.read()
	assert_eq(saved.locale, "pt_PT", "choice saved")


func test_keyboard_changes_the_focused_setting() -> void:
	_main.call(&"open_settings")
	await wait_frames(1)
	var vsync: SettingRow = (_main.get_node("UI/Root/Center/SettingsPanel") as SettingsPanel).rows()[2]
	vsync.grab_focus()
	assert_true(_settings.vsync, "vsync on by default")
	_press(&"ui_right")
	await wait_frames(1)
	assert_false(_settings.vsync, "right arrow switched vsync off")
	assert_eq(vsync.value_text(), "VSYNC_OFF")
	_press(&"ui_left")
	await wait_frames(1)
	assert_true(_settings.vsync, "left arrow switched it back on")


func test_rows_follow_changes_made_elsewhere() -> void:
	_main.call(&"open_settings")
	await wait_frames(1)
	var display: SettingRow = (_main.get_node("UI/Root/Center/SettingsPanel") as SettingsPanel).rows()[1]
	assert_eq(display.value_text(), "DISPLAY_WINDOWED")
	_settings.change(&"fullscreen", true)
	assert_eq(display.value_text(), "DISPLAY_FULLSCREEN", "F11 shows up in the open settings")


func _press(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	tree.root.push_input(event)


func _remove_settings_file() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
