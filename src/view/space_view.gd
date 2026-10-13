class_name SpaceView
extends Node2D
## Draws a star system and lets the player move around it: zoom towards the
## cursor (wheel, PageUp/PageDown), pan (middle or right drag, WASD or
## arrows), select (click), follow (F or double-click), home (H) and true
## scale (T). Reads the simulation; never changes it.

signal selection_changed(index: int)

const ZOOM_STEP: float = 1.25
const PAN_SPEED: float = 280.0
const DEFAULT_SCALE: float = 100.0
const ORBIT_POINTS: int = 160
const MOON_ORBIT_POINTS: int = 72
const DASH_ON: float = 3.0
const DASH_OFF: float = 3.0
## Orbits larger than this on screen (radius, pixels) are drawn as an exact
## arc around their body instead of a whole loop.
const LOCAL_ARC_PIXELS: float = 2500.0
const LOCAL_ARC_SAMPLES: int = 48
## Hours in a Julian year, for spinning the discs.
const HOURS_PER_YEAR: float = Units.YEAR_DAYS * 24.0
## Label priority: lower draws first and wins overlaps.
const PRIORITY: Dictionary[CelestialBody.Kind, int] = {
	CelestialBody.Kind.STAR: 0, CelestialBody.Kind.PLANET: 1,
	CelestialBody.Kind.DWARF_PLANET: 2, CelestialBody.Kind.MOON: 3,
}

var simulation: Simulation
var camera: SpaceCamera = SpaceCamera.new()
## Off while a menu is open, so its keys do not also move the camera.
var accepts_input: bool = true
var selected: int = -1
var followed: int = -1
var true_scale: bool = false

var _sprites: Array[BodySprite] = []
var _screen: PackedVector2Array = []
var _radii: PackedInt32Array = []
var _shown: PackedByteArray = []
var _paths: Array[PackedVector2Array] = []
var _path_times: PackedFloat64Array = []
var _label_order: PackedInt32Array = []
var _hz: Node2D
var _orbits: Node2D
var _bodies: Node2D
var _overlay: Node2D
var _dragging: bool = false
var _press_position: Vector2 = Vector2.ZERO
var _press_moved: bool = false


func setup(sim: Simulation) -> void:
	simulation = sim
	_hz = _layer("HabitableZone")
	_orbits = _layer("Orbits")
	_bodies = _layer("Bodies")
	_overlay = _layer("Overlay")
	_orbits.draw.connect(_draw_orbits)
	_overlay.draw.connect(_draw_overlay)
	var hz_material: ShaderMaterial = ShaderMaterial.new()
	hz_material.shader = BodySprite.RING_SHADER
	hz_material.set_shader_parameter(&"color", Palette.color(&"hz_dim"))
	hz_material.set_shader_parameter(&"edge_color", Palette.color(&"hz"))
	hz_material.set_shader_parameter(&"edges", true)
	hz_material.set_shader_parameter(&"density_inner", 0.25)
	hz_material.set_shader_parameter(&"density_outer", 0.25)
	_hz.material = hz_material
	_hz.draw.connect(_draw_habitable_zone)

	var system: StarSystem = simulation.system
	var count: int = system.size()
	_screen.resize(count)
	_radii.resize(count)
	_shown.resize(count)
	_paths.resize(count)
	_path_times.resize(count)
	_path_times.fill(NAN)
	for i: int in count:
		var sprite: BodySprite = BodySprite.new()
		sprite.setup(system.body(i), i, hash(system.body(i).id))
		_bodies.add_child(sprite)
		_sprites.append(sprite)
	var order: Array[int] = []
	for i: int in count:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return PRIORITY[system.body(a).kind] < PRIORITY[system.body(b).kind])
	_label_order = PackedInt32Array(order)
	camera.set_scale_now(DEFAULT_SCALE)
	camera.look_at(system.x(0), system.y(0))


