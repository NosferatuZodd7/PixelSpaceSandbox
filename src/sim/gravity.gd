class_name Gravity
extends RefCounted
## Shared constants of the gravity simulation, and the kernel that runs it:
## the native one (the C++ GDExtension class "GravityCore") when it is
## loaded, otherwise the GDScript reference (GravityCoreScript). Both read
## and write an NBodyState and give the same results.

## How a massive body moves.
enum Mode {
	## On a fixed conic around its parent (exact and cheap).
	RAILS,
	## Integrated: pulled by every other body.
	FREE,
	## Removed, but still pulling the bodies its removal has not reached.
	GHOST,
	## Gone for good.
	GONE,
}

enum ParticleMode { ASLEEP, AWAKE, GONE }

## Why an advance() call returned.
enum Status {
	## Reached the target time.
	REACHED,
	## Stopped early because something collided (see the result's lists).
	EVENTS,
	## Stopped early to stay within the frame budget (the game lags).
	BUDGET,
}

const NATIVE_CLASS: StringName = &"GravityCore"
## Numbers per Kepler element set (see Kepler.elements_from_state).
const ELEMENT_SIZE: int = 12
## Step size as a share of the shortest dynamical time (about 250 steps per orbit).
const ETA: float = 0.025
## Steps are powers of two of this unit: 2^-40 years, about 29 µs.
const UNIT: float = 1.0 / 1099511627776.0
const MAX_LEVEL: int = 42
## A particle steps at most once every 2^this global steps.
const PARTICLE_MAX_LEVEL: int = 16
## An asleep particle wakes within this many Hill radii of a body.
const WAKE_HILL: float = 3.0
## ...but never farther from it than this share of its own distance to its
## parent (a companion star's Hill sphere can reach the main star).
const WAKE_REACH: float = 0.5
## An awake particle falls asleep once every other body is this many times
## farther than the distance that would wake it...
const SLEEP_FACTOR: float = 2.0
## ...a limit capped at this share of that body's distance to the particle's
## parent (a companion star's zone would otherwise keep a whole belt awake).
const SLEEP_REACH: float = 0.75
## Around a body that itself circles another, a particle sleeps only if its
## whole orbit stays within this share of the body's Hill sphere (stable
## orbits reach about half of it; farther out the outer star's tide is
## strong), and wakes if it is found beyond WAKE_HILL_SHARE of it.
const SLEEP_HILL_SHARE: float = 0.4
const WAKE_HILL_SHARE: float = 0.5
## A passing mass change wakes an asleep particle when it changes the pull
## on it by more than this share of its parent's.
const FRONT_WAKE_RATIO: float = 1e-6
## Most fronts a mass change can be gated by at once (bits in a mask).
const MAX_FRONTS: int = 30

## Whether the game runs on the native kernel when it is loaded (approved
## after the benchmark, see docs/DESIGN.md). Tests may turn it off to run
## the game on the GDScript kernel.
static var native_enabled: bool = true


static func create_core() -> Object:
	if native_enabled and native_available():
		return ClassDB.instantiate(NATIVE_CLASS)
	return GravityCoreScript.new()


static func native_available() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


## A kernel by name, "script" or "native"; null for an unknown name or a
## native kernel that is not loaded. For tests and measurements.
static func kernel_named(kernel_name: String) -> Object:
	match kernel_name:
		"script":
			return GravityCoreScript.new()
		"native":
			return ClassDB.instantiate(NATIVE_CLASS) if native_available() else null
	return null


static func step_size(level: int) -> float:
	return UNIT * pow(2.0, level)
