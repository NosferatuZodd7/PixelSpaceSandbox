extends SceneTree
## Measures the gravity simulation on the milestone 2 benchmark scene
## (src/sim/benchmark_scenario.gd), without drawing anything:
##
##   godot --headless --path . --script res://tools/benchmark.gd -- [--kernel=script|native|both]
##       [--frames=600] [--repeats=3] [--awake=0.1] [--seed=2026]
##
## Each repeat runs the same scene for a number of frames at ×1,000,000
## (one frame = 1/60 s of play) and times every frame's simulation work.
## Prints the mean, median, 95th percentile and worst frame, how well the
## bodies' total momentum is kept, and, when both kernels run, how far
## apart their results end up. (Measure memory from outside, e.g. with
## /usr/bin/time -v.) In an exported game, use `-- --gravity-self-test`.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: Dictionary[String, String] = _arguments()
	var choice: String = args.get("kernel", "both")
	var kernels: PackedStringArray = ["script", "native"] if choice == "both" else PackedStringArray([choice])
	var frames: int = int(args.get("frames", "600"))
	var repeats: int = int(args.get("repeats", "3"))
	var awake: float = float(args.get("awake", "0.1"))
	var seed_value: int = int(args.get("seed", "2026"))
	if not choice in ["script", "native", "both"] or frames < 1 or repeats < 1 or awake < 0.0 or awake > 1.0:
		printerr("Usage: --kernel=script|native|both --frames>=1 --repeats>=1 --awake=0..1 --seed=N")
		quit(2)
		return
	print("Benchmark: %d stars, %d planets, %d moons, %d particles (%d%% awake), %d fronts, x%s, %d frames x %d repeats" % [
		BenchmarkScenario.STARS, BenchmarkScenario.PLANETS, BenchmarkScenario.MOONS, BenchmarkScenario.PARTICLES,
		roundi(awake * 100.0), BenchmarkScenario.FRONTS, String.num(BenchmarkScenario.SPEED), frames, repeats,
	])
	var failed: bool = false
	var finals: Dictionary[String, NBodyState] = {}
	for kernel_name: String in kernels:
		if Gravity.kernel_named(kernel_name) == null:
			print("%s: NOT RUN (the native kernel is not loaded)" % kernel_name)
			failed = true
			continue
		for r: int in repeats:
			var s: NBodyState = BenchmarkScenario.build(seed_value, awake)
			var momentum_start: Vector3 = _momentum(s)
			var run: Dictionary = BenchmarkScenario.run(Gravity.kernel_named(kernel_name), s, frames)
			var stats: Dictionary = BenchmarkScenario.summarize(run["times"])
			var drift: float = (_momentum(s) - momentum_start).length() / maxf(_momentum_scale(s), 1e-300)
			if r == 0:
				finals[kernel_name] = s
			var awake_now: int = 0
			for mode: int in s.p_mode:
				if mode == Gravity.ParticleMode.AWAKE:
					awake_now += 1
			print("%s repeat %d: mean %.3f ms, median %.3f, p95 %.3f, worst %.3f (frame %d); setup %.1f ms; %.1f steps/frame; %d particles awake at the end; momentum drift %s; reached %.5f years" % [
				kernel_name, r + 1, stats["mean"], stats["median"], stats["p95"], stats["worst"], stats["worst_frame"],
				run["setup"], float(run["steps"]) / frames, awake_now, String.num_scientific(drift), s.time,
			])
	if finals.size() == 2:
		var gaps: Dictionary = BenchmarkScenario.compare(finals["script"], finals["native"])
		print("script vs native after %d frames: same time %s; largest difference %s AU for bodies, %s AU for particles; same awake/asleep states %s" % [
			frames, gaps["same_time"], String.num_scientific(gaps["bodies"]), String.num_scientific(gaps["particles"]),
			gaps["same_modes"],
		])
	quit(1 if failed else 0)


## Total momentum of the bodies that pull (M☉·AU/yr).
static func _momentum(s: NBodyState) -> Vector3:
	var total: Vector3 = Vector3.ZERO
	for i: int in s.body_count():
		if s.mode[i] == Gravity.Mode.FREE:
			total += Vector3(s.vel[i * 3], s.vel[i * 3 + 1], s.vel[i * 3 + 2]) * s.mass[i]
	return total


## The size of the momenta involved, to express the drift as a share.
static func _momentum_scale(s: NBodyState) -> float:
	var total: float = 0.0
	for i: int in s.body_count():
		if s.mode[i] == Gravity.Mode.FREE:
			total += Vector3(s.vel[i * 3], s.vel[i * 3 + 1], s.vel[i * 3 + 2]).length() * s.mass[i]
	return total


func _arguments() -> Dictionary[String, String]:
	var args: Dictionary[String, String] = {}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--") and argument.contains("="):
			var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
			args[parts[0]] = parts[1]
	return args
