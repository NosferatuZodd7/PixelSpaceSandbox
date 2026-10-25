class_name TimeControls
extends HBoxContainer
## Clickable time controls under the big counter: slower, pause or resume,
## faster. The same as −, Space and + on the keyboard.

signal changed

var clock: SimClock

var _slower: Button
var _pause: Button
var _faster: Button


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override(&"separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slower = _button(&"slower", "TIME_SLOWER")
	_pause = _button(&"pause", "TIME_PAUSE")
	_faster = _button(&"faster", "TIME_FASTER")
	_slower.pressed.connect(func() -> void:
		clock.slower()
		clock.paused = false
		changed.emit())
	_pause.pressed.connect(func() -> void:
		clock.toggle_pause()
		changed.emit())
	_faster.pressed.connect(func() -> void:
		clock.faster()
		clock.paused = false
		changed.emit())


func _process(_delta: float) -> void:
	if clock == null:
		return
	var paused: bool = clock.paused
	_pause.icon = PixelIcons.texture(&"play" if paused else &"pause")
	_pause.tooltip_text = "TIME_RESUME" if paused else "TIME_PAUSE"


func slower_button() -> Button:
	return _slower


func pause_button() -> Button:
	return _pause


func faster_button() -> Button:
	return _faster


func _button(icon: StringName, tooltip_key: String) -> Button:
	var button: Button = Button.new()
	button.icon = PixelIcons.texture(icon)
	button.tooltip_text = tooltip_key
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = &"ArrowButton"
	add_child(button)
	return button
