class_name SpaceView
extends Node2D
## Draws a star system and lets the player move around it: zoom towards the
## cursor (wheel, PageUp/PageDown), pan (middle or right drag, WASD or
## arrows), select (click), follow (F or double-click), home (H) and true
## scale (T). Untouched, bodies show their real orbits; once the system has
## changed, the orbit each body is on right now. Changes spreading at the
## speed of light show as rings: warm for light, violet for gravity, with
## what changed; a removed body that still pulls shows as a faint ghost.
## Reads the simulation; never changes it.

signal selection_changed(index: int)

const HZ_SHADER: Shader = preload("res://assets/shaders/habitable_zone.gdshader")
## The habitable zone is drawn from this many stars at most (the shader's).
const HZ_MAX_STARS: int = 8
const ZOOM_STEP: float = 1.25
const PAN_SPEED: float = 280.0
const DEFAULT_SCALE: float = 100.0
## How fast bodies grow as the camera zooms in past DEFAULT_SCALE: twice
## as big at 300 times the zoom.
const ZOOM_GROWTH: float = 0.12
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
## Faster than this (turns per real second) a disc's spin would only
## flicker, so it is shown turning at this pace instead, the right way round.
const MAX_VISUAL_TURNS: float = 1.0
## Label priority: lower draws first and wins overlaps.
const PRIORITY: Dictionary[CelestialBody.Kind, int] = {
	CelestialBody.Kind.STAR: 0, CelestialBody.Kind.BLACK_HOLE: 0, CelestialBody.Kind.PLANET: 1,
	CelestialBody.Kind.DWARF_PLANET: 2, CelestialBody.Kind.MOON: 3,
}
## How long a collision's flash lasts (real seconds) and how far it spreads
## beyond the body (pixels).
const FLASH_SECONDS: float = 0.6
const FLASH_PIXELS: float = 14.0
## Rings bigger than this (radius, pixels) are drawn only where they cross
## the screen.
const FRONT_ARC_PIXELS: float = 3000.0
## Small bodies as single pixels, by kind.
const PARTICLE_COLORS: Dictionary[Gravity.ParticleKind, StringName] = {
	Gravity.ParticleKind.ASTEROID: &"regolith", Gravity.ParticleKind.ICY: &"ice",
	Gravity.ParticleKind.OORT: &"star_dim", Gravity.ParticleKind.COMET: &"white",
	Gravity.ParticleKind.DEBRIS: &"dust",
}
## A comet grows a tail, pointing away from the star lighting it most,
## inside this distance from it (AU)...
const TAIL_START_AU: float = 5.0
## ...as long as this (AU) at 1 AU, growing as the inverse square of the
## distance, up to TAIL_MAX_AU.
const TAIL_AT_1_AU: float = 0.25
const TAIL_MAX_AU: float = 1.0
## Colours along a tail, from the head out.
const TAIL_COLORS: Array[StringName] = [&"white", &"star_a", &"ice", &"star_mid"]

var simulation: Simulation
var camera: SpaceCamera = SpaceCamera.new()
## Off while a menu is open, so its keys do not also move the camera.
var accepts_input: bool = true
var selected: int = -1
var followed: int = -1
var true_scale: bool = false
## The layers shown (the Tools tab switches them); the others are drawn by
## OverlayView.
var overlays: Dictionary[StringName, bool] = {&"orbits": true, &"fronts": true, &"hz": true}

var _sprites: Array[BodySprite] = []
var _spin: PackedFloat64Array = []
var _screen: PackedVector2Array = []
var _radii: PackedInt32Array = []
var _shown: PackedByteArray = []
var _paths: Array[PackedVector2Array] = []
var _path_times: PackedFloat64Array = []
## What each cached path goes around (what a body circles can change).
var _path_parents: PackedInt32Array = []
var _label_order: PackedInt32Array = []
## Small bodies drawn last frame, by kind, and comets' tails (screen pixels,
## from the head) and heads.
var _drawn: Dictionary[Gravity.ParticleKind, int] = {}
var _tails: Dictionary[int, Vector2] = {}
var _comet_heads: Dictionary[int, Vector2] = {}
## The osculating orbits drawn once the system has changed: an element set
## per body (empty when it circles nothing).
var _elements: Array[PackedFloat64Array] = []
var _changes_seen: int = -1
## Flashes where something collided: {"body", "age"} (real seconds).
var _flashes: Array[Dictionary] = []
var _shake: float = 0.0
var _restores_seen: int = 0
var _orbits_drawn: int = 0
var _hz: Node2D
var _orbits: Node2D
var _particles: Node2D
var _bodies: Node2D
var _overlay: Node2D
var _dragging: bool = false
var _press_position: Vector2 = Vector2.ZERO
var _press_moved: bool = false


