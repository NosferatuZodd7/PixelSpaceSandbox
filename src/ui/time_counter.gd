class_name TimeCounter
extends VBoxContainer
## The big pixel time counter at the top of the screen: the date (or the
## year, far from today), and below it the speed ("x86 400 · 1 day/s") or
## PAUSED, and a warning when the simulation cannot keep up with it.

## Above this speed (simulated seconds per real second) the clock shows
## only the date, since hours and minutes would just flicker.
const DATE_ONLY_ABOVE: float = 3600.0
const REFRESH_SECONDS: float = 0.1

var clock: SimClock
## When set, the counter warns while it lags behind the chosen speed.
var simulation: Simulation

var _date: Label
var _speed: Label
var _since_refresh: float = 0.0


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override(&"separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_date = Label.new()
	_date.theme_type_variation = &"TitleLabel"
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_date.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_date)
	_speed = Label.new()
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_speed)


func _process(delta: float) -> void:
	_since_refresh += delta
	if clock != null and _since_refresh >= REFRESH_SECONDS:
		_since_refresh = 0.0
		refresh()


func refresh() -> void:
	_date.text = Format.date(clock.time, clock.speed() <= DATE_ONLY_ABOVE)
	if clock.paused:
		_speed.text = tr("TIME_PAUSED")
		_speed.theme_type_variation = &"KeyLabel"
	else:
		_speed.text = "%s  ·  %s" % [Format.multiplier(clock.speed()), speed_words(clock.speed())]
		_speed.theme_type_variation = &"DimLabel"
		if simulation != null and simulation.lagging:
			_speed.text += "  ·  " + tr("TIME_LAGGING")
			_speed.theme_type_variation = &"KeyLabel"


func date_text() -> String:
	return _date.text


func speed_text() -> String:
	return _speed.text


## "real time", "slow motion", or how much time passes each second.
static func speed_words(seconds_per_second: float) -> String:
	if seconds_per_second < 1.0:
		return TranslationServer.translate("TIME_SLOW_MOTION")
	if seconds_per_second == 1.0:
		return TranslationServer.translate("TIME_REAL")
	return Format.tr_units("TIME_PER_SECOND", Format.duration(seconds_per_second))
