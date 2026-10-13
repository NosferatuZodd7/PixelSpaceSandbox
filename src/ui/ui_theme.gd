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

	theme.set_type_variation(&"KeyLabel", &"Label")
	theme.set_color(&"font_color", &"KeyLabel", Palette.color(&"ui_accent"))

	# Panels with hard pixel edges: no rounding, no anti-aliasing.
	var panel: StyleBoxFlat = StyleBoxFlat.new()
	panel.bg_color = Palette.color(&"ui_panel")
	panel.border_color = Palette.color(&"ui_border")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(0)
	panel.anti_aliasing = false
	panel.set_content_margin_all(4)
	theme.set_stylebox(&"panel", &"PanelContainer", panel)
	theme.set_stylebox(&"panel", &"Panel", panel)
	return theme
