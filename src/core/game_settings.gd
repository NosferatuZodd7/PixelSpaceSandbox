class_name GameSettings
extends RefCounted
## The player's settings, saved in user://settings.cfg and applied at startup.
##
## Every setting has a safe default: a missing or broken settings file never
## stops the game, it only falls back to the defaults.

## Emitted after any setting changes (from the settings screen or a shortcut).
signal changed

const DEFAULT_PATH: String = "user://settings.cfg"
const SECTION: String = "settings"

var locale: String = ""
var fullscreen: bool = false
var vsync: bool = true

var _path: String


func _init(path: String = DEFAULT_PATH) -> void:
	_path = path
	locale = default_locale(OS.get_locale())


## The interface language on a first launch: Portuguese on Portuguese
## systems, English otherwise.
static func default_locale(system_locale: String) -> String:
	return "pt_PT" if system_locale.begins_with("pt") else "en"


## The languages the player can choose: every loaded translation.
static func available_locales() -> PackedStringArray:
	var locales: PackedStringArray = TranslationServer.get_loaded_locales()
	locales.sort()
	return locales


## Each language's name in that language ("English", "Português").
static func language_name(locale_code: String) -> String:
	var translation: Translation = TranslationServer.get_translation_object(locale_code)
	if translation == null:
		return locale_code
	var text: String = translation.get_message("LANGUAGE_NAME")
	return locale_code if text.is_empty() else text


## Reads the saved settings, keeping the default for anything missing or invalid.
func read() -> void:
	var file: ConfigFile = ConfigFile.new()
	if file.load(_path) != OK:
		return
	var saved_locale: Variant = file.get_value(SECTION, "locale", locale)
	if saved_locale is String and available_locales().has(saved_locale):
		locale = saved_locale
	var saved_fullscreen: Variant = file.get_value(SECTION, "fullscreen", fullscreen)
	if saved_fullscreen is bool:
		fullscreen = saved_fullscreen
	var saved_vsync: Variant = file.get_value(SECTION, "vsync", vsync)
	if saved_vsync is bool:
		vsync = saved_vsync


func write() -> Error:
	var file: ConfigFile = ConfigFile.new()
	file.set_value(SECTION, "locale", locale)
	file.set_value(SECTION, "fullscreen", fullscreen)
	file.set_value(SECTION, "vsync", vsync)
	return file.save(_path)


## Puts the settings into effect. Only touches what differs, so applying
## twice is harmless.
func apply() -> void:
	if TranslationServer.get_locale() != locale:
		TranslationServer.set_locale(locale)
	if DisplayServer.get_name() == "headless":
		return
	var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	var is_fullscreen: bool = (
		mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	)
	if is_fullscreen != fullscreen:
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		)
	var vsync_mode: DisplayServer.VSyncMode = (
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)
	if DisplayServer.window_get_vsync_mode() != vsync_mode:
		DisplayServer.window_set_vsync_mode(vsync_mode)


## Changes one setting, puts it into effect, saves, and announces it.
func change(setting: StringName, value: Variant) -> void:
	set(setting, value)
	apply()
	write()
	changed.emit()