func select(index: int) -> void:
	if index == selected:
		return
	selected = index
	selection_changed.emit(index)


func follow(index: int) -> void:
	followed = index


## Centres on the system's star at the default zoom.
func go_home() -> void:
	followed = -1
	camera.set_scale_now(DEFAULT_SCALE)
	camera.look_at(simulation.system.x(0), simulation.system.y(0))


## The body drawn under a screen point, or -1.
func pick(point: Vector2) -> int:
	var best: int = -1
	var best_distance: float = INF
	for i: int in _sprites.size():
		if _shown[i] == 0:
			continue
		var distance: float = point.distance_to(_screen[i])
		if distance <= maxi(_radii[i], 3) + 3 and distance < best_distance:
			best = i
			best_distance = distance
	return best


## Where a body is drawn on screen this frame.
func screen_position(index: int) -> Vector2:
	return _screen[index]


func is_shown(index: int) -> bool:
	return _shown[index] == 1


## The drawn radius in pixels: true size, or bigger so small bodies stay
## visible (unless true scale is on).
func display_radius(index: int) -> int:
	var b: CelestialBody = simulation.system.body(index)
	var true_px: float = b.radius * camera.scale
	if true_scale:
		return maxi(roundi(true_px), 0)
	var radius_km: float = Units.km_from_au(b.radius)
	# Zoomed out, the enlarged discs shrink so they do not crowd each other.
	var shrink: float = clampf(pow(camera.scale / DEFAULT_SCALE, 0.3), 0.45, 1.0)
	var base: float
	match b.kind:
		CelestialBody.Kind.STAR:
			base = 10.0 * shrink
		CelestialBody.Kind.PLANET:
			base = maxf(1.5, clampf(1.5 + 1.25 * log(radius_km / 1000.0) / log(2.0), 2.0, 9.0) * shrink)
		_:
			base = clampf(1.2 + 1.0 * log(radius_km / 1000.0) / log(2.0), 1.0, 3.0)
	return mini(roundi(maxf(true_px, base)), 100000)


func _layer(layer_name: String) -> Node2D:
	var node: Node2D = Node2D.new()
	node.name = layer_name
	add_child(node)
	return node


func _process(delta: float) -> void:
	if simulation == null:
		return
	_pan_with_keys(delta)
	camera.viewport_size = get_viewport_rect().size
	camera.update(delta)
	var system: StarSystem = simulation.system
	if followed != -1:
		camera.look_at(system.x(followed), system.y(followed))
	_layout(delta)
	_hz.queue_redraw()
	_orbits.queue_redraw()
	_overlay.queue_redraw()


func _layout(delta: float) -> void:
	var system: StarSystem = simulation.system
	var spin_rate_limit: float = 0.15
	for i: int in system.size():
		var b: CelestialBody = system.body(i)
		var p: Vector2 = camera.to_screen(system.x(i), system.y(i)).round()
		var r: int = display_radius(i)
		_screen[i] = p
		_radii[i] = r
		var shown: bool = true
		if b.parent != -1:
			shown = _shown[b.parent] == 1 and p.distance_to(_screen[b.parent]) > _radii[b.parent] + r + 2
		_shown[i] = 1 if shown else 0
		var sprite: BodySprite = _sprites[i]
		var on_screen: bool = Rect2(Vector2.ZERO, camera.viewport_size).grow(r * 3 + 8).has_point(p)
		sprite.visible = shown and on_screen
		if not sprite.visible:
			continue
		sprite.position = p
		var star: int = system.host_star(i)
		var light: Vector2 = Vector2.RIGHT
		if star != -1 and star != i:
			var towards: Vector2 = camera.to_screen(system.x(star), system.y(star)) - camera.to_screen(system.x(i), system.y(i))
			if towards.length_squared() > 1e-6:
				light = towards.normalized()
		var spin: float = 0.0
		if b.rotation_hours != 0.0:
			var turns_per_second: float = simulation.clock.years_per_second() * HOURS_PER_YEAR / b.rotation_hours
			if simulation.clock.paused or absf(turns_per_second) * delta < spin_rate_limit:
				spin = fposmod(simulation.clock.time * HOURS_PER_YEAR / b.rotation_hours, 1.0)
		sprite.update_view(r, light, spin)


