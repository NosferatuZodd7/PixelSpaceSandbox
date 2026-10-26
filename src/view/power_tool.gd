class_name PowerTool
extends Node2D
## Uses the chosen Cosmos power or tool in space: a place power puts a new
## body on a circular orbit where the player clicks (or sweeping through,
## for a flyby) and throws it when they drag; a drag that ends on a body
## throws it straight at that body, and a click on a body drops it onto it.
## Fling throws an existing body by dragging from it (at another body, when
## the drag ends on one); delete removes the body clicked. While following a
## body, drags are throws as seen from it. While aiming, the
## path it would take around what it circles is drawn. The ruler measures
## a drag (in AU, km and light-time; an end on a body follows it), the
## light pulse sends a ring of light from the body clicked. Right click or
## Esc puts the power away.
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
## The ruler's two ends, each {"body": index} or {"point": [x, y, z]}.
var _ruler_ends: Array[Dictionary] = []


func setup(sim: Simulation, space_view: SpaceView) -> void:
	simulation = sim
	view = space_view


func set_power(power: Dictionary) -> void:
	_power = power
	_pressed = false
	_target = -1
	_ruler_ends.clear()
	queue_redraw()


## What the ruler measures now ("1.00 AU  ·  149,597,871 km  ·  light: 8 min
## 19 s"), or empty.
func ruler_text() -> String:
	if _ruler_ends.size() < 2:
		return ""
	var a: PackedFloat64Array = _end_position(_ruler_ends[0])
	var b: PackedFloat64Array = _end_position(_ruler_ends[1])
	var d: float = sqrt(pow(b[0] - a[0], 2.0) + pow(b[1] - a[1], 2.0) + pow(b[2] - a[2], 2.0))
	return "%s  ·  %s  ·  %s" % [
		Format.tr_units("UNIT_AU", Format.significant(d, 3)),
		Format.tr_units("UNIT_KM", Format.number(Units.km_from_au(d))),
		Format.tr_units("RULER_LIGHT", Format.duration(Units.light_time_seconds(d))),
	]


func is_active() -> bool:
	return not _power.is_empty()


func _process(_delta: float) -> void:
	if is_active():
		queue_redraw()
	# Ruler ends on bodies a step back in time may have removed.
	for end: Dictionary in _ruler_ends:
		if end.has("body") and int(end["body"]) >= simulation.system.size():
			_ruler_ends.clear()
			break


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
		if _action() == "ruler":
			_ruler_ends = [_end_at(button.position), _end_at(button.position)]
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
				var aimed: int = _aim_at(button.position, _target)
				var v: PackedFloat64Array = _thrown_velocity(_target, drag, aimed)
				simulation.fling(_target, v[0], v[1], v[2], "FRONT_FLUNG")
				if v.size() > 3 and not is_nan(v[3]):
					simulation.expect_impact(_target, aimed, v[3])
				used.emit(_power, _target)
		"delete":
			var target: int = view.pick(button.position)
			if target != -1:
				simulation.remove_body(target, "FRONT_REMOVED")
				if view.selected == target:
					view.select(-1)
				used.emit(_power, target)
		"ruler":
			_ruler_ends[1] = _end_at(button.position)
		"pulse":
			if _target != -1:
				simulation.light_pulse(_target)
				used.emit(_power, _target)
	_target = -1


## A ruler end: the body under the pixel, else the point in space there.
func _end_at(at: Vector2) -> Dictionary:
	var body: int = view.pick(at)
	if body != -1:
		return {"body": body}
	return {"point": _point_at(at)}


func _end_position(end: Dictionary) -> PackedFloat64Array:
	if end.has("body"):
		var b: int = int(end["body"]) * 3
		return simulation.state.view_pos.slice(b, b + 3)
	return end["point"]


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
	var launch: PackedFloat64Array = _launch(at, drag, body)
	var index: int = simulation.place_body(
		body, launch[0], launch[1], launch[2], launch[3], launch[4], launch[5], "FRONT_PLACED"
	)
	if not is_nan(launch[7]):
		simulation.expect_impact(index, int(launch[6]), launch[7])
	used.emit(_power, index)


## Where a new body starts and how it moves for a press at a pixel and a
## drag: dropped onto the body under a click, thrown at the body the drag
## ends on, else at the press point on a circular orbit (or a flyby), or
## thrown along the drag. [x, y, z, vx, vy, vz, the body aimed at or -1,
## the moment (years) a throw at it should hit, else NAN].
func _launch(at: Vector2, drag: Vector2, body: CelestialBody) -> PackedFloat64Array:
	var target: int = view.pick(at + drag)
	if target != -1 and drag.length() < MIN_DRAG:
		var drop: PackedFloat64Array = _drop_onto(target, at, body)
		drop.append_array([target, NAN])
		return drop
	var point: PackedFloat64Array = _point_at(at)
	var v: PackedFloat64Array = _new_velocity(point, drag, body, target)
	var arrival: float = v[3] if v.size() > 3 else NAN
	return PackedFloat64Array([point[0], point[1], point[2], v[0], v[1], v[2], target, arrival])


