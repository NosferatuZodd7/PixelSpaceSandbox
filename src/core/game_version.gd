class_name GameVersion
extends RefCounted
## The game's version ("0.2.0", or "0.2.0-dev.14" for a test build from the
## beta branch) and semver ordering: a test build comes before the version
## it leads to, and build numbers compare as numbers.

const SETTING: String = "application/config/version"


## The version of the running game.
static func current() -> String:
	return str(ProjectSettings.get_setting(SETTING, "0.0.0"))


static func is_valid(text: String) -> bool:
	return not _parse(text).is_empty()


## Whether a version is a test build (has a pre-release part).
static func is_test_build(text: String) -> bool:
	var parsed: Array = _parse(text)
	return not parsed.is_empty() and not (parsed[1] as PackedStringArray).is_empty()


## -1, 0 or 1 as a comes before, equals or comes after b. An invalid
## version comes before every valid one.
static func compare(a: String, b: String) -> int:
	var pa: Array = _parse(a)
	var pb: Array = _parse(b)
	if pa.is_empty() or pb.is_empty():
		return signi(int(not pa.is_empty()) - int(not pb.is_empty()))
	var core_a: PackedInt64Array = pa[0]
	var core_b: PackedInt64Array = pb[0]
	for k: int in 3:
		if core_a[k] != core_b[k]:
			return -1 if core_a[k] < core_b[k] else 1
	var pre_a: PackedStringArray = pa[1]
	var pre_b: PackedStringArray = pb[1]
	# A version without a pre-release part comes after one with it.
	if pre_a.is_empty() or pre_b.is_empty():
		return signi(int(pre_a.is_empty()) - int(pre_b.is_empty()))
	for k: int in mini(pre_a.size(), pre_b.size()):
		var x: String = pre_a[k]
		var y: String = pre_b[k]
		if x == y:
			continue
		if x.is_valid_int() and y.is_valid_int():
			return -1 if x.to_int() < y.to_int() else 1
		if x.is_valid_int() != y.is_valid_int():
			return -1 if x.is_valid_int() else 1
		return -1 if x < y else 1
	return signi(pre_a.size() - pre_b.size())


## [PackedInt64Array major, minor, patch; PackedStringArray pre-release
## parts], or empty when the text is not a version.
static func _parse(text: String) -> Array:
	var version: String = text.strip_edges().trim_prefix("v")
	version = version.get_slice("+", 0)
	var dash: int = version.find("-")
	var main: String = version if dash == -1 else version.substr(0, dash)
	var parts: PackedStringArray = main.split(".")
	if parts.size() != 3:
		return []
	var numbers: PackedInt64Array = []
	for part: String in parts:
		if not part.is_valid_int() or part.to_int() < 0:
			return []
		numbers.append(part.to_int())
	var pre: PackedStringArray = []
	if dash != -1:
		pre = version.substr(dash + 1).split(".")
		for part: String in pre:
			if part.is_empty():
				return []
	return [numbers, pre]
