extends SceneTree
## Renders a scene and saves a screenshot, for docs and for reviewing changes.
## Needs a real renderer (not --headless):
##
##   godot --path . --script res://tools/screenshot.gd -- --out=shot.png [--scene=res://...] [--seed=7] [--locale=pt_PT] [--settings=open] [--scale=3]
##
## For the game scene (--scene=res://scenes/space.tscn) also:
##   [--time=2026-10-13T12:00:00] [--select=earth] [--follow=earth] [--zoom=pixels per AU]
##   [--speed=4] [--menu=open] [--true-scale=on] [--wait=frames]
##   [--power=sun_like_star] [--click=x,y] [--drag=x,y] [--hover=x,y]
## For the title screen: [--update=available] shows the update notice as
## when a newer build is out.
## --power chooses a god power; --click uses it at a screen pixel (with
## --drag, dragging from there to the --drag pixel); then the scene runs
## for --wait frames; --hover finally points the mouse at a pixel to show
## the power's preview.
##
## Saves the 640×360 frame, plus an enlarged copy (nearest-neighbour) when
## --scale is above 1.

const DEFAULT_SCENE: String = "res://scenes/main.tscn"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var args: Dictionary[String, String] = _arguments()
	var out: String = args.get("out", "user://screenshot.png")
	InputBindings.apply()
	if args.has("locale"):
		# The App autoload is not a global name yet when this script compiles.
		var settings: GameSettings = root.get_node("App").get(&"settings")
		settings.locale = args["locale"]
		settings.apply()

	var scene: Node = (load(args.get("scene", DEFAULT_SCENE)) as PackedScene).instantiate()
	var sky: StarfieldBackground = scene.get_node_or_null("Sky") as StarfieldBackground
	if sky != null and args.has("seed"):
		sky.sky_seed = int(args["seed"])
	if args.has("time") and "start_time" in scene:
		scene.set(&"start_time", Units.years_from_unix(Time.get_unix_time_from_datetime_string(args["time"])))
	root.add_child(scene)
	if args.get("settings", "") == "open" and scene.has_method(&"open_settings"):
		scene.call(&"open_settings")
	var view: SpaceView = scene.get_node_or_null("View") as SpaceView
	if view != null:
		_set_up_view(scene, view, args)
	var notice: UpdateNotice = scene.get_node_or_null("UI/Root/UpdateNotice") as UpdateNotice
	if notice != null and args.get("update", "") == "available":
		var reply: String = JSON.stringify([{
			"tag_name": "v9.9.9-dev.1", "draft": false, "prerelease": true, "html_url": "",
			"assets": [{"name": "x" + UpdateChecker.asset_suffix(), "size": 1, "browser_download_url": ""}],
		}])
		notice.updater.channel = UpdateChecker.Channel.TESTING
		notice.updater.handle_releases(HTTPRequest.RESULT_SUCCESS, 200, reply)

	# Let the sky finish on its worker thread, then let a few frames render.
	var deadline: int = Time.get_ticks_msec() + 20000
	while sky != null and sky.is_generating() and Time.get_ticks_msec() < deadline:
		await process_frame
	if view != null and args.has("power"):
		await _use_power(scene, args)
	for i: int in int(args.get("wait", "10")):
		await process_frame
	if args.has("hover"):
		_mouse(_pixel(args["hover"]), -1, false)
		for i: int in 2:
			await process_frame
	await RenderingServer.frame_post_draw

	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(out)
	print("Saved %s (%dx%d): %s" % [out, image.get_width(), image.get_height(), error_string(error)])
	var scale: int = int(args.get("scale", "1"))
	if scale > 1:
		image.resize(image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST)
		var big: String = out.get_basename() + "_x%d.png" % scale
		image.save_png(big)
		print("Saved %s" % big)
	quit(0 if error == OK else 1)


func _set_up_view(scene: Node, view: SpaceView, args: Dictionary[String, String]) -> void:
	var system: StarSystem = view.simulation.system
	if args.has("speed"):
		view.simulation.clock.use_preset(args["speed"])
	if args.has("zoom"):
		view.camera.set_scale_now(float(args["zoom"]))
	if args.has("follow"):
		var followed: int = system.index_of(StringName(args["follow"]))
		view.follow(followed)
		view.camera.look_at(system.x(followed), system.y(followed))
	if args.has("select"):
		view.select(system.index_of(StringName(args["select"])))
	if args.get("true-scale", "") == "on":
		view.true_scale = true
	if args.get("menu", "") == "open" and scene.has_method(&"open_menu"):
		scene.call(&"open_menu")


func _use_power(scene: Node, args: Dictionary[String, String]) -> void:
	var toolbar: Toolbar = scene.get_node("UI/Root/Toolbar")
	toolbar.select(0)
	toolbar.choose_power(args["power"])
	await process_frame
	if not args.has("click"):
		return
	var at: Vector2 = _pixel(args["click"])
	_mouse(at, MOUSE_BUTTON_LEFT, true)
	var to: Vector2 = _pixel(args["drag"]) if args.has("drag") else at
	_mouse(to, -1, false)
	await process_frame
	_mouse(to, MOUSE_BUTTON_LEFT, false)
	await process_frame


## A mouse button event (button -1: a motion) at a screen pixel.
func _mouse(at: Vector2, button: int, pressed: bool) -> void:
	if button == -1:
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		root.push_input(motion, true)
		return
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button as MouseButton
	event.position = at
	event.global_position = at
	event.pressed = pressed
	root.push_input(event, true)


func _pixel(text: String) -> Vector2:
	var parts: PackedStringArray = text.split(",")
	return Vector2(float(parts[0]), float(parts[1])) if parts.size() == 2 else Vector2.ZERO


func _arguments() -> Dictionary[String, String]:
	var args: Dictionary[String, String] = {}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--") and argument.contains("="):
			var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
			args[parts[0]] = parts[1]
	return args
