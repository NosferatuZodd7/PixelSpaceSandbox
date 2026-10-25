extends TestCase
## The pixel fonts import unsmoothed, cover Portuguese, and every interface
## string exists in English and Portuguese.

const CSV_PATH: String = "res://locale/ui.csv"
const LOCALES: Array[String] = ["en", "pt_PT"]
const PORTUGUESE: String = "áàâãçéêíóôõúÁÀÂÃÇÉÊÍÓÔÕÚ"


func _fonts() -> Array[FontFile]:
	return [UiTheme.body_font() as FontFile, UiTheme.display_font() as FontFile]


func test_fonts_import_without_smoothing() -> void:
	for font: FontFile in _fonts():
		assert_true(font != null, "font loads")
		if font == null:
			continue
		var font_name: String = font.get_font_name()
		assert_eq(font.antialiasing, TextServer.FONT_ANTIALIASING_NONE, font_name + " antialiasing")
		assert_eq(font.hinting, TextServer.HINTING_NONE, font_name + " hinting")
		assert_eq(font.subpixel_positioning, TextServer.SUBPIXEL_POSITIONING_DISABLED, font_name + " subpixel")
		assert_false(font.generate_mipmaps, font_name + " mipmaps")
		assert_false(font.multichannel_signed_distance_field, font_name + " msdf")


## At their native sizes (and multiples) every glyph advance and the line
## height are whole pixels, so letters sit exactly on the pixel grid.
func test_fonts_land_on_whole_pixels_at_their_sizes() -> void:
	var sample: String = "AaBbGgJjMmQqWw019.,:;!?ãçéõ%"
	var cases: Array[Array] = [
		[UiTheme.body_font(), UiTheme.BODY_SIZE],
		[UiTheme.body_font(), UiTheme.BODY_SIZE * 2],
		[UiTheme.display_font(), UiTheme.DISPLAY_SIZE],
		[UiTheme.display_font(), UiTheme.DISPLAY_SIZE * 2],
	]
	for case: Array in cases:
		var font: Font = case[0]
		var size: int = case[1]
		var label: String = "%s at %d px" % [font.get_font_name(), size]
		var height: float = font.get_height(size)
		assert_eq(height, roundf(height), label + " line height")
		for character: String in sample:
			var width: float = font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			assert_eq(width, roundf(width), "%s: '%s' advance" % [label, character])
	assert_eq(UiTheme.display_font().get_string_size("A", HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x, 8.0, "Press Start 2P is 8 px wide at 8 px")


## Interface text must be easy to read: capitals at least 8 px tall (16 on
## a 1280×720 screen) and room above them for Portuguese accents.
func test_body_text_is_large_enough_to_read() -> void:
	var font: FontFile = UiTheme.body_font() as FontFile
	var server: TextServer = TextServerManager.get_primary_interface()
	var rid: RID = font.get_rids()[0]
	var size: Vector2i = Vector2i(UiTheme.BODY_SIZE, 0)
	var capital: int = server.font_get_glyph_index(rid, UiTheme.BODY_SIZE, "H".unicode_at(0), 0)
	# Glyph images carry one pixel of padding on every side.
	var cap_height: float = server.font_get_glyph_size(rid, size, capital).y - 2.0
	assert_true(cap_height >= 8.0, "capitals are %d px tall" % cap_height)
	var accented: int = server.font_get_glyph_index(rid, UiTheme.BODY_SIZE, "Ã".unicode_at(0), 0)
	var top: float = -server.font_get_glyph_offset(rid, size, accented).y - 1.0
	assert_true(top <= font.get_ascent(UiTheme.BODY_SIZE), "accents on capitals stay inside the line")


## Window headers are in capitals ("VÉNUS", "DEFINIÇÕES"): their font must
## draw accented capitals with the accent above the letter, not squeezed
## into a small letter.
func test_headers_keep_accents_above_capitals() -> void:
	var theme: Theme = UiTheme.shared()
	var font: FontFile = theme.get_font(&"font", &"HeaderLabel") as FontFile
	var size: int = theme.get_font_size(&"font_size", &"HeaderLabel")
	var server: TextServer = TextServerManager.get_primary_interface()
	var rid: RID = font.get_rids()[0]
	for pair: String in ["EÉ", "UÚ", "OÕ", "AÃ"]:
		var heights: Array[float] = []
		for character: String in pair:
			var glyph: int = server.font_get_glyph_index(rid, size, character.unicode_at(0), 0)
			heights.append(server.font_get_glyph_size(rid, Vector2i(size, 0), glyph).y)
		assert_true(heights[1] > heights[0], "%s: '%s' is taller than '%s'" % [font.get_font_name(), pair[1], pair[0]])


func test_fonts_cover_portuguese() -> void:
	for font: FontFile in _fonts():
		for character: String in PORTUGUESE:
			assert_true(font.has_char(character.unicode_at(0)), "%s has '%s'" % [font.get_font_name(), character])


func test_every_string_is_translated() -> void:
	var rows: Array[PackedStringArray] = _csv_rows()
	assert_false(rows.is_empty(), "strings found")
	for locale: String in LOCALES:
		var translation: Translation = TranslationServer.get_translation_object(locale)
		assert_true(translation != null and translation.get_locale() == locale, "translation for %s is loaded" % locale)
		if translation == null:
			continue
		for row: PackedStringArray in rows:
			var text: String = translation.get_message(row[0])
			assert_false(text.is_empty() or text == row[0], "%s has %s" % [locale, row[0]])


func test_every_string_can_be_drawn_by_the_body_font() -> void:
	var font: FontFile = UiTheme.body_font() as FontFile
	for row: PackedStringArray in _csv_rows():
		for column: int in range(1, row.size()):
			for character: String in row[column]:
				var code: int = character.unicode_at(0)
				assert_true(font.has_char(code), "'%s' in %s" % [character, row[0]])


## The CSV rows after the header: [key, en, pt_PT].
func _csv_rows() -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var file: FileAccess = FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		fail("cannot open %s" % CSV_PATH)
		return rows
	var header: PackedStringArray = file.get_csv_line()
	assert_eq(header, PackedStringArray(["keys"] + LOCALES), "CSV columns")
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.size() > 1 or (row.size() == 1 and not row[0].is_empty()):
			rows.append(row)
	return rows
