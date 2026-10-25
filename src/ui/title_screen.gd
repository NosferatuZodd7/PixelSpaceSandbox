extends Node
## Title screen: the seeded sky, the game's name, the main menu (new
## system, settings, quit) and, in an exported game, whether a newer build
## is out (it installs itself on request). Works with the mouse or the
## keyboard.

const SPACE_SCENE: String = "res://scenes/space.tscn"

## The settings the menu edits. Defaults to the App's; tests set their own
## before the screen enters the tree.
var settings: GameSettings

@onready var _menu: VBoxContainer = $UI/Root/Center/Menu
@onready var _new_system_button: Button = $UI/Root/Center/Menu/NewSystem
@onready var _settings_button: Button = $UI/Root/Center/Menu/Settings
@onready var _quit_button: Button = $UI/Root/Center/Menu/Quit
@onready var _settings_panel: SettingsPanel = $UI/Root/Center/SettingsPanel
@onready var _version_label: Label = $UI/Root/VersionLabel
@onready var _update_notice: UpdateNotice = $UI/Root/UpdateNotice


func _ready() -> void:
	if settings == null:
		settings = App.settings
	($UI/Root as Control).theme = UiTheme.shared()
	var engine: Dictionary = Engine.get_version_info()
	_version_label.text = "v%s · Godot %d.%d.%d" % [
		ProjectSettings.get_setting("application/config/version"),
		engine["major"], engine["minor"], engine["patch"],
	]
	_new_system_button.pressed.connect(start_new_system)
	_settings_button.pressed.connect(open_settings)
	_quit_button.pressed.connect(func() -> void: get_tree().quit())
	_settings_panel.closed.connect(_on_settings_closed)
	_new_system_button.grab_focus()
	_update_notice.updater.channel = settings.update_channel
	_update_notice.updater.check()


## Milestone 1 opens the Solar System at today's date; milestone 3 adds the
## new-system dialog (generator and presets) in between.
func start_new_system() -> void:
	get_tree().change_scene_to_file(SPACE_SCENE)


func open_settings() -> void:
	_menu.hide()
	_settings_panel.open(settings)


func is_settings_open() -> bool:
	return _settings_panel.visible


func _on_settings_closed() -> void:
	_menu.show()
	_settings_button.grab_focus()
	# The player may have chosen another update channel.
	if _update_notice.updater.channel != settings.update_channel:
		_update_notice.updater.channel = settings.update_channel
		_update_notice.updater.check()
