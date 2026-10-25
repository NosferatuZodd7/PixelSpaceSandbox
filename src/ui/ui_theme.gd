class_name UiTheme
extends RefCounted
## The game's UI theme, built from the palette and the pixel fonts.
##
## Pixel fonts are only sharp at the sizes their design grid was drawn for:
## Micro 5 at 11 px and Press Start 2P at 8 px (or exact multiples).

const BODY_FONT_PATH: String = "res://assets/fonts/micro5/Micro5-Regular.ttf"
const DISPLAY_FONT_PATH: String = "res://assets/fonts/press_start_2p/PressStart2P-Regular.ttf"
const BODY_SIZE: int = 11
const DISPLAY_SIZE: int = 8

static var _shared: Theme


## The theme every screen uses (built once).
static func shared() -> Theme:
	if _shared == null:
		_shared = build()
	return _shared


static func body_font() -> Font:
	return load(BODY_FONT_PATH) as Font


static func display_font() -> Font:
	return load(DISPLAY_FONT_PATH) as Font


static func build() -> Theme:
	var theme: Theme = Theme.new()
	theme.default_font = body_font()
	theme.default_font_size = BODY_SIZE

	theme.set_color(&"font_color", &"Label", Palette.color(&"ui_text"))
	theme.set_color(&"font_shadow_color", &"Label", Palette.color(&"ui_shadow"))
	theme.set_constant(&"shadow_offset_x", &"Label", 1)
	theme.set_constant(&"shadow_offset_y", &"Label", 1)

	# Big titles in the display font, at twice its native size.
	theme.set_type_variation(&"TitleLabel", &"Label")
	theme.set_font(&"font", &"TitleLabel", display_font())
	theme.set_font_size(&"font_size", &"TitleLabel", DISPLAY_SIZE * 2)
	theme.set_color(&"font_color", &"TitleLabel", Palette.color(&"ui_accent"))
	theme.set_constant(&"shadow_offset_x", &"TitleLabel", 2)
	theme.set_constant(&"shadow_offset_y", &"TitleLabel", 2)

	theme.set_type_variation(&"DimLabel", &"Label")
	theme.set_color(&"font_color", &"DimLabel", Palette.color(&"ui_text_dim"))

	# Highlighted text: what is happening right now (paused, following, a warning).
	theme.set_type_variation(&"KeyLabel", &"Label")
	theme.set_color(&"font_color", &"KeyLabel", Palette.color(&"ui_accent"))

	# Panel headers in the display font at its native size.
	theme.set_type_variation(&"HeaderLabel", &"Label")
	theme.set_font(&"font", &"HeaderLabel", display_font())
	theme.set_font_size(&"font_size", &"HeaderLabel", DISPLAY_SIZE)
	theme.set_color(&"font_color", &"HeaderLabel", Palette.color(&"ui_accent"))

	# Panels with hard pixel edges: no rounding, no anti-aliasing.
	var panel: StyleBoxFlat = _box(&"ui_panel", &"ui_border", 8)
	theme.set_stylebox(&"panel", &"PanelContainer", panel)
	theme.set_stylebox(&"panel", &"Panel", panel)

	_add_buttons(theme)
	return theme


## Draws a one-pixel frame just inside the rectangle, crisp at any scale.
static func draw_frame(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), color)
	canvas.draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 1), Vector2(rect.size.x, 1)), color)
	canvas.draw_rect(Rect2(rect.position, Vector2(1, rect.size.y)), color)
	canvas.draw_rect(Rect2(rect.position + Vector2(rect.size.x - 1, 0), Vector2(1, rect.size.y)), color)


static func _add_buttons(theme: Theme) -> void:
	var normal: StyleBoxFlat = _box(&"ui_panel", &"ui_border", 0)
	var hover: StyleBoxFlat = _box(&"ui_panel_light", &"ui_border", 0)
	var pressed: StyleBoxFlat = _box(&"space_indigo", &"ui_accent", 0)
	var disabled: StyleBoxFlat = _box(&"ui_panel", &"space_indigo_light", 0)
	var focus: StyleBoxFlat = _box(&"ui_panel", &"ui_accent", 0)
	focus.draw_center = false
	for box: StyleBoxFlat in [normal, hover, pressed, disabled, focus]:
		box.content_margin_left = 8
		box.content_margin_right = 8
		box.content_margin_top = 2
		box.content_margin_bottom = 3
	theme.set_stylebox(&"normal", &"Button", normal)
	theme.set_stylebox(&"hover", &"Button", hover)
	theme.set_stylebox(&"pressed", &"Button", pressed)
	theme.set_stylebox(&"hover_pressed", &"Button", pressed)
	theme.set_stylebox(&"disabled", &"Button", disabled)
	theme.set_stylebox(&"focus", &"Button", focus)
	theme.set_color(&"font_color", &"Button", Palette.color(&"ui_text"))
	theme.set_color(&"font_hover_color", &"Button", Palette.color(&"white"))
	theme.set_color(&"font_focus_color", &"Button", Palette.color(&"ui_text"))
	theme.set_color(&"font_pressed_color", &"Button", Palette.color(&"ui_accent"))
	theme.set_color(&"font_hover_pressed_color", &"Button", Palette.color(&"ui_accent"))
	theme.set_color(&"font_disabled_color", &"Button", Palette.color(&"ui_disabled"))

	# Square buttons around a pixel icon (the god powers).
	theme.set_type_variation(&"IconButton", &"Button")
	var states: Dictionary[StringName, StyleBoxFlat] = {
		&"normal": normal, &"hover": hover, &"pressed": pressed, &"hover_pressed": pressed,
		&"disabled": disabled, &"focus": focus,
	}
	for state: StringName in states:
		var box: StyleBoxFlat = states[state].duplicate()
		box.set_content_margin_all(2)
		theme.set_stylebox(state, &"IconButton", box)

	# Small "<" and ">" arrows: text only, no box.
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	empty.content_margin_left = 3
	empty.content_margin_right = 3
	theme.set_type_variation(&"ArrowButton", &"Button")
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"]:
		theme.set_stylebox(state, &"ArrowButton", empty)
	theme.set_color(&"font_color", &"ArrowButton", Palette.color(&"ui_accent"))
	theme.set_color(&"font_hover_color", &"ArrowButton", Palette.color(&"white"))
	theme.set_color(&"font_pressed_color", &"ArrowButton", Palette.color(&"white"))


static func _box(background: StringName, border: StringName, margin: int) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Palette.color(background)
	box.border_color = Palette.color(border)
	box.set_border_width_all(1)
	box.set_corner_radius_all(0)
	box.anti_aliasing = false
	box.set_content_margin_all(margin)
	return box
