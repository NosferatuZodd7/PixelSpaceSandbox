extends Node
## Title screen: the seeded sky, the game's name and the main menu
## (new system, settings, quit). Works with the mouse or the keyboard.

## The settings the menu edits. Defaults to the App's; tests set their own
## before the screen enters the tree.
var settings: GameSettings

@onready var _menu: VBoxContainer = $UI/Root/Center/Menu
@onready var _settings_button: Button = $UI/Root/Center/Menu/Settings
@onready var _quit_button: Button = $UI/Root/Center/Menu/Quit
@onready var _settings_panel: SettingsPanel = $UI/Root/Center/SettingsPanel
@onready var _version_label: Label = $UI/Root/VersionLabel


func _ready() -> void:
	if settings == null:
		settings = App.settings
	($UI/Root as Control).theme = UiTheme.shared()
	var engine: Dictionary = Engine.get_version_info()
	_version_label.text = "v%s · Godot %d.%d.%d" % [
		ProjectSettings.get_setting("application/config/version"),
		engine["major"], engine["minor"], engine["patch"],
	]
	_settings_button.pressed.connect(open_settings)
	_quit_button.pressed.connect(func() -> void: get_tree().quit())
	_settings_panel.closed.connect(_on_settings_closed)
	_settings_button.grab_focus()


func open_settings() -> void:
	_menu.hide()
	_settings_panel.open(settings)


func is_settings_open() -> bool:
	return _settings_panel.visible


func _on_settings_closed() -> void:
	_menu.show()
	_settings_button.grab_focus()
