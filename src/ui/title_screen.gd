extends Node
## Milestone 0 title screen. It shows the pixel-perfect setup, the palette, the
## fonts and a seeded sky, and answers a few keys: new sky, language, palette,
## fullscreen (handled by App) and quit.

## Actions listed in the hint bar, with the text that explains each one.
const HINTS: Array[Array] = [
	[&"new_sky", "HINT_NEW_SKY"],
	[&"toggle_language", "HINT_LANGUAGE"],
	[&"toggle_palette", "HINT_PALETTE"],
	[&"toggle_fullscreen", "HINT_FULLSCREEN"],
	[&"quit", "HINT_QUIT"],
]

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _sky: StarfieldBackground = $Sky
@onready var _root: Control = $UI/Root
@onready var _hints: HBoxContainer = $UI/Root/Hints
@onready var _seed_label: Label = $UI/Root/SeedLabel
@onready var _language_label: Label = $UI/Root/LanguageLabel
@onready var _version_label: Label = $UI/Root/VersionLabel
@onready var _palette_strip: PaletteStrip = $UI/Root/PaletteStrip


func _ready() -> void:
	_rng.randomize()
	_root.theme = UiTheme.shared()
	var engine: Dictionary = Engine.get_version_info()
	_version_label.text = "v%s · Godot %d.%d.%d" % [
		ProjectSettings.get_setting("application/config/version"),
		engine["major"], engine["minor"], engine["patch"],
	]
	_build_hints()
	_update_texts()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_texts()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"new_sky"):
		_sky.generate(_rng.randi_range(1, 999_999))
		_update_texts()
	elif event.is_action_pressed(&"toggle_language"):
		App.cycle_language()
	elif event.is_action_pressed(&"toggle_palette"):
		_palette_strip.visible = not _palette_strip.visible
	elif event.is_action_pressed(&"quit"):
		get_tree().quit()
	else:
		return
	get_viewport().set_input_as_handled()


func _update_texts() -> void:
	_seed_label.text = tr("SEED_LABEL") % _sky.sky_seed
	_language_label.text = tr("LANGUAGE_NAME")


## One "KEY text" pair per action, using the action's current first key, so
## the hints follow rebinding.
func _build_hints() -> void:
	for child: Node in _hints.get_children():
		_hints.remove_child(child)
		child.queue_free()
	for hint: Array in HINTS:
		var action: StringName = hint[0]
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		if events.is_empty():
			continue
		if _hints.get_child_count() > 0:
			var gap: Control = Control.new()
			gap.custom_minimum_size = Vector2(8, 0)
			_hints.add_child(gap)
		var key: Label = Label.new()
		key.theme_type_variation = &"KeyLabel"
		key.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		key.text = InputBindings.key_label(events[0] as InputEventKey).to_upper()
		var text: Label = Label.new()
		text.theme_type_variation = &"DimLabel"
		text.text = hint[1]
		_hints.add_child(key)
		_hints.add_child(text)
