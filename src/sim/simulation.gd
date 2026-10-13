class_name Simulation
extends RefCounted
## Runs a star system through time.
##
## Milestone 1: every body follows its fixed orbit, so positions are a pure
## function of time (deterministic at any speed). Milestone 2 adds n-body
## gravity, light and gravity fronts behind this same interface.

var system: StarSystem
var clock: SimClock
## Changes spreading at the speed of light (empty until milestone 2 creates them).
var fronts: Array[WaveFront] = []


func _init(star_system: StarSystem, sim_clock: SimClock) -> void:
	system = star_system
	clock = sim_clock
	system.place_on_orbits(clock.time)


## Advances by a real duration (seconds) at the clock's speed.
func advance(real_seconds: float) -> void:
	clock.advance(real_seconds)
	system.place_on_orbits(clock.time)
	_drop_finished_fronts()


## Jumps to a moment (years since J2000.0).
func set_time(t: float) -> void:
	clock.time = t
	system.place_on_orbits(t)


## A front is finished once it has passed every body by a safe margin.
func _drop_finished_fronts() -> void:
	if fronts.is_empty():
		return
	var kept: Array[WaveFront] = []
	for front: WaveFront in fronts:
		if not front.has_passed_all(system, clock.time):
			kept.append(front)
	fronts = kept