func _draw_habitable_zone() -> void:
	var system: StarSystem = simulation.system
	var luminosity: float = system.total_luminosity()
	if luminosity <= 0.0:
		return
	var center: Vector2 = _screen[0]
	var inner: float = Astro.habitable_zone_inner(luminosity) * camera.scale
	var outer: float = Astro.habitable_zone_outer(luminosity) * camera.scale
	var view: Rect2 = Rect2(Vector2.ZERO, camera.viewport_size)
	var ring: Rect2 = Rect2(center - Vector2(outer, outer), Vector2(outer, outer) * 2.0)
	var area: Rect2 = view.intersection(ring)
	if not area.has_area() or outer < 4.0:
		return
	# Skip when the whole screen sits inside the hole of the ring.
	var corners: Array[Vector2] = [view.position, view.end, Vector2(view.end.x, 0.0), Vector2(0.0, view.end.y)]
	var farthest: float = 0.0
	for corner: Vector2 in corners:
		farthest = maxf(farthest, corner.distance_to(center))
	if farthest < inner:
		return
	# Close up, the band would cover the whole screen: let its fill fade out.
	var density: float = 0.25 * clampf(1.0 - (outer - inner - 400.0) / 1200.0, 0.0, 1.0)
	var hz_material: ShaderMaterial = _hz.material as ShaderMaterial
	hz_material.set_shader_parameter(&"center", center)
	hz_material.set_shader_parameter(&"inner_radius", inner)
	hz_material.set_shader_parameter(&"outer_radius", outer)
	hz_material.set_shader_parameter(&"density_inner", density)
	hz_material.set_shader_parameter(&"density_outer", density)
	_hz.draw_rect(area, Palette.color(&"white"))


func _draw_orbits() -> void:
	var system: StarSystem = simulation.system
	var t: float = simulation.clock.time
	for i: int in system.size():
		var b: CelestialBody = system.body(i)
		if b.orbit == null or _shown[i] == 0:
			continue
		var color: Color = Palette.color(&"ui_border") if i == selected else Palette.color(&"space_indigo_light")
		var radius_px: float = float(b.orbit.elements_at(t)["a"]) * camera.scale
		if radius_px < 4.0:
			continue
		if radius_px > LOCAL_ARC_PIXELS:
			_draw_local_arc(i, color)
			continue
		var period: float = b.orbit.period_years()
		if is_nan(_path_times[i]) or absf(t - _path_times[i]) > period * 0.02:
			var count: int = MOON_ORBIT_POINTS if b.kind == CelestialBody.Kind.MOON else ORBIT_POINTS
			var points: PackedFloat64Array = b.orbit.path(t, count)
			var flat: PackedVector2Array = PackedVector2Array()
			for k: int in count:
				flat.append(Vector2(points[k * 3], points[k * 3 + 1]))
			_paths[i] = flat
			_path_times[i] = t
		var parent: Vector2 = camera.to_screen(system.x(b.parent), system.y(b.parent))
		var to_screen: Transform2D = Transform2D(Vector2(camera.scale, 0.0), Vector2(0.0, -camera.scale), parent)
		_draw_dashed(_orbits, to_screen * _paths[i], true, 0.0, color)


