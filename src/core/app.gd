extends Node
## Autoload "App": global setup every screen relies on (key bindings, the
## player's settings) and the shortcuts that work everywhere.

var settings: GameSettings = GameSettings.new()


func _ready() -> void:
	InputBindings.apply()
	settings.read()
	settings.apply()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen"):
		settings.change(&"fullscreen", not settings.fullscreen)
		get_viewport().set_input_as_handled()
