class_name SmartTime
extends RefCounted
## How fast time should run to watch a change spread: light and gravity
## are slow at the scale of a system and orbits slower still. Following a
## front, time runs so it crosses half the view in a few seconds (faster as
## the view widens with it); as it is about to reach a body, time eases
## down so the moment takes a while; speeds change smoothly.

## Real seconds a front takes to cross half the view.
const CROSS_SECONDS: float = 3.0
## Real seconds the last stretch before an arrival takes.
const ARRIVAL_SECONDS: float = 1.5
## Never slower than real time.
const MIN_SPEED: float = 1.0
## Largest change of speed per real second (a factor).
const MAX_CHANGE_PER_SECOND: float = 8.0


## Simulated seconds per real second for a front to cross a view of this
## half-width (AU) in CROSS_SECONDS.
static func wave_speed(view_radius_au: float) -> float:
	var light_au_per_second: float = Units.C / Units.YEAR_SECONDS
	return view_radius_au / (light_au_per_second * CROSS_SECONDS)


## Simulated seconds per real second for an arrival this many simulated
## seconds away to take ARRIVAL_SECONDS.
static func arrival_speed(seconds_to_arrival: float) -> float:
	return maxf(MIN_SPEED, seconds_to_arrival / ARRIVAL_SECONDS)


## A speed moved towards another by at most MAX_CHANGE_PER_SECOND per real
## second.
static func ease_towards(current: float, wanted: float, real_seconds: float) -> float:
	var factor: float = pow(MAX_CHANGE_PER_SECOND, real_seconds)
	if wanted > current:
		return minf(wanted, current * factor)
	return maxf(wanted, current / factor)
