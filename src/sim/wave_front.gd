class_name WaveFront
extends RefCounted
## A change spreading from where it happened at the speed of light.
##
## A light front carries a change in what a source emits (a star placed,
## removed, brightened…); a gravity front carries a change in mass (a body
## placed, removed, merged…). A body feels the change only once the front's
## radius has passed its distance from the emission point. Checking that is
## one distance comparison per body, so fronts are cheap.

enum Kind { LIGHT, GRAVITY }

var kind: Kind = Kind.LIGHT
var origin_x: float = 0.0
var origin_y: float = 0.0
var origin_z: float = 0.0
## When it was emitted, in years since J2000.0.
var emitted_at: float = 0.0
## AU per year; the real speed of light unless a world law changes it.
var speed: float = Units.C
## What changed, for the label next to the ring ("Sun removed"…).
var label_key: String = ""


static func create(front_kind: Kind, x: float, y: float, z: float, time: float) -> WaveFront:
	var front: WaveFront = WaveFront.new()
	front.kind = front_kind
	front.origin_x = x
	front.origin_y = y
	front.origin_z = z
	front.emitted_at = time
	return front


func radius_at(t: float) -> float:
	return maxf(0.0, (t - emitted_at) * speed)


func distance_to(x: float, y: float, z: float) -> float:
	var dx: float = x - origin_x
	var dy: float = y - origin_y
	var dz: float = z - origin_z
	return sqrt(dx * dx + dy * dy + dz * dz)


func has_reached(x: float, y: float, z: float, t: float) -> bool:
	return radius_at(t) >= distance_to(x, y, z)


## When the front reaches a point (that stays put), in years since J2000.0.
func arrival_time(x: float, y: float, z: float) -> float:
	return emitted_at + distance_to(x, y, z) / speed


## True once the front is past every body of the system by 1% (bodies keep
## moving, so a margin keeps one from slipping back outside).
func has_passed_all(system: StarSystem, t: float) -> bool:
	var radius: float = radius_at(t)
	for i: int in system.size():
		if distance_to(system.x(i), system.y(i), system.z(i)) * 1.01 > radius:
			return false
	return true
