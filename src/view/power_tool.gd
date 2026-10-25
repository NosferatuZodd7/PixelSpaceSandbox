class_name PowerTool
extends Node2D
## Uses the chosen Cosmos power in space: a place power puts a new body on
## a circular orbit where the player clicks (or sweeping through, for a
## flyby) and throws it when they drag; fling throws an existing body by
## dragging from it; delete removes the body clicked. While aiming, the
## path it would take around what it circles is drawn. Right click or Esc
## puts the power away.
##
## Sits after the space view in the scene, so it sees the mouse first.

## The power was put away (right click or Esc).
signal cancelled
## A power changed the system.
signal used(power: Dictionary, body: int)

## A drag this long (pixels) means the reference speed: the circular speed
## for a new body, the speed it had for a flung one.
const DRAG_PIXELS: float = 40.0
## Shorter drags count as clicks.
const MIN_DRAG: float = 4.0
const PATH_POINTS: int = 128

var simulation: Simulation
var view: SpaceView

var _power: Dictionary = {}
var _hover: Vector2 = Vector2.ZERO
var _pressed: bool = false
var _press_at: Vector2 = Vector2.ZERO
var _target: int = -1
var _right_at: Vector2 = Vector2.ZERO


func setup(sim: Simulation, space_view: SpaceView) -> void:
	simulation = sim
	view = space_view


func set_power(power: Dictionary) -> void:
	_power = power
	_pressed = false
	_target = -1
	queue_redraw()


func is_active() -> bool:
	return not _power.is_empty()


