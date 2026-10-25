class_name SimClock
extends RefCounted
## The one global clock: the time in years since J2000.0, and how fast it
## runs. Speeds come from a ladder in data/time_speeds.json, from slow motion
## to billions of years per second.

const DEFAULT_PATH: String = "res://data/time_speeds.json"

var time: float = 0.0
var paused: bool = false
## Simulated seconds per real second, slowest first.
var ladder: PackedFloat64Array = PackedFloat64Array([1.0])
## Number key → ladder index.
var presets: Dictionary[String, int] = {}
var speed_index: int = 0
## A speed set by smart time instead of the ladder's (NAN when none).
var steered_speed: float = NAN


static func load_default(start_time: float) -> SimClock:
	var clock: SimClock = SimClock.new()
	clock.time = start_time
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_PATH))
	if data is Dictionary:
		clock.configure(data)
	return clock


## Reads the ladder, the presets and the starting speed.
func configure(data: Dictionary) -> void:
	var speeds: Variant = data.get("ladder_seconds_per_second")
	if speeds is Array and not (speeds as Array).is_empty():
		ladder = PackedFloat64Array(speeds as Array)
	presets.clear()
	var keys: Variant = data.get("presets", {})
	if keys is Dictionary:
		for key: Variant in keys:
			var index: int = ladder.find(float(keys[key]))
			if index != -1:
				presets[str(key)] = index
	var start: int = ladder.find(float(data.get("default_seconds_per_second", 1.0)))
	speed_index = maxi(start, 0)


## Simulated seconds per real second.
func speed() -> float:
	return ladder[speed_index] if is_nan(steered_speed) else steered_speed


## Runs at any speed (smart time) until released or the player picks one.
func steer(seconds_per_second: float) -> void:
	steered_speed = seconds_per_second


func is_steered() -> bool:
	return not is_nan(steered_speed)


## Back to the speed the player chose.
func release() -> void:
	steered_speed = NAN


func years_per_second() -> float:
	return speed() / Units.YEAR_SECONDS


## Moves time forward by a real duration (seconds), unless paused.
## Returns the simulated years that passed.
func advance(real_seconds: float) -> float:
	if paused:
		return 0.0
	var step: float = real_seconds * years_per_second()
	time += step
	return step


func faster() -> void:
	release()
	speed_index = mini(speed_index + 1, ladder.size() - 1)


func slower() -> void:
	release()
	speed_index = maxi(speed_index - 1, 0)


## Jumps to the speed bound to a number key. Returns false if none is.
func use_preset(key: String) -> bool:
	if not presets.has(key):
		return false
	release()
	speed_index = presets[key]
	paused = false
	return true


func toggle_pause() -> void:
	paused = not paused
