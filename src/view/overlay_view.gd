class_name OverlayView
extends Node2D
## The Tools tab's overlays beyond what the space view draws itself:
## dithered maps of the gravity field and of temperature; Hill spheres and
## the Roche limits around bodies; the Lagrange points of the selected body
## and what it circles; and ghost trajectories — after a change, the path
## each body would have followed without it, next to its real one, with the
## moment the news reached it (where the paths part) marked. Reads the
## simulation and the view's camera; never changes them.

const FIELD_SHADER: Shader = preload("res://assets/shaders/field.gdshader")
const FIELD_SOURCES: int = 16
## Points kept along each trail, one every TRAIL_SECONDS of play.
const TRAIL_POINTS: int = 240
const TRAIL_SECONDS: float = 1.0 / 30.0
## A typical moon's density (kg/m³), for the Roche limits drawn around bodies.
const MOON_DENSITY: float = 3000.0
const GRAVITY_BANDS: Array[StringName] = [&"nebula_2", &"nebula_3", &"gravity_front_dim", &"gravity_front", &"white"]
const TEMPERATURE_BANDS: Array[StringName] = [&"ice", &"ocean_shallow", &"grass", &"desert", &"lava"]

var simulation: Simulation
var view: SpaceView

var _gravity: Node2D
var _temperature: Node2D
var _lines: Node2D
var _drawn: Dictionary[StringName, int] = {}
## Trails as x, y, z triples per body (real and would-be), for the
## alternative they were recorded from.
var _real: Array[PackedFloat64Array] = []
var _would: Array[PackedFloat64Array] = []
var _split: Dictionary[int, PackedFloat64Array] = {}
var _recorded_for: NBodyState = null
var _since_sample: float = 0.0


func setup(sim: Simulation, space_view: SpaceView) -> void:
	simulation = sim
	view = space_view
	_gravity = _field_layer(0, GRAVITY_BANDS)
	_temperature = _field_layer(1, TEMPERATURE_BANDS)
	_lines = Node2D.new()
	add_child(_lines)
	_lines.draw.connect(_draw_lines)


## How many things an overlay drew last frame (circles, points, trails).
func drawn(overlay: StringName) -> int:
	return _drawn.get(overlay, 0)


func _on(overlay: StringName) -> bool:
	return view.overlays.get(overlay, false)


func _process(delta: float) -> void:
	if simulation == null:
		return
	_record_trails(delta)
	_gravity.visible = _on(&"gravity")
	_temperature.visible = _on(&"temperature")
	if _gravity.visible:
		_gravity.queue_redraw()
	if _temperature.visible:
		_temperature.queue_redraw()
	_lines.queue_redraw()


func _field_layer(mode: int, bands: Array[StringName]) -> Node2D:
	var node: Node2D = Node2D.new()
	var field: ShaderMaterial = ShaderMaterial.new()
	field.shader = FIELD_SHADER
	field.set_shader_parameter(&"mode", mode)
	for k: int in bands.size():
		field.set_shader_parameter(StringName("band_%d" % k), Palette.color(bands[k]))
	node.material = field
	node.visible = false
	node.draw.connect(_draw_field.bind(node, mode))
	add_child(node)
	return node


## The field from the heaviest bodies (gravity) or every star as it looks
## from the middle of the screen (temperature).
func _draw_field(node: Node2D, mode: int) -> void:
	var system: StarSystem = simulation.system
	var camera: SpaceCamera = view.camera
	var middle: PackedFloat64Array = camera.to_world(camera.viewport_size * 0.5)
	var candidates: Array[Vector2] = []
	for i: int in system.size():
		if not simulation.is_present(i):
			continue
		var amount: float
		if mode == 0:
			amount = simulation.state.final_mass(i)
		elif system.body(i).is_star():
			amount = simulation.felt_luminosity(i, middle[0], middle[1], 0.0)
		else:
			continue
		if amount > 0.0:
			candidates.append(Vector2(amount, i))
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)
	var sources: PackedVector2Array = PackedVector2Array()
	var strength: PackedFloat32Array = PackedFloat32Array()
	for entry: Vector2 in candidates.slice(0, FIELD_SOURCES):
		var i: int = int(entry.y)
		sources.append(camera.to_screen(system.x(i), system.y(i)))
		strength.append(entry.x)
	var count: int = sources.size()
	_drawn[&"gravity" if mode == 0 else &"temperature"] = count
	if count == 0:
		return
	sources.resize(FIELD_SOURCES)
	strength.resize(FIELD_SOURCES)
	var field: ShaderMaterial = node.material as ShaderMaterial
	field.set_shader_parameter(&"count", count)
	field.set_shader_parameter(&"sources", sources)
	field.set_shader_parameter(&"strength", strength)
	field.set_shader_parameter(&"scale", camera.scale)
	node.draw_rect(Rect2(Vector2.ZERO, camera.viewport_size), Palette.color(&"white"))


func _draw_lines() -> void:
	_drawn[&"hill"] = 0
	_drawn[&"lagrange"] = 0
	_drawn[&"ghosts"] = 0
	if _on(&"hill"):
		_draw_hill_and_roche()
	if _on(&"lagrange"):
		_draw_lagrange()
	if _on(&"ghosts"):
		_draw_trails()


