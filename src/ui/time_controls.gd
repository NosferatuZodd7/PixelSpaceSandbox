class_name TimeControls
extends HBoxContainer
## Clickable time controls under the big counter: slower, pause or resume,
## faster (the same as −, Space and + on the keyboard), then, while news of
## a change is travelling, jump to its next arrival (N) and follow the wave
## (G).

signal changed
signal next_arrival_requested
signal follow_wave_toggled(on: bool)

var clock: SimClock

var _slower: Button
var _pause: Button
var _faster: Button
var _next: Button
var _wave: Button
## Whether news is travelling (the last two buttons only show then).
var news_travelling: bool = false


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override(&"separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slower = _button(&"slower", "TIME_SLOWER")
	_pause = _button(&"pause", "TIME_PAUSE")
	_faster = _button(&"faster", "TIME_FASTER")
	_next = _button(&"next", "TIME_NEXT_ARRIVAL")
	_wave = _button(&"wave", "TIME_FOLLOW_WAVE")
	_wave.toggle_mode = true
	_next.pressed.connect(func() -> void: next_arrival_requested.emit())
	_wave.toggled.connect(func(on: bool) -> void: follow_wave_toggled.emit(on))
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
	_next.visible = news_travelling
	_wave.visible = news_travelling


func slower_button() -> Button:
	return _slower


func pause_button() -> Button:
	return _pause


func faster_button() -> Button:
	return _faster


func next_button() -> Button:
	return _next


func wave_button() -> Button:
	return _wave


## Shows whether the wave is being followed, without announcing it.
func show_following(on: bool) -> void:
	_wave.set_pressed_no_signal(on)


func _button(icon: StringName, tooltip_key: String) -> Button:
	var button: Button = Button.new()
	button.icon = PixelIcons.texture(icon)
	button.tooltip_text = tooltip_key
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = &"ArrowButton"
	add_child(button)
	return button