func setup(sim: Simulation) -> void:
	simulation = sim
	_hz = _layer("HabitableZone")
	_orbits = _layer("Orbits")
	_particles = _layer("Particles")
	_bodies = _layer("Bodies")
	_overlay = _layer("Overlay")
	_orbits.draw.connect(_draw_orbits)
	_particles.draw.connect(_draw_particles)
	_overlay.draw.connect(_draw_overlay)
	var hz_material: ShaderMaterial = ShaderMaterial.new()
	hz_material.shader = HZ_SHADER
	hz_material.set_shader_parameter(&"edge_color", Palette.color(&"hz"))
	hz_material.set_shader_parameter(&"flux_inner", 1.0 / pow(Astro.habitable_zone_inner(1.0), 2.0))
	hz_material.set_shader_parameter(&"flux_outer", 1.0 / pow(Astro.habitable_zone_outer(1.0), 2.0))
	_hz.material = hz_material
	_hz.draw.connect(_draw_habitable_zone)

	_sync_bodies()
	camera.set_scale_now(DEFAULT_SCALE)
	camera.look_at(simulation.system.x(0), simulation.system.y(0))


func select(index: int) -> void:
	if index == selected:
		return
	selected = index
	selection_changed.emit(index)


func follow(index: int) -> void:
	followed = index


## Adds what is needed to draw bodies added to the system since; after the
## system went back to a snapshot, starts afresh.
func _sync_bodies() -> void:
	var system: StarSystem = simulation.system
	if simulation.restores != _restores_seen:
		_restores_seen = simulation.restores
		for sprite: BodySprite in _sprites:
			_bodies.remove_child(sprite)
			sprite.queue_free()
		_sprites.clear()
		_path_times.fill(NAN)
		if selected >= system.size():
			select(-1)
		if followed >= system.size():
			followed = -1
	var old: int = _sprites.size()
	var count: int = system.size()
	if count == old:
		return
	_screen.resize(count)
	_radii.resize(count)
	_shown.resize(count)
	_paths.resize(count)
	_elements.resize(count)
	_path_times.resize(count)
	_path_parents.resize(count)
	_spin.resize(count)
	for i: int in range(old, count):
		_path_times[i] = NAN
		_shown[i] = 0
		var sprite: BodySprite = BodySprite.new()
		sprite.setup(system.body(i), i, hash(system.body(i).id))
		sprite.visible = false
		_bodies.add_child(sprite)
		_sprites.append(sprite)
	var order: Array[int] = []
	for i: int in count:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return PRIORITY[system.body(a).kind] < PRIORITY[system.body(b).kind])
	_label_order = PackedInt32Array(order)


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


## A flash at a body (a collision or an impact); a big one also shakes the
## screen a little.
func flash(body: int, big: bool) -> void:
	_flashes.append({"body": body, "age": 0.0})
	if big:
		_shake = FLASH_SECONDS * 0.5


func active_flashes() -> int:
	return _flashes.size()


## How many orbits were drawn last frame.
func orbits_drawn() -> int:
	return _orbits_drawn


## How many small bodies of each kind were drawn on screen last frame.
func particles_drawn() -> Dictionary[Gravity.ParticleKind, int]:
	return _drawn