## Each body's Hill sphere (dashed) and, where it shows outside the drawn
## disc, the Roche limit for a typical moon (in red).
func _draw_hill_and_roche() -> void:
	var system: StarSystem = simulation.system
	var camera: SpaceCamera = view.camera
	var screen: Rect2 = Rect2(Vector2.ZERO, camera.viewport_size)
	for i: int in system.size():
		if not view.is_shown(i):
			continue
		var center: Vector2 = view.screen_position(i)
		var hill: float = simulation.hill_radius(i) * camera.scale
		if hill < INF and hill > view.display_radius(i) + 3.0 and _circle_visible(screen, center, hill):
			_dashed_circle(center, hill, Palette.color(&"ui_text_dim"))
			_drawn[&"hill"] += 1
		var b: CelestialBody = system.body(i)
		if b.radius <= 0.0:
			continue
		var radius_m: float = Units.km_from_au(b.radius) * 1000.0
		var density: float = Units.kg_from_solar_masses(simulation.state.final_mass(i)) / (4.0 / 3.0 * PI * pow(radius_m, 3.0))
		var roche: float = b.radius * pow(Gravity.TIDAL_FACTOR * density / MOON_DENSITY, 1.0 / 3.0) * camera.scale
		if roche > view.display_radius(i) + 2.0 and _circle_visible(screen, center, roche):
			_dashed_circle(center, roche, Palette.color(&"ui_danger"))


## L1 to L5 of the selected body and what it circles, as small crosses.
func _draw_lagrange() -> void:
	if view.selected == -1:
		return
	var points: PackedFloat64Array = simulation.lagrange_points(view.selected)
	var font: Font = UiTheme.body_font()
	var color: Color = Palette.color(&"ui_accent")
	for k: int in range(0, points.size(), 3):
		var at: Vector2 = view.camera.to_screen(points[k], points[k + 1]).round()
		_drawn[&"lagrange"] += 1
		_lines.draw_rect(Rect2(at - Vector2(2, 0), Vector2(5, 1)), color)
		_lines.draw_rect(Rect2(at - Vector2(0, 2), Vector2(1, 5)), color)
		_lines.draw_string(font, at + Vector2(4, -3), "L%d" % _drawn[&"lagrange"], HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.BODY_SIZE, color)


func _record_trails(delta: float) -> void:
	var alternative: NBodyState = simulation.alternative
	if alternative != _recorded_for:
		_recorded_for = alternative
		_real.clear()
		_would.clear()
		_split.clear()
		_since_sample = TRAIL_SECONDS
	if alternative == null or simulation.clock.paused:
		return
	_since_sample += delta
	if _since_sample < TRAIL_SECONDS:
		return
	_since_sample = 0.0
	var count: int = alternative.body_count()
	_real.resize(count)
	_would.resize(count)
	var front: WaveFront = simulation.alternative_front
	for i: int in count:
		if alternative.mode[i] == Gravity.Mode.GONE:
			continue
		var b: int = i * 3
		_add_point(_would, i, alternative.view_pos, b)
		if simulation.is_present(i):
			_add_point(_real, i, simulation.state.view_pos, b)
			var real: PackedFloat64Array = simulation.state.view_pos.slice(b, b + 3)
			var heard: bool = front == null or not simulation.fronts.has(front) or front.has_reached(real[0], real[1], real[2], simulation.clock.time)
			if heard and not _split.has(i):
				_split[i] = real


func _add_point(trails: Array[PackedFloat64Array], i: int, positions: PackedFloat64Array, b: int) -> void:
	var trail: PackedFloat64Array = trails[i]
	trail.append_array(positions.slice(b, b + 3))
	if trail.size() > TRAIL_POINTS * 3:
		trail = trail.slice(3)
	trails[i] = trail


## Real paths dotted in the interface colour, the would-be ones dashed in
## violet, and a ring where the news arrived.
func _draw_trails() -> void:
	var camera: SpaceCamera = view.camera
	for i: int in _would.size():
		var would: PackedVector2Array = _project(_would[i])
		if would.size() >= 2:
			view.draw_dashed(_lines, would, false, 0.0, Palette.color(&"gravity_front"))
			_drawn[&"ghosts"] += 1
		if i < _real.size():
			var real: PackedVector2Array = _project(_real[i])
			for k: int in range(0, real.size(), 2):
				_lines.draw_rect(Rect2(real[k].floor(), Vector2.ONE), Palette.color(&"ui_text"))
		if _split.has(i):
			var at: Vector2 = camera.to_screen(_split[i][0], _split[i][1])
			_lines.draw_arc(at, 3.0, 0.0, TAU, 12, Palette.color(&"ui_accent"))


func _project(trail: PackedFloat64Array) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for k: int in range(0, trail.size(), 3):
		points.append(view.camera.to_screen(trail[k], trail[k + 1]))
	return points


func _dashed_circle(center: Vector2, radius: float, color: Color) -> void:
	var count: int = clampi(ceili(radius * 0.5), 16, 720)
	var points: PackedVector2Array = PackedVector2Array()
	for k: int in count:
		var angle: float = TAU * k / count
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	view.draw_dashed(_lines, points, true, 0.0, color)


static func _circle_visible(screen: Rect2, center: Vector2, radius: float) -> bool:
	return radius < 20000.0 and screen.grow(radius).has_point(center)
