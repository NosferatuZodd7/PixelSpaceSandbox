extends TestCase
## The title screen starts, draws a sky, follows the language and frees
## cleanly, with no errors along the way.

const MAIN_SCENE: String = "res://scenes/main.tscn"

var _main: Node


func before_each() -> void:
	InputBindings.apply()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	tree.root.add_child(_main)


func after_each() -> void:
	TranslationServer.set_locale("en")
	_main.queue_free()
	await wait_frames(2)


func test_sky_is_generated() -> void:
	var sky: StarfieldBackground = _main.get_node("Sky")
	var ready: bool = await wait_until(func() -> bool: return not sky.is_generating(), 10.0)
	assert_true(ready, "sky generated within 10 s")
	await wait_frames(2)
	assert_eq(sky.sky_seed, 7, "default seed")


func test_new_sky_request_while_generating_uses_the_latest_seed() -> void:
	var sky: StarfieldBackground = _main.get_node("Sky")
	var seeds: Array[int] = []
	sky.sky_ready.connect(func(sky_seed: int) -> void: seeds.append(sky_seed))
	sky.generate(11)
	sky.generate(12)
	var done: bool = await wait_until(func() -> bool: return seeds.has(12) and not sky.is_generating(), 20.0)
	assert_true(done, "latest sky generated")
	assert_false(seeds.has(11), "the superseded seed is skipped")


func test_hints_show_the_bound_keys() -> void:
	await wait_frames(1)
	var hints: HBoxContainer = _main.get_node("UI/Root/Hints")
	var texts: PackedStringArray = []
	for child: Node in hints.get_children():
		if child is Label:
			texts.append((child as Label).text)
	assert_true(texts.has("ESC"), "quit key shown: %s" % ", ".join(texts))
	assert_true(texts.has("HINT_QUIT"), "quit hint shown")


func test_language_switch_updates_texts() -> void:
	await wait_frames(1)
	var language: Label = _main.get_node("UI/Root/LanguageLabel")
	var seed_label: Label = _main.get_node("UI/Root/SeedLabel")
	TranslationServer.set_locale("en")
	await wait_frames(1)
	assert_eq(language.text, "English")
	assert_eq(seed_label.text, "Seed 7")
	TranslationServer.set_locale("pt_PT")
	await wait_frames(1)
	assert_eq(language.text, "Português")
	assert_eq(seed_label.text, "Semente 7")
