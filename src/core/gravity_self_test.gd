class_name GravitySelfTest
extends RefCounted
## A check the shipped game can run on any PC (`-- --gravity-self-test` on
## the command line, optionally `--gravity-self-test-frames=600`): it runs
## the benchmark scene on both gravity kernels (two seconds of play by
## default), prints whether the native kernel loaded, whether the two
## kernels agree, and how long a frame of simulation takes. The Windows CI
## job runs it on a real Windows machine.

const FLAG: String = "--gravity-self-test"
const FRAMES_FLAG: String = "--gravity-self-test-frames="
const FRAMES: int = 120
## The kernels agree when they end this close (AU). Their maths libraries
## may differ in the last bit on another platform; a real difference in the
## physics would be many orders of magnitude larger.
const TOLERANCE: float = 1e-9


static func requested() -> bool:
	return OS.get_cmdline_user_args().has(FLAG)


static func frames() -> int:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(FRAMES_FLAG):
			return maxi(int(argument.trim_prefix(FRAMES_FLAG)), 1)
	return FRAMES


## Runs the check and prints its findings. True when the native kernel is
## loaded and ends where the GDScript one does.
static func run() -> bool:
	var native: bool = Gravity.native_available()
	print("Gravity self-test: native kernel loaded: %s" % native)
	var count: int = frames()
	var finals: Dictionary[String, NBodyState] = {}
	for kernel_name: String in (["script", "native"] if native else ["script"]):
		var s: NBodyState = BenchmarkScenario.build()
		var run: Dictionary = BenchmarkScenario.run(Gravity.kernel_named(kernel_name), s, count)
		var stats: Dictionary = BenchmarkScenario.summarize(run["times"])
		print("Gravity self-test: %s kernel, %d frames: mean %.3f ms, median %.3f, p95 %.3f, worst %.3f" % [
			kernel_name, count, stats["mean"], stats["median"], stats["p95"], stats["worst"],
		])
		finals[kernel_name] = s
	if not native:
		return false
	var gaps: Dictionary = BenchmarkScenario.compare(finals["script"], finals["native"])
	var agree: bool = (
		gaps["same_time"] and gaps["same_modes"] and float(gaps["bodies"]) < TOLERANCE
		and float(gaps["particles"]) < TOLERANCE
	)
	print("Gravity self-test: largest difference %s AU (bodies), %s AU (particles)" % [
		String.num_scientific(gaps["bodies"]), String.num_scientific(gaps["particles"]),
	])
	print("Gravity self-test: kernels agree: %s" % agree)
	return agree