## A new body touching a body on the side clicked, falling onto it: they
## collide at once. It falls with its share of the speed they meet at (all
## of it onto a star, almost none for a black hole dropped on a planet).
func _drop_onto(target: int, at: Vector2, body: CelestialBody) -> PackedFloat64Array:
	var b: int = target * 3
	var side: Vector2 = (at - view.screen_position(target)) * Vector2(1, -1)
	side = side.normalized() if side.length() >= 1.0 else Vector2.UP
	var reach: float = (simulation.state.radius[target] + body.radius) * 1.05
	var target_mass: float = simulation.state.final_mass(target)
	var mu: float = Units.G * simulation.state.g_scale * (target_mass + body.mass)
	var fall: float = sqrt(2.0 * mu / reach) * target_mass / maxf(target_mass + body.mass, 1e-30)
	var pos: PackedFloat64Array = simulation.state.view_pos
	var vel: PackedFloat64Array = simulation.state.view_vel
	return PackedFloat64Array([
		pos[b] + side.x * reach, pos[b + 1] + side.y * reach, pos[b + 2],
		vel[b] - side.x * fall, vel[b + 1] - side.y * fall, vel[b + 2],
	])


## The velocity of a new body at a point: on a circular orbit (or a flyby)
## when there is no drag, else along the drag around the same body, or
## straight at the body the drag ends on (then followed by the moment it
## should hit).
func _new_velocity(point: PackedFloat64Array, drag: Vector2, body: CelestialBody, target: int = -1) -> PackedFloat64Array:
	var base: PackedFloat64Array
	var reference: int = simulation.dominant_body(point[0], point[1], point[2])
	if _power.has("flyby_kms"):
		var speed_far: float = Units.au_from_km(float(_power["flyby_kms"])) * Units.YEAR_SECONDS
		base = simulation.flyby_velocity(point[0], point[1], point[2], speed_far)
		while reference >= 0 and simulation.parent_of(reference) >= 0:
			reference = simulation.parent_of(reference)
	else:
		base = simulation.circular_velocity(point[0], point[1], point[2], body.mass)
	if drag.length() < MIN_DRAG:
		return base
	if target != -1:
		var speed: float = _drag_speed(reference, base, drag)
		return simulation.intercept_velocity(target, point[0], point[1], point[2], speed, body.mass, body.radius)
	return _along_drag(reference, base, drag)


## The velocity of a flung body: along the drag, relative to what it circles,
## or straight at the body the drag ends on (target; then followed by the
## moment it should hit, as Simulation.intercept_velocity gives it).
func _thrown_velocity(index: int, drag: Vector2, target: int = -1) -> PackedFloat64Array:
	var current: PackedFloat64Array = simulation.state.view_vel.slice(index * 3, index * 3 + 3)
	if target != -1:
		var speed: float = _drag_speed(simulation.parent_of(index), current, drag)
		var b: int = index * 3
		var pos: PackedFloat64Array = simulation.state.view_pos
		var state: NBodyState = simulation.state
		return simulation.intercept_velocity(target, pos[b], pos[b + 1], pos[b + 2], speed, state.final_mass(index), state.radius[index], index)
	return _along_drag(simulation.parent_of(index), current, drag)


## The body a drag released at a pixel is aimed at (not the thrown one), or -1.
func _aim_at(release: Vector2, thrown: int) -> int:
	var target: int = view.pick(release)
	return target if target != thrown else -1


## The speed a drag means: the reference speed (that of base relative to
## the reference body) times the drag length over DRAG_PIXELS.
func _drag_speed(reference: int, base: PackedFloat64Array, drag: Vector2) -> float:
	var frame: PackedFloat64Array = _velocity_of(reference)
	var speed: float = Vector3(base[0] - frame[0], base[1] - frame[1], base[2] - frame[2]).length()
	if speed <= 0.0:
		speed = 1.0
	return speed * drag.length() / DRAG_PIXELS


## A velocity along the drag (screen y points down, space y up) at the
## speed it means, relative to the body being followed or else to the
## reference body: a throw as the player sees it.
func _along_drag(reference: int, base: PackedFloat64Array, drag: Vector2) -> PackedFloat64Array:
	var speed: float = _drag_speed(reference, base, drag)
	var frame: PackedFloat64Array = _velocity_of(reference)
	if view.followed != -1 and simulation.is_present(view.followed):
		frame = _velocity_of(view.followed)
	var direction: Vector2 = drag.normalized()
	return PackedFloat64Array([frame[0] + direction.x * speed, frame[1] - direction.y * speed, frame[2]])