## A comet's tail on screen (from its head, in pixels), or zero when it has
## none.
func comet_tail(particle: int) -> Vector2:
	return _tails.get(particle, Vector2.ZERO)


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
	# Zoomed out, the enlarged discs shrink so they do not crowd each other;
	# zoomed in, they grow (up to twice) to show more of their surface.
	var zoom: float = camera.scale / DEFAULT_SCALE
	var shrink: float = clampf(pow(zoom, 0.3), 0.45, 1.0)
	var grow: float = clampf(pow(zoom, ZOOM_GROWTH), 1.0, 2.0)
	var base: float
	match b.kind:
		CelestialBody.Kind.STAR:
			# The Sun at 10 pixels; dwarfs smaller, giants bigger.
			base = clampf(10.0 * pow(radius_km / Units.SOLAR_RADIUS_KM, 0.25), 3.0, 16.0) * shrink * grow
		CelestialBody.Kind.BLACK_HOLE:
			base = 3.0
		CelestialBody.Kind.PLANET:
			base = maxf(1.5, clampf(1.5 + 1.25 * log(radius_km / 1000.0) / log(2.0), 2.0, 9.0) * shrink) * grow
		_:
			base = clampf(1.2 + 1.0 * log(radius_km / 1000.0) / log(2.0), 1.0, 3.0) * grow
	return mini(roundi(maxf(true_px, base)), 100000)


func _layer(layer_name: String) -> Node2D:
	var node: Node2D = Node2D.new()
	node.name = layer_name
	add_child(node)
	return node


func _process(delta: float) -> void:
	if simulation == null:
		return
	_sync_bodies()
	_pan_with_keys(delta)
	camera.viewport_size = get_viewport_rect().size
	camera.update(delta)
	var system: StarSystem = simulation.system
	if followed != -1:
		camera.look_at(system.x(followed), system.y(followed))
	_layout(delta)
	for item: Dictionary in _flashes:
		item["age"] = float(item["age"]) + delta
	_flashes = _flashes.filter(func(item: Dictionary) -> bool: return float(item["age"]) < FLASH_SECONDS)
	# A little shake, whole pixels only.
	_shake = maxf(0.0, _shake - delta)
	position = Vector2(randi_range(-1, 1), randi_range(-1, 1)) if _shake > 0.0 else Vector2.ZERO
	_hz.queue_redraw()
	_orbits.queue_redraw()
	_particles.queue_redraw()
	_overlay.queue_redraw()


func _layout(delta: float) -> void:
	var system: StarSystem = simulation.system
	for i: int in system.size():
		var b: CelestialBody = system.body(i)
		var p: Vector2 = camera.to_screen(system.x(i), system.y(i)).round()
		var r: int = display_radius(i)
		_screen[i] = p
		_radii[i] = r
		var shown: bool = simulation.is_present(i)
		var parent: int = simulation.parent_of(i)
		if shown and parent != -1:
			shown = _shown[parent] == 1 and p.distance_to(_screen[parent]) > _radii[parent] + r + 2
		_shown[i] = 1 if shown else 0
		var sprite: BodySprite = _sprites[i]
		var on_screen: bool = Rect2(Vector2.ZERO, camera.viewport_size).grow(r * 3 + 8).has_point(p)
		sprite.visible = shown and on_screen
		if not sprite.visible:
			continue
		sprite.position = p
		var star: int = -1 if b.is_star() else simulation.main_star_at(system.x(i), system.y(i), system.z(i))
		var light: Vector2 = Vector2.RIGHT
		if star != -1:
			var towards: Vector2 = camera.to_screen(system.x(star), system.y(star)) - camera.to_screen(system.x(i), system.y(i))
			if towards.length_squared() > 1e-6:
				light = towards.normalized()
		if b.rotation_hours != 0.0:
			var turns_per_second: float = simulation.clock.years_per_second() * HOURS_PER_YEAR / b.rotation_hours
			if simulation.clock.paused or absf(turns_per_second) <= MAX_VISUAL_TURNS:
				_spin[i] = fposmod(simulation.clock.time * HOURS_PER_YEAR / b.rotation_hours, 1.0)
			else:
				_spin[i] = fposmod(_spin[i] + signf(turns_per_second) * MAX_VISUAL_TURNS * delta, 1.0)
		sprite.update_view(r, light, _spin[i])


