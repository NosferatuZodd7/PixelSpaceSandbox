extends SceneTree
## Measures the whole game screen — simulation, drawing commands and
## interface — on the Solar System with its small bodies, untouched and
## then with a second star (so everything runs on gravity), at one day and
## one year per second. Needs a renderer (not --headless):
##
##   godot --path . --script res://tools/game_benchmark.gd -- [--frames=600]
##
## Prints the mean and 95th percentile of the time between frames (wall
## clock: simulation, drawing and rendering together) and the frames per
## second. Vertical sync is turned off so frames are not held back.

const SPACE_SCENE: String = "res://scenes/space.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var frames: int = 600
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--frames="):
			frames = maxi(int(argument.trim_prefix("--frames=")), 10)
	InputBindings.apply()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var screen: Node = (load(SPACE_SCENE) as PackedScene).instantiate()
	screen.set(&"start_time", Units.years_from_unix(Time.get_unix_time_from_datetime_string("2026-10-25T12:00:00")))
	root.add_child(screen)
	for i: int in 30:
		await process_frame
	var simulation: Simulation = screen.get(&"simulation")
	for case: String in ["untouched, 1 day/s", "second star, 1 day/s", "second star, 1 year/s"]:
		if case.begins_with("second star") and simulation.is_pristine():
			var star: CelestialBody = CelestialBody.new()
			star.id = &"benchmark_star"
			star.name_key = "PLACED_STAR"
			star.name_number = 1
			star.kind = CelestialBody.Kind.STAR
			star.mass = 1.0
			star.radius = Units.au_from_km(695700.0)
			star.luminosity = 1.0
			star.temperature = 5772.0
			star.look = &"sun"
			var v: PackedFloat64Array = simulation.circular_velocity(0.0, 3.0, 0.0, 1.0)
			simulation.place_body(star, 0.0, 3.0, 0.0, v[0], v[1], v[2], "FRONT_PLACED")
		simulation.clock.use_preset("7" if case.ends_with("year/s") else "4")
		var times: PackedFloat64Array = []
		var started: int = Time.get_ticks_usec()
		var last: int = started
		for i: int in frames:
			await process_frame
			var now: int = Time.get_ticks_usec()
			times.append((now - last) / 1000.0)
			last = now
		var seconds: float = (Time.get_ticks_usec() - started) / 1e6
		times.sort()
		var total: float = 0.0
		for t: float in times:
			total += t
		print("%s: frame %.2f ms mean, %.2f ms p95; %.1f frames per second; %d small bodies drawn; simulation lagging: %s" % [
			case, total / times.size(), times[int(times.size() * 0.95)], frames / seconds,
			(screen.get_node("View") as SpaceView).particles_drawn().values().reduce(func(a: int, b: int) -> int: return a + b, 0),
			simulation.lagging,
		])
	quit()
