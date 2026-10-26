extends TestCase
## The game screen's interface fits its 640×360 frame in English and in
## Portuguese: every toolbar tab on screen, each power's name and hint on
## one line without being cut, inspect windows clear of the toolbar, time
## buttons big enough to hit, and tabs whose powers come later set apart.

const SPACE_SCENE: String = "res://scenes/space.tscn"
const SETTINGS_PATH: String = "user://test_layout_settings.cfg"
const START: String = "2026-10-13T12:00:00"
const LOCALES: Array[String] = ["en", "pt_PT"]

var _screen: Node
var _toolbar: Toolbar


func before_each() -> void:
	InputBindings.apply()
	TranslationServer.set_locale("en")
	_screen = (load(SPACE_SCENE) as PackedScene).instantiate()
	_screen.set(&"start_time", Units.years_from_unix(Time.get_unix_time_from_datetime_string(START)))
	_screen.set(&"settings", GameSettings.new(SETTINGS_PATH))
	tree.root.add_child(_screen)
	_toolbar = _screen.get_node("UI/Root/Toolbar")
	await wait_frames(3)


func after_each() -> void:
	_screen.queue_free()
	await wait_frames(2)
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	TranslationServer.set_locale("en")


func _frame() -> Rect2:
	return Rect2(Vector2.ZERO, (_screen.get_node("UI/Root") as Control).size)


## The toolbar's labels whose text does not fit their width.
func _cut_labels() -> PackedStringArray:
	var cut: PackedStringArray = []
	for node: Node in _toolbar.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if not label.is_visible_in_tree() or label.text.is_empty():
			continue
		var font: Font = label.get_theme_font(&"font")
		var width: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size(&"font_size")).x
		if width > label.size.x + 0.5:
			cut.append("'%s' (%d px in %d)" % [label.text, width, label.size.x])
	return cut


func test_every_tab_is_on_screen() -> void:
	for locale: String in LOCALES:
		TranslationServer.set_locale(locale)
		await wait_frames(2)
		for index: int in _toolbar.tabs.size():
			var tab: Button = _toolbar.tab_button(index)
			assert_true(_frame().encloses(tab.get_global_rect()), "%s: '%s' at %s" % [locale, tab.text, tab.get_global_rect()])


func test_each_power_is_described_on_one_line() -> void:
	for locale: String in LOCALES:
		TranslationServer.set_locale(locale)
		for index: int in _toolbar.tabs.size():
			_toolbar.select(index)
			await wait_frames(2)
			assert_eq(_cut_labels(), PackedStringArray(), "%s, tab %d" % [locale, index])
			for id: String in _toolbar.power_ids():
				_toolbar.choose_power(id)
				await wait_frames(2)
				assert_eq(_cut_labels(), PackedStringArray(), "%s, %s" % [locale, id])
				var tooltip: String = _toolbar.power_button(id).tooltip_text
				assert_true(tooltip.contains(tr(str(_toolbar.current_power().get("name_key", id)))), "%s: its tooltip names it: %s" % [id, tooltip])
				if ["place", "fling"].has(_toolbar.current_power().get("action")):
					assert_true(tooltip.contains(tr("POWER_AIM_HINT")), "%s: and says a body can be aimed at: %s" % [id, tooltip])
				_toolbar.cancel_power()


func test_tabs_whose_powers_come_later_are_set_apart() -> void:
	for index: int in _toolbar.tabs.size():
		var tab: Dictionary = _toolbar.tabs[index]
		var later: bool = not tab.has("hint_key")
		var look: StringName = _toolbar.tab_button(index).theme_type_variation
		assert_eq(look == &"LockedTab", later, "%s" % tab["id"])


func test_inspect_windows_stay_clear_of_the_toolbar() -> void:
	var view: SpaceView = _screen.get_node("View")
	var simulation: Simulation = _screen.get(&"simulation")
	for locale: String in LOCALES:
		TranslationServer.set_locale(locale)
		for id: StringName in [&"earth", &"sun", &"moon"]:
			view.select(simulation.system.index_of(id))
			await wait_frames(3)
			var windows: Array[InspectWindow] = _screen.call(&"inspect_windows")
			var rect: Rect2 = windows[0].get_global_rect()
			assert_true(_frame().encloses(rect), "%s, %s: on screen at %s" % [locale, id, rect])
			assert_false(rect.intersects(_toolbar.get_global_rect()), "%s, %s: above the toolbar" % [locale, id])
			for row: PackedStringArray in windows[0].rows():
				assert_false(row[1].is_empty(), "%s: every value shown" % id)


func test_time_buttons_are_big_enough_to_hit() -> void:
	var controls: TimeControls = _screen.get_node("UI/Root/TimeControls")
	for button: Button in [controls.slower_button(), controls.pause_button(), controls.faster_button()]:
		assert_true(button.size.x >= 13.0 and button.size.y >= 13.0, "%s is %s" % [button.tooltip_text, button.size])


func test_an_inspect_window_does_not_cover_its_body() -> void:
	var view: SpaceView = _screen.get_node("View")
	var simulation: Simulation = _screen.get(&"simulation")
	simulation.clock.paused = true
	for id: StringName in [&"earth", &"venus", &"mercury", &"mars", &"sun"]:
		var index: int = simulation.system.index_of(id)
		if not _frame().has_point(view.screen_position(index)):
			continue
		view.select(index)
		await wait_frames(3)
		var windows: Array[InspectWindow] = _screen.call(&"inspect_windows")
		var rect: Rect2 = windows[0].get_global_rect()
		assert_false(rect.grow(4.0).has_point(view.screen_position(index)), "%s at %s, window at %s" % [id, view.screen_position(index), rect])


## Long notices wrap in their corner instead of running under the date or
## the speed line (at its widest, saying the game cannot keep up).
func test_long_notices_stay_in_their_corner() -> void:
	var feed: NotificationFeed = _screen.get_node("UI/Root/Notifications")
	var counter: TimeCounter = _screen.get_node("UI/Root/TimeCounter")
	var simulation: Simulation = _screen.get(&"simulation")
	simulation.clock.paused = true
	for locale: String in LOCALES:
		TranslationServer.set_locale(locale)
		simulation.clock.paused = false
		simulation.lagging = true
		counter.refresh()
		feed.push(tr("NOTE_TORN") % ["Earth", "Black hole 1"], -1)
		await wait_frames(2)
		var entry: Button = feed.entry(feed.texts().size() - 1)
		var rect: Rect2 = entry.get_global_rect()
		for line: Node in counter.get_children():
			var label: Label = line as Label
			var font: Font = label.get_theme_font(&"font")
			var width: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size(&"font_size")).x
			var text_rect: Rect2 = Rect2(label.get_global_rect().get_center() - Vector2(width * 0.5, label.size.y * 0.5), Vector2(width, label.size.y))
			assert_false(rect.intersects(text_rect), "%s: '%s' at %s runs into '%s' at %s" % [locale, entry.text, rect, label.text, text_rect])


## The toolbar is a panel like the others: the palette's colours and hard
## pixel edges, not the engine's default grey rounded box.
func test_the_toolbar_panel_is_drawn_like_the_others() -> void:
	var panel: StyleBoxFlat = _toolbar.get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_eq(panel.bg_color, Palette.color(&"ui_panel"))
	assert_eq(panel.border_color, Palette.color(&"ui_border"))
	assert_eq(panel.corner_radius_top_left, 0, "square corners")
	assert_false(panel.anti_aliasing, "hard pixel edges")
