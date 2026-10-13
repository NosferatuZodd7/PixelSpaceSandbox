class_name TestCase
extends RefCounted
## Base class for headless tests.
##
## The runner (tests/run_tests.gd) calls every method whose name starts with
## "test_", with before_each() and after_each() around it. A test passes when
## it records no failure. Tests may be coroutines (use await).

## The running SceneTree, for tests that need nodes or frames.
var tree: SceneTree

var _failures: PackedStringArray = []


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func failures() -> PackedStringArray:
	return _failures


func clear_failures() -> void:
	_failures.clear()


func fail(message: String) -> void:
	_failures.append("%s  [%s]" % [message, _caller()])


func assert_true(condition: bool, message: String = "") -> void:
	if not condition:
		fail(message if not message.is_empty() else "expected true")


func assert_false(condition: bool, message: String = "") -> void:
	if condition:
		fail(message if not message.is_empty() else "expected false")


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if not _same(actual, expected):
		fail("%sexpected %s, got %s" % [_prefix(message), var_to_str(expected), var_to_str(actual)])


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	if _same(actual, unexpected):
		fail("%sexpected anything but %s" % [_prefix(message), var_to_str(unexpected)])


func assert_almost_eq(actual: float, expected: float, tolerance: float, message: String = "") -> void:
	if absf(actual - expected) > tolerance:
		fail("%sexpected %s ± %s, got %s" % [_prefix(message), expected, tolerance, actual])


## Waits for the given number of frames to be processed.
func wait_frames(count: int) -> void:
	for i: int in count:
		await tree.process_frame


## Waits until the condition is true, for at most the given number of seconds.
## Returns whether the condition became true.
func wait_until(condition: Callable, timeout_seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await tree.process_frame
	return true


static func _same(a: Variant, b: Variant) -> bool:
	var numbers: Array[int] = [TYPE_INT, TYPE_FLOAT]
	var strings: Array[int] = [TYPE_STRING, TYPE_STRING_NAME]
	if typeof(a) == typeof(b):
		return a == b
	if typeof(a) in numbers and typeof(b) in numbers:
		return a == b
	if typeof(a) in strings and typeof(b) in strings:
		return str(a) == str(b)
	return false


static func _prefix(message: String) -> String:
	return "" if message.is_empty() else message + ": "


## The first stack frame outside this file, as "file:line".
static func _caller() -> String:
	for frame: Dictionary in get_stack():
		var source: String = frame["source"]
		if not source.ends_with("base_test_case.gd"):
			return "%s:%d" % [source.get_file(), frame["line"]]
	return "?"
