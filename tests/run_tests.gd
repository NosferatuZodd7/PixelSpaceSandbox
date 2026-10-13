extends SceneTree
## Headless test runner.
##
##   godot --headless --path . --script res://tests/run_tests.gd [-- --filter=<text>]
##
## Runs every test_* method of every tests/**/test_*.gd script, prints one
## line per test and a summary, and exits with code 1 if anything failed.
## tools/run_tests.sh wraps it and also fails on any error or warning.

const TEST_ROOT: String = "res://tests"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var filter: String = _filter_from_args()
	var passed: int = 0
	var failed: int = 0
	var started: int = Time.get_ticks_msec()

	for path: String in _find_tests(TEST_ROOT):
		var script: GDScript = load(path) as GDScript
		var case: TestCase = null
		if script != null and script.can_instantiate():
			case = script.new() as TestCase
		if case == null:
			print("FAIL  %s: cannot load it as a TestCase" % path)
			failed += 1
			continue
		case.tree = self

		for method_name: String in _test_methods(script):
			var label: String = "%s.%s" % [path.get_file().get_basename(), method_name]
			if not filter.is_empty() and not label.contains(filter):
				continue
			case.clear_failures()
			await case.call(&"before_each")
			await case.call(method_name)
			await case.call(&"after_each")
			if case.failures().is_empty():
				print("PASS  %s" % label)
				passed += 1
			else:
				print("FAIL  %s" % label)
				for message: String in case.failures():
					print("        %s" % message)
				failed += 1

	var seconds: float = (Time.get_ticks_msec() - started) / 1000.0
	print("")
	print("%d passed, %d failed (%.2f s)" % [passed, failed, seconds])
	quit(1 if failed > 0 or passed == 0 else 0)


func _test_methods(script: GDScript) -> PackedStringArray:
	var names: PackedStringArray = []
	for method: Dictionary in script.get_script_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_") and not names.has(method_name):
			names.append(method_name)
	return names


## Every test_*.gd script under the directory, sorted, recursively.
func _find_tests(directory: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for file: String in DirAccess.get_files_at(directory):
		if file.begins_with("test_") and file.ends_with(".gd"):
			found.append(directory.path_join(file))
	for subdirectory: String in DirAccess.get_directories_at(directory):
		found.append_array(_find_tests(directory.path_join(subdirectory)))
	found.sort()
	return found


func _filter_from_args() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--filter="):
			return argument.trim_prefix("--filter=")
	return ""