func _draw_habitable_zone() -> void:
	if not overlays.get(&"hz", true):
		return
	# Every star as it looks from the middle of the screen (its light, or
	# the news that it is gone, may not have got here yet).
	var system: StarSystem = simulation.system
	var view: Rect2 = Rect2(Vector2.ZERO, camera.viewport_size)
	var middle: PackedFloat64Array = camera.to_world(view.get_center())
	var stars: PackedVector2Array = PackedVector2Array()
	var shine: PackedFloat32Array = PackedFloat32Array()
	var brightest: float = 0.0
	for i: int in system.size():
		if not system.body(i).is_star() or stars.size() >= HZ_MAX_STARS:
			continue
		var light: float = simulation.felt_luminosity(i, middle[0], middle[1], 0.0)
		if light <= 0.0:
			continue
		stars.append(camera.to_screen(system.x(i), system.y(i)))
		shine.append(light)
		brightest = maxf(brightest, light)
	if stars.is_empty() or Astro.habitable_zone_outer(brightest) * camera.scale < 4.0:
		return
	var count: int = stars.size()
	stars.resize(HZ_MAX_STARS)
	shine.resize(HZ_MAX_STARS)
	var hz_material: ShaderMaterial = _hz.material as ShaderMaterial
	hz_material.set_shader_parameter(&"star_count", count)
	hz_material.set_shader_parameter(&"stars", stars)
	hz_material.set_shader_parameter(&"luminosity", shine)
	hz_material.set_shader_parameter(&"scale", camera.scale)
	_hz.draw_rect(view, Palette.color(&"white"))


func _draw_orbits() -> void:
	_orbits_drawn = 0
	if not overlays.get(&"orbits", true):
		return
	var system: StarSystem = simulation.system
	var t: float = simulation.clock.time
	var pristine: bool = simulation.is_pristine()
	if not pristine and _changes_seen != simulation.changes:
		_changes_seen = simulation.changes
		_path_times.fill(NAN)
	for i: int in system.size():
		var b: CelestialBody = system.body(i)
		var parent: int = simulation.parent_of(i)
		if _shown[i] == 0 or parent < 0 or (pristine and b.orbit == null):
			continue
		var color: Color = Palette.color(&"ui_border") if i == selected else Palette.color(&"space_indigo_light")
		var a: float
		var period: float
		if pristine:
			a = float(b.orbit.elements_at(t)["a"])
			period = b.orbit.period_years()
		else:
			_elements[i] = simulation.orbit_elements(i)
			if _elements[i].is_empty():
				continue
			a = _elements[i][0]
			period = TAU / _elements[i][2] if a > 0.0 else NAN
		var radius_px: float = absf(a) * camera.scale
		if radius_px < 4.0:
			continue
		if a > 0.0 and radius_px > LOCAL_ARC_PIXELS:
			_draw_local_arc(i, color)
			_orbits_drawn += 1
			continue
		if (
			is_nan(_path_times[i]) or is_nan(period) or absf(t - _path_times[i]) > period * 0.02
			or _path_parents[i] != parent
		):
			var count: int = MOON_ORBIT_POINTS if b.kind == CelestialBody.Kind.MOON else ORBIT_POINTS
			var points: PackedFloat64Array
			if pristine:
				points = b.orbit.path(t, count)
			else:
				var reach: float = maxf(3.0 * absf(a), camera.viewport_size.length() / camera.scale + system.distance(i, parent))
				points = Kepler.conic_points(_elements[i], count, reach)
			var flat: PackedVector2Array = PackedVector2Array()
			for k: int in count:
				flat.append(Vector2(points[k * 3], points[k * 3 + 1]))
			_paths[i] = flat
			_path_times[i] = t
			_path_parents[i] = parent
		var center: Vector2 = camera.to_screen(system.x(parent), system.y(parent))
		var to_screen: Transform2D = Transform2D(Vector2(camera.scale, 0.0), Vector2(0.0, -camera.scale), center)
		draw_dashed(_orbits, to_screen * _paths[i], a > 0.0, 0.0, color)
		_orbits_drawn += 1


