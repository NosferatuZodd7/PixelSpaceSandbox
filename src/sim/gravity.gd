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
## An awake particle falls asleep when other bodies pull it less than this
## share of its parent's pull (tidally).
const SLEEP_RATIO: float = 1e-5
## A passing mass change wakes an asleep particle when it changes the pull
## on it by more than this share of its parent's.
const FRONT_WAKE_RATIO: float = 1e-6
## Most fronts a mass change can be gated by at once (bits in a mask).
const MAX_FRONTS: int = 30

## Tests set this to compare the two kernels.
static var use_script_kernel: bool = false


static func create_core() -> Object:
	if not use_script_kernel and ClassDB.class_exists(NATIVE_CLASS):
		return ClassDB.instantiate(NATIVE_CLASS)
	return GravityCoreScript.new()


static func native_available() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


static func step_size(level: int) -> float:
	return UNIT * pow(2.0, level)
