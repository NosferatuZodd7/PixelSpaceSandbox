extends TestCase
## The camera: exact conversions between space and screen at any zoom, and
## zooming that keeps the point under the cursor in place.


func _camera(x: float, y: float, scale: float) -> SpaceCamera:
	var camera: SpaceCamera = SpaceCamera.new()
	camera.look_at(x, y)
	camera.set_scale_now(scale)
	return camera


func test_screen_and_space_round_trip() -> void:
	var camera: SpaceCamera = _camera(1.5, -2.0, 120.0)
	for point: Vector2 in [Vector2(0, 0), Vector2(320, 180), Vector2(17, 301), Vector2(640, 360)]:
		var world: PackedFloat64Array = camera.to_world(point)
		var back: Vector2 = camera.to_screen(world[0], world[1])
		assert_almost_eq(back.x, point.x, 1e-3, "x of %s" % point)
		assert_almost_eq(back.y, point.y, 1e-3, "y of %s" % point)
	assert_eq(camera.to_screen(1.5, -2.0), Vector2(320, 180), "the centre is the middle of the screen")
	assert_true(camera.to_screen(1.5, -1.0).y < 180.0, "north is up")


func test_zoom_keeps_the_point_under_the_cursor() -> void:
	var camera: SpaceCamera = _camera(0.0, 0.0, 100.0)
	var cursor: Vector2 = Vector2(500, 60)
	var world: PackedFloat64Array = camera.to_world(cursor)
	camera.zoom_at(cursor, 4.0)
	assert_true(camera.is_zooming(), "eases in")
	camera.update(10.0)
	assert_eq(camera.scale, 400.0, "reached the target zoom")
	assert_false(camera.is_zooming(), "done")
	var after: Vector2 = camera.to_screen(world[0], world[1])
	assert_almost_eq(after.x, cursor.x, 0.01, "same x under the cursor")
	assert_almost_eq(after.y, cursor.y, 0.01, "same y under the cursor")


func test_zoom_is_limited() -> void:
	var camera: SpaceCamera = _camera(0.0, 0.0, 100.0)
	camera.zoom_at(Vector2(320, 180), 1e30)
	assert_eq(camera.target_scale, SpaceCamera.MAX_SCALE)
	camera.zoom_at(Vector2(320, 180), 1e-60)
	assert_eq(camera.target_scale, SpaceCamera.MIN_SCALE)


func test_precise_far_from_the_star() -> void:
	# Neptune's distance, zoomed in to 15 km per pixel: one kilometre is still exact.
	var camera: SpaceCamera = _camera(30.0, 0.0, 1.0e7)
	var near: Vector2 = camera.to_screen(30.0 + 1.0e-6, 0.0)
	assert_almost_eq(near.x, 330.0, 1e-3, "a millionth of an AU is 10 pixels")


func test_pan_moves_space_with_the_mouse() -> void:
	var camera: SpaceCamera = _camera(0.0, 0.0, 50.0)
	camera.pan_pixels(Vector2(25, -10))
	assert_almost_eq(camera.center_x, -0.5, 1e-12, "dragging right moves the view left")
	assert_almost_eq(camera.center_y, -0.2, 1e-12, "dragging up moves the view down")
