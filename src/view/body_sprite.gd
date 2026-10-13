class_name BodySprite
extends Node2D
## Draws one body: its spinning, lit pixel disc; a dithered glow for stars;
## and dithered rings, the far half behind the disc and the near half in
## front of it.

const DISC_SHADER: Shader = preload("res://assets/shaders/planet_disc.gdshader")
const RING_SHADER: Shader = preload("res://assets/shaders/dither_ring.gdshader")

## Star colours by effective temperature (K), hottest first.
const STAR_COLORS: Array[Array] = [
	[30000.0, &"star_o"], [10000.0, &"star_b"], [7500.0, &"star_a"], [6000.0, &"star_f"],
	[5200.0, &"star_g"], [3700.0, &"star_k"], [0.0, &"star_m"],
]

var index: int = -1
var radius_px: int = 2
## How far from the centre the drawing reaches (disc, rings or glow), in pixels.
var extent_px: float = 2.0

var _body: CelestialBody
var _map: ImageTexture
var _disc: ShaderMaterial
var _glow: Node2D
var _rings: Array[Node2D] = []
var _ring_rotation: float = 0.0
var _ring_flatten: float = 1.0
var _ring_front: int = 1


static func star_color_id(temperature: float) -> StringName:
	for entry: Array in STAR_COLORS:
		if temperature >= float(entry[0]):
			return entry[1]
	return &"star_m"


func setup(body: CelestialBody, body_index: int, map_seed: int) -> void:
	_body = body
	index = body_index
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map = ImageTexture.create_from_image(SurfaceMaps.generate(body.look, map_seed))
	_disc = ShaderMaterial.new()
	_disc.shader = DISC_SHADER
	_disc.set_shader_parameter(&"night_color", Palette.color(&"void"))
	_disc.set_shader_parameter(&"lit", not body.is_star())
	material = _disc
	if body.is_star():
		_glow = _ring_node(Palette.color(star_color_id(body.temperature)), true)
	if not body.rings.is_empty():
		_orient_rings()
		for ring: Dictionary in body.rings:
			var color: Color = Palette.color(ring["color"])
			var back: Node2D = _ring_node(color, true)
			back.set_meta(&"ring", ring)
			back.set_meta(&"side", -_ring_front)
			var front: Node2D = _ring_node(color, false)
			front.set_meta(&"ring", ring)
			front.set_meta(&"side", _ring_front)
			_rings.append(back)
			_rings.append(front)


## Updates the drawing for this frame. light_dir points to the star on screen.
func update_view(new_radius: int, light_dir: Vector2, spin: float) -> void:
	radius_px = new_radius
	extent_px = radius_px
	_disc.set_shader_parameter(&"light_dir", light_dir)
	_disc.set_shader_parameter(&"spin", spin)
	if _glow != null:
		var glow: ShaderMaterial = _glow.material as ShaderMaterial
		glow.set_shader_parameter(&"inner_radius", radius_px + 0.5)
		glow.set_shader_parameter(&"outer_radius", radius_px * 2.0 + 4.0)
		glow.set_shader_parameter(&"density_inner", 0.5)
		glow.set_shader_parameter(&"density_outer", 0.0)
		_glow.set_meta(&"extent", radius_px * 2.0 + 5.0)
		_glow.queue_redraw()
		extent_px = radius_px * 2.0 + 4.0
	if not _rings.is_empty():
		# Rings scale with the drawn planet, which may be larger than life.
		var pixels_per_au: float = radius_px / _body.radius
		for node: Node2D in _rings:
			var ring: Dictionary = node.get_meta(&"ring")
			var ring_material: ShaderMaterial = node.material as ShaderMaterial
			var outer: float = float(ring["outer"]) * pixels_per_au
			ring_material.set_shader_parameter(&"inner_radius", float(ring["inner"]) * pixels_per_au)
			ring_material.set_shader_parameter(&"outer_radius", outer)
			ring_material.set_shader_parameter(&"density_inner", float(ring["density"]))
			ring_material.set_shader_parameter(&"density_outer", float(ring["density"]))
			ring_material.set_shader_parameter(&"rotation", _ring_rotation)
			ring_material.set_shader_parameter(&"flatten", _ring_flatten)
			ring_material.set_shader_parameter(&"half_side", int(node.get_meta(&"side")))
			node.set_meta(&"extent", outer + 1.0)
			node.queue_redraw()
			extent_px = maxf(extent_px, outer)
	queue_redraw()


func _draw() -> void:
	var size: float = radius_px * 2 + 1
	draw_texture_rect(_map, Rect2(Vector2(-radius_px, -radius_px), Vector2(size, size)), false)


## A child that fills a square with a dither-ring material.
func _ring_node(color: Color, behind: bool) -> Node2D:
	var node: Node2D = Node2D.new()
	var ring_material: ShaderMaterial = ShaderMaterial.new()
	ring_material.shader = RING_SHADER
	ring_material.set_shader_parameter(&"color", color)
	ring_material.set_shader_parameter(&"edge_color", color)
	node.material = ring_material
	node.show_behind_parent = behind
	node.set_meta(&"extent", 1.0)
	node.draw.connect(func() -> void:
		var extent: float = float(node.get_meta(&"extent"))
		node.draw_rect(Rect2(Vector2(-extent, -extent), Vector2(extent, extent) * 2.0), Palette.color(&"white"))
	)
	add_child(node)
	return node


## The ring plane is the planet's equator. Seen from above the ecliptic it is
## an ellipse; its near half (towards the viewer) covers the planet.
func _orient_rings() -> void:
	var frame: PackedFloat64Array = KeplerOrbit.equator_frame(_body.pole_ra_deg, _body.pole_dec_deg)
	var node_screen: Vector2 = Vector2(frame[0], -frame[1])
	var up_screen: Vector2 = Vector2(frame[3], -frame[4])
	_ring_rotation = node_screen.angle()
	_ring_flatten = absf(frame[8])
	# The shader's +y axis is node_screen turned a quarter turn; the near half
	# is the one along the frame's y axis (which points towards the viewer).
	var shader_y: Vector2 = Vector2(-sin(_ring_rotation), cos(_ring_rotation))
	_ring_front = 1 if shader_y.dot(up_screen) >= 0.0 else -1
