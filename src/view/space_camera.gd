class_name SpaceCamera
extends RefCounted
## Where the view looks and how close: a point in AU at the centre of the
## screen and a scale in pixels per AU.
##
## Math only. Positions stay 64-bit until they become screen pixels, so the
## view is exact from the surface of a star to the edge of the system
## (a floating origin around the camera).

const MIN_SCALE: float = 0.5
const MAX_SCALE: float = 2.0e7
## How quickly a zoom eases in (higher is snappier).
const ZOOM_EASE: float = 14.0

var center_x: float = 0.0
var center_y: float = 0.0
var scale: float = 100.0
var target_scale: float = 100.0
var viewport_size: Vector2 = Vector2(640, 360)

var _anchor_screen: Vector2 = Vector2.ZERO
var _anchor_x: float = 0.0
var _anchor_y: float = 0.0
var _has_anchor: bool = false


## Screen pixel of a point (AU). y grows upwards in space, downwards on screen.
func to_screen(x: float, y: float) -> Vector2:
	return Vector2((x - center_x) * scale + viewport_size.x * 0.5, (center_y - y) * scale + viewport_size.y * 0.5)


## The point in space (AU) under a screen pixel: [x, y].
func to_world(screen: Vector2) -> PackedFloat64Array:
	return PackedFloat64Array([
		center_x + (screen.x - viewport_size.x * 0.5) / scale,
		center_y - (screen.y - viewport_size.y * 0.5) / scale,
	])


func look_at(x: float, y: float) -> void:
	center_x = x
	center_y = y
	if _has_anchor:
		_anchor_screen = viewport_size * 0.5
		_anchor_x = x
		_anchor_y = y


## Zooms by a factor, keeping the point under the given screen pixel in place.
func zoom_at(screen: Vector2, factor: float) -> void:
	target_scale = clampf(target_scale * factor, MIN_SCALE, MAX_SCALE)
	var world: PackedFloat64Array = to_world(screen)
	_anchor_screen = screen
	_anchor_x = world[0]
	_anchor_y = world[1]
	_has_anchor = true


## Sets the zoom at once (no easing), keeping the centre.
func set_scale_now(value: float) -> void:
	scale = clampf(value, MIN_SCALE, MAX_SCALE)
	target_scale = scale
	_has_anchor = false


## Moves the view by a screen distance, as if dragging space with the mouse.
func pan_pixels(delta: Vector2) -> void:
	center_x -= delta.x / scale
	center_y += delta.y / scale
	if _has_anchor:
		var world: PackedFloat64Array = to_world(_anchor_screen)
		_anchor_x = world[0]
		_anchor_y = world[1]


func is_zooming() -> bool:
	return _has_anchor


## Eases the zoom towards its target. Call once per frame.
func update(delta_seconds: float) -> void:
	if not _has_anchor:
		return
	var ratio: float = target_scale / scale
	if absf(log(ratio)) < 1e-4:
		scale = target_scale
	else:
		scale *= pow(ratio, 1.0 - exp(-ZOOM_EASE * delta_seconds))
	center_x = _anchor_x - (_anchor_screen.x - viewport_size.x * 0.5) / scale
	center_y = _anchor_y + (_anchor_screen.y - viewport_size.y * 0.5) / scale
	if scale == target_scale:
		_has_anchor = false