## Zoomed in far enough, a whole orbit is too big to draw precisely: draw an
## exact arc of it around the body instead (64-bit, sampled along the motion).
func _draw_local_arc(index: int, color: Color) -> void:
	var system: StarSystem = simulation.system
	var b: CelestialBody = system.body(index)
	if not Rect2(Vector2.ZERO, camera.viewport_size).grow(camera.viewport_size.x).has_point(_screen[index]):
		return
	var parent: int = simulation.parent_of(index)
	var pristine: bool = simulation.is_pristine()
	var relative_speed: float = 0.0
	for k: int in 3:
		relative_speed += pow(system.velocities[index * 3 + k] - system.velocities[parent * 3 + k], 2.0)
	relative_speed = sqrt(relative_speed)
	if relative_speed <= 0.0:
		return
	var pixels_per_year: float = relative_speed * camera.scale
	var period: float = b.orbit.period_years() if pristine else TAU / _elements[index][2]
	var step: float = minf(
		camera.viewport_size.x * 1.5 / pixels_per_year / LOCAL_ARC_SAMPLES,
		period / (2.0 * LOCAL_ARC_SAMPLES + 1.0)
	)
	var t: float = simulation.clock.time
	var px: float = system.x(parent)
	var py: float = system.y(parent)
	var points: PackedVector2Array = PackedVector2Array()
	for k: int in range(-LOCAL_ARC_SAMPLES, LOCAL_ARC_SAMPLES + 1):
		var state: PackedFloat64Array
		if pristine:
			state = b.orbit.state_at(t + k * step)
		else:
			state = Kepler.state_from_element_set(_elements[index], 0, t + k * step)
		points.append(camera.to_screen(px + state[0], py + state[1]))
	# Anchor the dashes to the orbit rather than to the arc, so they stay put.
	draw_dashed(_orbits, points, false, (t - LOCAL_ARC_SAMPLES * step) * pixels_per_year, color)


## Belts and clouds as single pixels; comets with a dithered tail pointing
## away from the star that lights them most, longer the closer they come.
func _draw_particles() -> void:
	var state: NBodyState = simulation.state
	var view: PackedFloat64Array = state.p_view
	var w: float = camera.viewport_size.x
	var h: float = camera.viewport_size.y
	var cx: float = camera.center_x
	var cy: float = camera.center_y
	var scale: float = camera.scale
	var half_w: float = w * 0.5
	var half_h: float = h * 0.5
	var lines: Dictionary[Gravity.ParticleKind, PackedVector2Array] = {}
	for kind: Gravity.ParticleKind in PARTICLE_COLORS:
		lines[kind] = PackedVector2Array()
	_drawn.clear()
	_tails.clear()
	_comet_heads.clear()
	for p: int in state.particle_count():
		if state.p_mode[p] == Gravity.ParticleMode.GONE:
			continue
		var x: float = floorf((view[p * 3] - cx) * scale + half_w)
		var y: float = floorf((cy - view[p * 3 + 1]) * scale + half_h)
		var kind: Gravity.ParticleKind = state.p_kind[p] as Gravity.ParticleKind
		if kind == Gravity.ParticleKind.COMET:
			_draw_comet(p, Vector2(x, y))
		if x < 0.0 or x >= w or y < 0.0 or y >= h:
			continue
		# A one-pixel line through the pixel's centre lights just that pixel.
		var points: PackedVector2Array = lines[kind]
		points.append(Vector2(x, y + 0.5))
		points.append(Vector2(x + 1.0, y + 0.5))
		_drawn[kind] = _drawn.get(kind, 0) + 1
	for kind: Gravity.ParticleKind in lines:
		if not lines[kind].is_empty():
			_particles.draw_multiline(lines[kind], Palette.color(PARTICLE_COLORS[kind]))


func _draw_comet(p: int, head: Vector2) -> void:
	var view: PackedFloat64Array = simulation.state.p_view
	var x: float = view[p * 3]
	var y: float = view[p * 3 + 1]
	var z: float = view[p * 3 + 2]
	_comet_heads[p] = head
	var star: int = simulation.main_star_at(x, y, z)
	if star < 0:
		return
	var dx: float = x - simulation.system.x(star)
	var dy: float = y - simulation.system.y(star)
	var distance: float = sqrt(dx * dx + dy * dy + pow(z - simulation.system.z(star), 2.0))
	if distance >= TAIL_START_AU or distance <= 0.0:
		return
	var length: float = minf(TAIL_MAX_AU, TAIL_AT_1_AU / (distance * distance)) * camera.scale
	var direction: Vector2 = Vector2(dx, -dy).normalized()
	var tail: Vector2 = direction * length
	_tails[p] = tail
	if not Rect2(Vector2.ZERO, camera.viewport_size).grow(length).has_point(head):
		return
	var steps: int = mini(ceili(length), 2000)
	for k: int in steps:
		var along: float = float(k) / maxf(steps, 1)
		# Thinner further out: every pixel near the head, then fewer.
		if along > 0.33 and k % 2 == 1 or along > 0.66 and k % 3 != 0:
			continue
		var color: Color = Palette.color(TAIL_COLORS[mini(int(along * TAIL_COLORS.size()), TAIL_COLORS.size() - 1)])
		_particles.draw_rect(Rect2((head + direction * k).floor(), Vector2.ONE), color)
	_particles.draw_rect(Rect2(head, Vector2(2, 2)), Palette.color(&"white"))


