class_name PaletteStrip
extends Control
## Shows every colour of the shared palette as a row of swatches, with the id
## of the swatch under the mouse. A development aid, toggled from the title.

const SWATCH: int = 8
const GAP: int = 1
const COLUMNS: int = 28

var _hovered: int = -1


func _ready() -> void:
	var rows: int = ceili(Palette.ids().size() / float(COLUMNS))
	custom_minimum_size = Vector2(COLUMNS * (SWATCH + GAP) + GAP, rows * (SWATCH + GAP) + GAP + 12)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var p: Vector2 = (event as InputEventMouseMotion).position
		@warning_ignore("integer_division")
		var column: int = int(p.x) / (SWATCH + GAP)
		@warning_ignore("integer_division")
		var row: int = int(p.y) / (SWATCH + GAP)
		var index: int = row * COLUMNS + column
		var hovered: int = index if column < COLUMNS and index < Palette.ids().size() else -1
		if hovered != _hovered:
			_hovered = hovered
			queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hovered != -1:
		_hovered = -1
		queue_redraw()


func _draw() -> void:
	var ids: Array[StringName] = Palette.ids()
	var rows: int = ceili(ids.size() / float(COLUMNS))
	var frame: Rect2 = Rect2(0, 0, COLUMNS * (SWATCH + GAP) + GAP, rows * (SWATCH + GAP) + GAP)
	draw_rect(frame, Palette.color(&"ui_border"))
	for i: int in ids.size():
		@warning_ignore("integer_division")
		var cell: Vector2 = Vector2(GAP + (i % COLUMNS) * (SWATCH + GAP), GAP + (i / COLUMNS) * (SWATCH + GAP))
		draw_rect(Rect2(cell, Vector2(SWATCH, SWATCH)), Palette.color(ids[i]))
		if i == _hovered:
			draw_rect(Rect2(cell - Vector2.ONE, Vector2(SWATCH + 2, SWATCH + 2)), Palette.color(&"white"), false, 1.0)
	if _hovered != -1:
		var font: Font = get_theme_default_font()
		var font_size: int = get_theme_default_font_size()
		var label: String = "%s  #%s" % [ids[_hovered], Palette.color(ids[_hovered]).to_html(false)]
		draw_string(font, Vector2(0, frame.size.y + 10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Palette.color(&"ui_text"))
