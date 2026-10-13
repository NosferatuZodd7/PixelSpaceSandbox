extends Node
## Autoload "App": global setup that every screen relies on, and the global
## shortcuts (fullscreen) that work everywhere.


func _ready() -> void:
	InputBindings.apply()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen"):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


func toggle_fullscreen() -> void:
	var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## Switches the interface to the next loaded language.
func cycle_language() -> void:
	var locales: PackedStringArray = TranslationServer.get_loaded_locales()
	if locales.is_empty():
		return
	locales.sort()
	var current: int = locales.find(TranslationServer.get_locale())
	TranslationServer.set_locale(locales[(current + 1) % locales.size()])