## Zoomed in far enough, a whole orbit is too big to draw precisely: draw an
## exact arc of it around the body instead (64-bit, sampled along the motion).
func _draw_local_arc(index: int, color: Color) -> void:
	var system: StarSystem = simulation.system
	var b: CelestialBody = system.body(index)
	if not Rect2(Vector2.ZERO, camera.viewport_size).grow(camera.viewport_size.x).has_point(_screen[index]):
		return
	var parent: int = b.parent
	var relative_speed: float = 0.0
	for k: int in 3:
		relative_speed += pow(system.velocities[index * 3 + k] - system.velocities[parent * 3 + k], 2.0)
	relative_speed = sqrt(relative_speed)
	if relative_speed <= 0.0:
		return
	var pixels_per_year: float = relative_speed * camera.scale
	var step: float = minf(
		camera.viewport_size.x * 1.5 / pixels_per_year / LOCAL_ARC_SAMPLES,
		b.orbit.period_years() / (2.0 * LOCAL_ARC_SAMPLES + 1.0)
	)
	var t: float = simulation.clock.time
	var px: float = system.x(parent)
	var py: float = system.y(parent)
	var points: PackedVector2Array = PackedVector2Array()
	for k: int in range(-LOCAL_ARC_SAMPLES, LOCAL_ARC_SAMPLES + 1):
		var state: PackedFloat64Array = b.orbit.state_at(t + k * step)
		points.append(camera.to_screen(px + state[0], py + state[1]))
	# Anchor the dashes to the orbit rather than to the arc, so they stay put.
	_draw_dashed(_orbits, points, false, (t - LOCAL_ARC_SAMPLES * step) * pixels_per_year, color)


## A dashed line with fixed on-screen dashes, whatever the zoom. Only the
## pieces near the screen are cut into dashes; the rest just advance the
## pattern. start shifts the pattern along the line.
func _draw_dashed(canvas: CanvasItem, points: PackedVector2Array, closed: bool, start: float, color: Color) -> void:
	var view: Rect2 = Rect2(Vector2.ZERO, camera.viewport_size).grow(DASH_ON + DASH_OFF)
	var period: float = DASH_ON + DASH_OFF
	var segments: PackedVector2Array = PackedVector2Array()
	var count: int = points.size()
	var along: float = start
	for k: int in (count if closed else count - 1):
		var a: Vector2 = points[k]
		var b: Vector2 = points[(k + 1) % count]
		var length: float = a.distance_to(b)
		if length <= 0.0:
			continue
		var end: float = along + length
		if not _may_cross(view, a, b):
			along = end
			continue
		var at: float = along
		while at < end:
			var phase: float = fposmod(at, period)
			var stop: float = minf(at - phase + (DASH_ON if phase < DASH_ON else period), end)
			if phase < DASH_ON:
				segments.append(a.lerp(b, (at - along) / length))
				segments.append(a.lerp(b, (stop - along) / length))
			at = maxf(stop, at + 1e-4)
		along = end
	if not segments.is_empty():
		canvas.draw_multiline(segments, color)


## False only when the segment is surely outside the rectangle.
static func _may_cross(rect: Rect2, a: Vector2, b: Vector2) -> bool:
	return not (
		(a.x < rect.position.x and b.x < rect.position.x) or (a.x > rect.end.x and b.x > rect.end.x)
		or (a.y < rect.position.y and b.y < rect.position.y) or (a.y > rect.end.y and b.y > rect.end.y)
	)


