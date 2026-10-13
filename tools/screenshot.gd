extends SceneTree
## Renders a scene and saves a screenshot, for docs and for reviewing changes.
## Needs a real renderer (not --headless):
##
##   godot --path . --script res://tools/screenshot.gd -- --out=shot.png [--scene=res://...] [--seed=7] [--locale=pt_PT] [--palette=on|off] [--scale=3]
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
		TranslationServer.set_locale(args["locale"])

	var scene: Node = (load(args.get("scene", DEFAULT_SCENE)) as PackedScene).instantiate()
	var sky: StarfieldBackground = scene.get_node_or_null("Sky") as StarfieldBackground
	if sky != null and args.has("seed"):
		sky.sky_seed = int(args["seed"])
	root.add_child(scene)
	var palette: Control = scene.get_node_or_null("UI/Root/PaletteStrip") as Control
	if palette != null and args.has("palette"):
		palette.visible = args["palette"] == "on"

	# Let the sky finish on its worker thread, then let a few frames render.
	var deadline: int = Time.get_ticks_msec() + 20000
	while sky != null and sky.is_generating() and Time.get_ticks_msec() < deadline:
		await process_frame
	for i: int in 10:
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


func _arguments() -> Dictionary[String, String]:
	var args: Dictionary[String, String] = {}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--") and argument.contains("="):
			var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
			args[parts[0]] = parts[1]
	return args