## A dashed line with fixed on-screen dashes, whatever the zoom. Only the
## pieces near the screen are cut into dashes; the rest just advance the
## pattern. start shifts the pattern along the line.
func draw_dashed(canvas: CanvasItem, points: PackedVector2Array, closed: bool, start: float, color: Color) -> void:
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
		Rect2(view.size.x * 0.5 - 170.0, 0.0, 340.0, 52.0),
		Rect2(0.0, view.size.y - 44.0, view.size.x, 44.0),
	]
	_draw_ghosts()
	_draw_flashes()
	if selected != -1 and _shown[selected] == 1:
		_draw_brackets(_screen[selected], _radii[selected] + 3, Palette.color(&"ui_accent"))
	# Names never cover a drawn body (discs, rings or glows).
	for i: int in system.size():
		if _shown[i] == 1 and _sprites[i].visible:
			var extent: float = ceilf(maxf(_radii[i], _sprites[i].extent_px))
			placed.append(Rect2(_screen[i] - Vector2(extent, extent), Vector2(extent, extent) * 2.0))
	_draw_fronts(placed)
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
		var text: String = Format.body_name(b)
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
	# Named comets, after the bodies.
	for name_key: String in simulation.particle_names:
		var p: int = simulation.particle_names[name_key]
		if not _comet_heads.has(p) or simulation.state.p_mode[p] == Gravity.ParticleMode.GONE:
			continue
		var text: String = tr(name_key)
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var at: Vector2 = _comet_heads[p] + Vector2(5.0, 4.0)
		var box: Rect2 = Rect2(at + Vector2(-1, -9), Vector2(width + 2, 12))
		if not view.encloses(box) or _covers(box, placed):
			continue
		placed.append(box)
		_overlay.draw_string(font, at + Vector2.ONE, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.color(&"ui_shadow"))
		_overlay.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.color(&"ui_text_dim"))


## Each flash: a dithered burst of light growing from the body and fading.
func _draw_flashes() -> void:
	for item: Dictionary in _flashes:
		var body: int = item["body"]
		if body >= _screen.size():
			continue
		var t: float = float(item["age"]) / FLASH_SECONDS
		var center: Vector2 = _screen[body]
		var radius: float = _radii[body] + 2.0 + FLASH_PIXELS * t
		var color: Color = Palette.color(&"white" if t < 0.3 else &"accretion" if t < 0.6 else &"star_k")
		var count: int = maxi(12, ceili(radius * 2.0))
		for k: int in count:
			if (k + int(t * 10.0)) % 2 == 0:
				var angle: float = TAU * k / count
				_overlay.draw_rect(Rect2((center + Vector2(cos(angle), sin(angle)) * radius).floor(), Vector2.ONE), color)
		if t < 0.25:
			_overlay.draw_circle(center, _radii[body] + 1.0, Palette.color(&"white"))


## A removed or flung body still pulling where the news has not arrived: a
## faint dotted circle on its old path.
func _draw_ghosts() -> void:
	var color: Color = Palette.color(&"gravity_front_dim")
	for i: int in simulation.system.size():
		if simulation.state.mode[i] != Gravity.Mode.GHOST:
			continue
		var at: Vector2 = camera.to_screen(simulation.system.x(i), simulation.system.y(i)).round()
		if Rect2(Vector2.ZERO, camera.viewport_size).grow(8.0).has_point(at):
			for k: int in 8:
				var angle: float = TAU * k / 8.0
				_overlay.draw_rect(Rect2((at + Vector2(cos(angle), sin(angle)) * 4.0).round(), Vector2.ONE), color)


