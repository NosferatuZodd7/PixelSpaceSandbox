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


func test_menu_offers_new_system_settings_and_quit() -> void:
	var new_system: Button = _main.get_node("UI/Root/Center/Menu/NewSystem")
	var settings: Button = _main.get_node("UI/Root/Center/Menu/Settings")
	var quit: Button = _main.get_node("UI/Root/Center/Menu/Quit")
	assert_false(new_system.disabled, "new system enabled")
	assert_false(settings.disabled, "settings enabled")
	assert_false(quit.disabled, "quit enabled")
	assert_true(new_system.has_focus(), "keyboard starts on New system")
	assert_true(new_system.pressed.is_connected(Callable(_main, &"start_new_system")), "New system opens the space scene")


func test_settings_open_and_close_with_escape() -> void:
	_main.call(&"open_settings")
	await wait_frames(1)
	var panel: SettingsPanel = _main.get_node("UI/Root/Center/SettingsPanel")
	assert_true(panel.visible, "settings shown")
	assert_false((_main.get_node("UI/Root/Center/Menu") as Control).visible, "menu hidden")
	assert_eq(panel.rows().size(), 4, "language, display, vsync, updates")
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


func test_no_update_check_when_not_an_exported_game() -> void:
	var notice: UpdateNotice = _main.get_node("UI/Root/UpdateNotice")
	assert_false(notice.visible, "running from the editor or the tests, the game does not update itself")
	assert_eq(notice.updater.state, Updater.State.DISABLED)


func test_a_newer_build_is_offered_on_the_title_screen() -> void:
	var notice: UpdateNotice = _main.get_node("UI/Root/UpdateNotice")
	var updater: Updater = notice.updater
	updater.channel = UpdateChecker.Channel.TESTING
	updater.current_version = "0.2.0-dev.1"
	var reply: String = JSON.stringify([{
		"tag_name": "v0.2.0-dev.7", "draft": false, "prerelease": true, "body": "", "html_url": "https://example.org/r",
		"assets": [
			{"name": "PixelSpaceSandbox-v0.2.0-dev.7%s" % UpdateChecker.asset_suffix(), "size": 10, "browser_download_url": "https://example.org/a.zip"},
			{"name": "PixelSpaceSandbox-v0.2.0-dev.7%s.sha256" % UpdateChecker.asset_suffix(), "size": 10, "browser_download_url": "https://example.org/a.zip.sha256"},
		],
	}])
	updater.handle_releases(HTTPRequest.RESULT_SUCCESS, 200, reply)
	await wait_frames(1)
	assert_eq(updater.state, Updater.State.AVAILABLE)
	assert_true(notice.visible, "the notice shows")
	assert_true(notice.text().contains("0.2.0-dev.7"), "naming the new version: %s" % notice.text())
	assert_true(notice.action_button().visible, "with a button to update")
	updater.handle_releases(HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	await wait_frames(1)
	assert_eq(updater.state, Updater.State.FAILED, "no connection")
	assert_true(notice.text().contains("no connection"), "is said plainly: %s" % notice.text())
	updater.handle_releases(HTTPRequest.RESULT_SUCCESS, 200, "[]")
	await wait_frames(1)
	assert_eq(updater.state, Updater.State.UP_TO_DATE)


## Changing the update channel while a new version downloads (the title
## screen checks again then) does not cut the download short.
func test_a_check_does_not_interrupt_a_download() -> void:
	var updater: Updater = (_main.get_node("UI/Root/UpdateNotice") as UpdateNotice).updater
	updater.channel = UpdateChecker.Channel.TESTING
	for busy: Updater.State in [Updater.State.DOWNLOADING, Updater.State.INSTALLING, Updater.State.RESTARTING]:
		updater.state = busy
		updater.check()
		assert_eq(updater.state, busy, "still %s" % Updater.State.keys()[busy])
	updater.state = Updater.State.DISABLED


## The longest update message, with its button, fits on screen in both
## languages without running into the version line.
func test_an_update_failure_fits_beside_the_version() -> void:
	var notice: UpdateNotice = _main.get_node("UI/Root/UpdateNotice")
	var version: Label = _main.get_node("UI/Root/VersionLabel")
	var updater: Updater = notice.updater
	updater.release = {"version": "0.2.0-dev.17", "page_url": "https://example.org/r"}
	updater.error_key = "UPDATE_ERROR_INSTALL"
	updater.state = Updater.State.FAILED
	var screen: Rect2 = Rect2(Vector2.ZERO, (_main.get_node("UI/Root") as Control).size)
	for locale: String in ["en", "pt_PT"]:
		TranslationServer.set_locale(locale)
		updater.state_changed.emit()
		await wait_frames(2)
		assert_true(notice.action_button().visible, "%s: with the button to the release page" % locale)
		var rect: Rect2 = notice.get_global_rect().merge(notice.action_button().get_global_rect())
		assert_true(screen.encloses(rect), "%s: on screen at %s" % [locale, rect])
		var text_width: float = version.get_theme_font(&"font").get_string_size(version.text, HORIZONTAL_ALIGNMENT_LEFT, -1, version.get_theme_font_size(&"font_size")).x
		var version_rect: Rect2 = Rect2(version.get_global_rect().end - Vector2(text_width, version.size.y), Vector2(text_width, version.size.y))
		assert_false(rect.intersects(version_rect), "%s: clear of the version (%s, %s)" % [locale, rect, version_rect])
		assert_true(notice.text().contains(tr("UPDATE_ERROR_INSTALL")), notice.text())