func _velocity_of(index: int) -> PackedFloat64Array:
	if index < 0:
		return PackedFloat64Array([0.0, 0.0, 0.0])
	return simulation.state.view_vel.slice(index * 3, index * 3 + 3)


func _draw() -> void:
	if not is_active() or simulation == null:
		return
	var accent: Color = Palette.color(&"ui_accent")
	var path_color: Color = Palette.color(&"ui_text")
	match _action():
		"place":
			var at: Vector2 = _press_at if _pressed else _hover
			var drag: Vector2 = (_hover - _press_at) if _pressed else Vector2.ZERO
			var body: CelestialBody = PowerCatalog.make_body(_power, simulation.system)
			var target: int = view.pick(_hover)
			if target != -1:
				# Aimed at a body: it will be hit.
				_draw_brackets(view.screen_position(target), view.display_radius(target) + 3, Palette.color(&"ui_danger"))
				if drag.length() >= MIN_DRAG:
					draw_line(at, view.screen_position(target), Palette.color(&"ui_danger"))
					draw_arc(at, 4.0, 0.0, TAU, 12, accent)
				return
			var launch: PackedFloat64Array = _launch(at, drag, body)
			_draw_path(launch.slice(0, 3), launch.slice(3, 6), body.mass, path_color)
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
				var aimed: int = _aim_at(_hover, target)
				if aimed != -1:
					_draw_brackets(view.screen_position(aimed), view.display_radius(aimed) + 3, Palette.color(&"ui_danger"))
					draw_line(at, view.screen_position(aimed), Palette.color(&"ui_danger"))
					return
				var v: PackedFloat64Array = _thrown_velocity(target, drag)
				var b: int = target * 3
				_draw_path(simulation.state.view_pos.slice(b, b + 3), v, simulation.state.final_mass(target), path_color)
				draw_line(at, at + drag, accent)
		"delete":
			var target: int = view.pick(_hover)
			if target != -1:
				_draw_brackets(view.screen_position(target), view.display_radius(target) + 3, Palette.color(&"ui_danger"))
		"pulse":
			var target: int = view.pick(_hover)
			if target != -1:
				_draw_brackets(view.screen_position(target), view.display_radius(target) + 3, Palette.color(&"light_front"))
		"ruler":
			if _pressed and _ruler_ends.size() == 2:
				_ruler_ends[1] = _end_at(_hover)
			_draw_ruler()


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


func _draw_ruler() -> void:
	if _ruler_ends.size() < 2:
		return
	var a: PackedFloat64Array = _end_position(_ruler_ends[0])
	var b: PackedFloat64Array = _end_position(_ruler_ends[1])
	var from: Vector2 = view.camera.to_screen(a[0], a[1]).round()
	var to: Vector2 = view.camera.to_screen(b[0], b[1]).round()
	var color: Color = Palette.color(&"ui_accent")
	view.draw_dashed(self, PackedVector2Array([from, to]), false, 0.0, color)
	for end: Vector2 in [from, to]:
		draw_rect(Rect2(end - Vector2(1, 1), Vector2(3, 3)), color)
	var text: String = ruler_text()
	var font: Font = UiTheme.body_font()
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.BODY_SIZE).x
	var at: Vector2 = ((from + to) * 0.5 + Vector2(-width * 0.5, -8.0)).round()
	at = at.clamp(Vector2(5, 16), view.camera.viewport_size - Vector2(width + 5.0, 64.0))
	# On a small panel, so the numbers read clearly over orbits and labels.
	var ascent: float = font.get_ascent(UiTheme.BODY_SIZE)
	var box: Rect2 = Rect2(at + Vector2(-4.0, -ascent - 1.0), Vector2(width + 8.0, font.get_height(UiTheme.BODY_SIZE) + 2.0))
	draw_rect(box, Palette.color(&"ui_panel"))
	UiTheme.draw_frame(self, box, Palette.color(&"ui_border"))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.BODY_SIZE, color)


func _draw_brackets(center: Vector2, half: int, color: Color) -> void:
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			var corner: Vector2 = center + Vector2(sx * half, sy * half)
			draw_rect(Rect2(Vector2(minf(corner.x, corner.x - sx * 2), corner.y), Vector2(3, 1)), color)
			draw_rect(Rect2(Vector2(corner.x, minf(corner.y, corner.y - sy * 2)), Vector2(1, 3)), color)