## Each change spreading at the speed of light: a warm ring for light, a
## violet one for gravity (both, one inside the other, when a star comes or
## goes), labelled with what changed where the ring is nearest the centre of
## the screen.
func _draw_fronts(placed: Array[Rect2]) -> void:
	if not overlays.get(&"fronts", true):
		return
	var view: Rect2 = Rect2(Vector2.ZERO, camera.viewport_size)
	var font: Font = UiTheme.body_font()
	var t: float = simulation.clock.time
	for front: WaveFront in simulation.fronts:
		var center: Vector2 = camera.to_screen(front.origin_x, front.origin_y)
		var radius: float = front.radius_at(t) * camera.scale
		if radius < 2.0 or not _ring_crosses(view, center, radius):
			continue
		var color: Color = Palette.color(&"light_front" if front.light else &"gravity_front")
		_draw_ring(center, radius, color)
		if front.light and front.gravity and radius > 6.0:
			_draw_ring(center, radius - 3.0, Palette.color(&"gravity_front"))
		if front.label_key.is_empty():
			continue
		var changed: String = Format.body_name(simulation.system.body(front.body)) if front.body >= 0 else ""
		var text: String = Format.tr_units(front.label_key, changed)
		if front.label_key == "FRONT_PULSE":
			# How long the light has been travelling.
			text += "  ·  " + Format.duration((t - front.emitted_at) * Units.YEAR_SECONDS)
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.BODY_SIZE).x
		# Along the ring, starting where it is nearest the middle of the
		# screen, the first spot that covers nothing.
		var towards: Vector2 = view.get_center() - center
		var middle: float = towards.angle() if towards.length() > 1.0 else -PI * 0.5
		var step: float = clampf(24.0 / radius, 0.02, 0.5)
		for k: int in 25:
			var angle: float = middle + step * floorf((k + 1) * 0.5) * (1.0 if k % 2 == 0 else -1.0)
			var at: Vector2 = (center + Vector2(cos(angle), sin(angle)) * radius).round()
			var spot: Vector2 = at + Vector2(3.0, -3.0)
			var box: Rect2 = Rect2(spot + Vector2(-1, -9), Vector2(width + 2, 12))
			if not view.encloses(box) or _covers(box, placed):
				continue
			placed.append(box)
			_overlay.draw_string(font, spot + Vector2.ONE, text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.BODY_SIZE, Palette.color(&"ui_shadow"))
			_overlay.draw_string(font, spot, text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.BODY_SIZE, color)
			break


static func _covers(box: Rect2, placed: Array[Rect2]) -> bool:
	for other: Rect2 in placed:
		if other.intersects(box):
			return true
	return false


## True when a circle passes through the rectangle (not wholly inside or
## around it).
static func _ring_crosses(rect: Rect2, center: Vector2, radius: float) -> bool:
	var nearest: Vector2 = center.clamp(rect.position, rect.end)
	var farthest: float = 0.0
	for corner: Vector2 in [rect.position, rect.end, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y)]:
		farthest = maxf(farthest, corner.distance_to(center))
	return center.distance_to(nearest) <= radius and radius <= farthest


## A dashed circle; a huge one only along the part that crosses the screen.
func _draw_ring(center: Vector2, radius: float, color: Color) -> void:
	var view: Rect2 = Rect2(Vector2.ZERO, camera.viewport_size)
	var start: float = 0.0
	var span: float = TAU
	if radius > FRONT_ARC_PIXELS and not view.has_point(center):
		var middle: float = (view.get_center() - center).angle()
		var half: float = 0.0
		for corner: Vector2 in [view.position, view.end, Vector2(view.end.x, 0.0), Vector2(0.0, view.end.y)]:
			half = maxf(half, absf(angle_difference(middle, (corner - center).angle())))
		start = middle - half - 0.01
		span = 2.0 * half + 0.02
	var count: int = clampi(ceili(radius * span / 4.0), 24, 1200)
	var points: PackedVector2Array = PackedVector2Array()
	for k: int in count + (0 if span >= TAU else 1):
		var angle: float = start + span * k / count
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_dashed(_overlay, points, span >= TAU, 0.0, color)


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