func _process(_delta: float) -> void:
	if is_active():
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or not view.accepts_input:
		return
	if event.is_action_pressed(&"ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		_hover = motion.position
		if _pressed:
			get_viewport().set_input_as_handled()
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null:
		return
	_hover = button.position
	if button.button_index == MOUSE_BUTTON_RIGHT:
		# Right drags still pan the view; a right click cancels.
		if button.pressed:
			_right_at = button.position
		elif button.position.distance_to(_right_at) < MIN_DRAG:
			_cancel()
		return
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	if button.pressed:
		_pressed = true
		_press_at = button.position
		_target = view.pick(button.position) if _action() != "place" else -1
		return
	if not _pressed:
		return
	_pressed = false
	var drag: Vector2 = button.position - _press_at
	match _action():
		"place":
			_place(_press_at, drag)
		"fling":
			if _target != -1 and drag.length() >= MIN_DRAG:
				var v: PackedFloat64Array = _thrown_velocity(_target, drag)
				simulation.fling(_target, v[0], v[1], v[2], "FRONT_FLUNG")
				used.emit(_power, _target)
		"delete":
			var target: int = view.pick(button.position)
			if target != -1:
				simulation.remove_body(target, "FRONT_REMOVED")
				if view.selected == target:
					view.select(-1)
				used.emit(_power, target)
	_target = -1


## The point in space under a screen pixel, in the plane of what it would
## circle.
func _point_at(at: Vector2) -> PackedFloat64Array:
	var world: PackedFloat64Array = view.camera.to_world(at)
	return simulation.point_in_plane(world[0], world[1])


func _action() -> String:
	return str(_power.get("action", ""))


func _cancel() -> void:
	_power = {}
	_pressed = false
	_target = -1
	queue_redraw()
	cancelled.emit()


func _place(at: Vector2, drag: Vector2) -> void:
	var body: CelestialBody = PowerCatalog.make_body(_power, simulation.system)
	var point: PackedFloat64Array = _point_at(at)
	var v: PackedFloat64Array = _new_velocity(point, drag, body.mass)
	var index: int = simulation.place_body(body, point[0], point[1], point[2], v[0], v[1], v[2], "FRONT_PLACED")
	used.emit(_power, index)


## The velocity of a new body at a point: on a circular orbit (or a flyby)
## when there is no drag, else along the drag around the same body.
func _new_velocity(point: PackedFloat64Array, drag: Vector2, mass: float) -> PackedFloat64Array:
	var base: PackedFloat64Array
	var reference: int = simulation.dominant_body(point[0], point[1], point[2])
	if _power.has("flyby_kms"):
		var speed_far: float = Units.au_from_km(float(_power["flyby_kms"])) * Units.YEAR_SECONDS
		base = simulation.flyby_velocity(point[0], point[1], point[2], speed_far)
		while reference >= 0 and simulation.parent_of(reference) >= 0:
			reference = simulation.parent_of(reference)
	else:
		base = simulation.circular_velocity(point[0], point[1], point[2], mass)
	if drag.length() < MIN_DRAG:
		return base
	return _along_drag(reference, base, drag)


## The velocity of a flung body: along the drag, relative to what it circles.
func _thrown_velocity(index: int, drag: Vector2) -> PackedFloat64Array:
	var current: PackedFloat64Array = simulation.state.view_vel.slice(index * 3, index * 3 + 3)
	return _along_drag(simulation.parent_of(index), current, drag)


## A velocity along the drag (screen y points down, space y up), relative to
## a reference body, at the reference speed times the drag length over
## DRAG_PIXELS. The reference speed is that of base relative to the body.
func _along_drag(reference: int, base: PackedFloat64Array, drag: Vector2) -> PackedFloat64Array:
	var frame: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
	if reference >= 0:
		frame = simulation.state.view_vel.slice(reference * 3, reference * 3 + 3)
	var dx: float = base[0] - frame[0]
	var dy: float = base[1] - frame[1]
	var dz: float = base[2] - frame[2]
	var speed: float = sqrt(dx * dx + dy * dy + dz * dz)
	if speed <= 0.0:
		speed = 1.0
	speed *= drag.length() / DRAG_PIXELS
	var direction: Vector2 = drag.normalized()
	return PackedFloat64Array([frame[0] + direction.x * speed, frame[1] - direction.y * speed, frame[2]])


func _draw() -> void:
	if not is_active() or simulation == null:
		return
	var accent: Color = Palette.color(&"ui_accent")
	var path_color: Color = Palette.color(&"ui_text")
	match _action():
		"place":
			var at: Vector2 = _press_at if _pressed else _hover
			var drag: Vector2 = (_hover - _press_at) if _pressed else Vector2.ZERO
			var point: PackedFloat64Array = _point_at(at)
			var body: CelestialBody = PowerCatalog.make_body(_power, simulation.system)
			var v: PackedFloat64Array = _new_velocity(point, drag, body.mass)
			_draw_path(point, v, body.mass, path_color)
			if drag.length() >= MIN_DRAG:
				draw_line(at, _hover, accent)
			draw_arc(at, 4.0, 0.0, TAU, 12, accent)
		"fling":
			var target: int = _target if _pressed else view.pick(_hover)
			if target == -1:
				return
			var at: Vector2 = view.screen_position(target)
			_draw_brackets(at, view.display_radius(target) + 3, accent)
			if _pressed and _hover.distance_to(_press_at) >= MIN_DRAG:
				var drag: Vector2 = _hover - _press_at
				var v: PackedFloat64Array = _thrown_velocity(target, drag)
				var b: int = target * 3
				_draw_path(simulation.state.view_pos.slice(b, b + 3), v, simulation.state.final_mass(target), path_color)
				draw_line(at, at + drag, accent)
		"delete":
			var target: int = view.pick(_hover)
			if target != -1:
				_draw_brackets(view.screen_position(target), view.display_radius(target) + 3, Palette.color(&"ui_danger"))


## The path a body at a point with a velocity would take around what
## dominates there, as a dashed conic (gravity of the others left out).
func _draw_path(point: PackedFloat64Array, v: PackedFloat64Array, mass: float, color: Color) -> void:
	var reference: int = simulation.dominant_body(point[0], point[1], point[2])
	if _power.has("flyby_kms"):
		while reference >= 0 and simulation.parent_of(reference) >= 0:
			reference = simulation.parent_of(reference)
	if reference < 0:
		return
	var b: int = reference * 3
	var view_pos: PackedFloat64Array = simulation.state.view_pos
	var view_vel: PackedFloat64Array = simulation.state.view_vel
	var mu: float = Units.G * simulation.state.g_scale * (simulation.state.final_mass(reference) + mass)
	var elements: PackedFloat64Array = Kepler.elements_from_state(
		point[0] - view_pos[b], point[1] - view_pos[b + 1], point[2] - view_pos[b + 2],
		v[0] - view_vel[b], v[1] - view_vel[b + 1], v[2] - view_vel[b + 2], mu, 0.0
	)
	if elements.is_empty():
		return
	var reach: float = maxf(view.camera.viewport_size.length() / view.camera.scale, 3.0 * absf(elements[0]))
	var points: PackedFloat64Array = Kepler.conic_points(elements, PATH_POINTS, reach)
	var center: Vector2 = view.screen_position(reference)
	var path: PackedVector2Array = PackedVector2Array()
	for k: int in PATH_POINTS:
		path.append(center + Vector2(points[k * 3], -points[k * 3 + 1]) * view.camera.scale)
	view.draw_dashed(self, path, elements[0] > 0.0, 0.0, color)


func _draw_brackets(center: Vector2, half: int, color: Color) -> void:
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			var corner: Vector2 = center + Vector2(sx * half, sy * half)
			draw_rect(Rect2(Vector2(minf(corner.x, corner.x - sx * 2), corner.y), Vector2(3, 1)), color)
			draw_rect(Rect2(Vector2(corner.x, minf(corner.y, corner.y - sy * 2)), Vector2(1, 3)), color)