func _draw_overlay() -> void:
	var system: StarSystem = simulation.system
	var font: Font = UiTheme.body_font()
	var size: int = UiTheme.BODY_SIZE
	var view: Rect2 = Rect2(Vector2.ZERO, camera.viewport_size)
	# Space kept free for the time counter and the toolbar.
	var placed: Array[Rect2] = [
		Rect2(view.size.x * 0.5 - 170.0, 0.0, 340.0, 36.0),
		Rect2(0.0, view.size.y - 44.0, view.size.x, 44.0),
	]
	if selected != -1 and _shown[selected] == 1:
		_draw_brackets(_screen[selected], _radii[selected] + 3, Palette.color(&"ui_accent"))
	# Names never cover a drawn body (discs, rings or glows).
	for i: int in system.size():
		if _shown[i] == 1 and _sprites[i].visible:
			var extent: float = ceilf(maxf(_radii[i], _sprites[i].extent_px))
			placed.append(Rect2(_screen[i] - Vector2(extent, extent), Vector2(extent, extent) * 2.0))
	var order: Array[int] = []
	if selected != -1:
		order.append(selected)
	for i: int in _label_order:
		if i != selected:
			order.append(i)
	for i: int in order:
		if _shown[i] == 0:
			continue
		var b: CelestialBody = system.body(i)
		var text: String = tr(b.name_key)
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var at: Vector2 = _screen[i] + Vector2(ceilf(maxf(_radii[i], _sprites[i].extent_px)) + 3.0, 4.0)
		var box: Rect2 = Rect2(at + Vector2(-1, -9), Vector2(width + 2, 12))
		if not view.encloses(box):
			continue
		var overlaps: bool = false
		for other: Rect2 in placed:
			if other.intersects(box):
				overlaps = true
				break
		if overlaps:
			continue
		placed.append(box)
		var color: Color = Palette.color(&"ui_text")
		if i == selected:
			color = Palette.color(&"ui_accent")
		elif b.kind == CelestialBody.Kind.MOON or b.kind == CelestialBody.Kind.DWARF_PLANET:
			color = Palette.color(&"ui_text_dim")
		_overlay.draw_string(font, at + Vector2.ONE, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.color(&"ui_shadow"))
		_overlay.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Pixel corner brackets around a body: a 3-pixel arm each way at every corner.
func _draw_brackets(center: Vector2, half: int, color: Color) -> void:
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			var corner: Vector2 = center + Vector2(sx * half, sy * half)
			_overlay.draw_rect(Rect2(Vector2(minf(corner.x, corner.x - sx * 2), corner.y), Vector2(3, 1)), color)
			_overlay.draw_rect(Rect2(Vector2(corner.x, minf(corner.y, corner.y - sy * 2)), Vector2(1, 3)), color)


func _pan_with_keys(delta: float) -> void:
	if not accepts_input:
		return
	var direction: Vector2 = Input.get_vector(&"pan_left", &"pan_right", &"pan_up", &"pan_down")
	if direction != Vector2.ZERO:
		followed = -1
		camera.pan_pixels(-direction * PAN_SPEED * delta)


func _unhandled_input(event: InputEvent) -> void:
	if simulation == null or not accepts_input:
		return
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button != null:
		_mouse_button(mouse_button)
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		if _dragging:
			followed = -1
			camera.pan_pixels(motion.relative)
			get_viewport().set_input_as_handled()
		elif motion.button_mask & MOUSE_BUTTON_MASK_LEFT and motion.position.distance_to(_press_position) > 3.0:
			_press_moved = true
		return
	if event.is_action_pressed(&"zoom_in"):
		_zoom(camera.viewport_size * 0.5, ZOOM_STEP)
	elif event.is_action_pressed(&"zoom_out"):
		_zoom(camera.viewport_size * 0.5, 1.0 / ZOOM_STEP)
	elif event.is_action_pressed(&"follow"):
		follow(-1 if followed == selected else selected)
	elif event.is_action_pressed(&"home_view"):
		go_home()
	elif event.is_action_pressed(&"true_scale"):
		true_scale = not true_scale
	else:
		return
	get_viewport().set_input_as_handled()


func _mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				var factor: float = ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP
				_zoom(event.position, factor)
		MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press_position = event.position
				_press_moved = false
				if event.double_click:
					var target: int = pick(event.position)
					if target != -1:
						select(target)
						follow(target)
			elif not _press_moved:
				select(pick(event.position))
		_:
			return
	get_viewport().set_input_as_handled()


func _zoom(anchor: Vector2, factor: float) -> void:
	# While following a body, zoom on it rather than on the cursor.
	camera.zoom_at(camera.viewport_size * 0.5 if followed != -1 else anchor, factor)
