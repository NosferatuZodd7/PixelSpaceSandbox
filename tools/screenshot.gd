extends SceneTree
## Renders a scene and saves a screenshot, for docs and for reviewing changes.
## Needs a real renderer (not --headless):
##
##   godot --path . --script res://tools/screenshot.gd -- --out=shot.png [--scene=res://...] [--seed=7] [--locale=pt_PT] [--settings=open] [--scale=3]
##
## For the game scene (--scene=res://scenes/space.tscn) also:
##   [--time=2026-10-13T12:00:00] [--select=earth] [--follow=earth] [--zoom=pixels per AU]
##   [--speed=4] [--menu=open] [--true-scale=on] [--wait=frames]
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

	# Let the sky finish on its worker thread, then let a few frames render.
	var deadline: int = Time.get_ticks_msec() + 20000
	while sky != null and sky.is_generating() and Time.get_ticks_msec() < deadline:
		await process_frame
	for i: int in int(args.get("wait", "10")):
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


func _arguments() -> Dictionary[String, String]:
	var args: Dictionary[String, String] = {}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--") and argument.contains("="):
			var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
			args[parts[0]] = parts[1]
	return args
