extends TestCase
## Numbers, durations and dates read naturally in both languages.


func after_each() -> void:
	TranslationServer.set_locale("en")


func _in(locale: String) -> void:
	TranslationServer.set_locale(locale)


func test_numbers_in_english_and_portuguese() -> void:
	_in("en")
	assert_eq(Format.number(1234567.891, 2), "1,234,567.89")
	assert_eq(Format.number(-42.0), "-42")
	assert_eq(Format.number(-0.004, 2), "0.00", "no negative zero")
	assert_eq(Format.number(3.0, 2), "3.00")
	_in("pt_PT")
	assert_eq(Format.number(1234567.891, 2), "1 234 567,89")
	assert_eq(Format.number(0.5, 1), "0,5")


func test_significant_digits_and_scientific() -> void:
	_in("en")
	assert_eq(Format.significant(0.0549, 3), "0.0549")
	assert_eq(Format.significant(11.862, 3), "11.9")
	assert_eq(Format.significant(1898.13, 3), "1,898")
	assert_eq(Format.scientific(1.0659e16, 3), "1.07e16")
	assert_eq(Format.scientific(9.9999e3, 2), "1.0e4", "rounding up moves the exponent")


func test_durations() -> void:
	_in("en")
	assert_eq(Format.duration(499.005), "8 min 19 s", "sunlight to the Earth")
	assert_eq(Format.duration(3600.0), "1 h")
	assert_eq(Format.duration(9.925 * 3600.0), "9 h 56 min", "a day on Jupiter")
	assert_eq(Format.duration(Units.DAY_SECONDS), "1 day")
	assert_eq(Format.duration(27.3217 * Units.DAY_SECONDS), "27.3 days")
	assert_eq(Format.duration(Units.YEAR_SECONDS), "1 year")
	assert_eq(Format.duration(11.862 * Units.YEAR_SECONDS), "11.9 years")
	assert_eq(Format.years(4.6e9), "4.6 billion years")
	assert_eq(Format.years(1.0e6), "1 million years")
	_in("pt_PT")
	assert_eq(Format.duration(Units.DAY_SECONDS), "1 dia")
	assert_eq(Format.duration(27.3217 * Units.DAY_SECONDS), "27,3 dias")
	assert_eq(Format.duration(1.03 * Units.DAY_SECONDS), "1,03 dias", "only exactly one is singular")
	assert_eq(Format.years(1.0e6), "1 milhão de anos")
	assert_eq(Format.years(2.5e6), "2,5 milhões de anos")
	assert_eq(Format.years(4.6e9), "4,6 mil milhões de anos")


func test_speed_texts() -> void:
	_in("pt_PT")
	assert_eq(Format.multiplier(86400.0), "x86 400")
	assert_eq(Format.multiplier(0.01), "x0,01")
	assert_eq(TimeCounter.speed_words(86400.0), "1 dia por segundo")
	assert_eq(TimeCounter.speed_words(1.0), "tempo real")
	assert_eq(TimeCounter.speed_words(0.1), "câmara lenta")
	_in("en")
	assert_eq(Format.multiplier(3.15576e16), "x3.2e16")
	assert_eq(TimeCounter.speed_words(Units.YEAR_SECONDS), "1 year per second")


func test_dates() -> void:
	_in("en")
	assert_eq(Format.date(0.0, true), "01 JAN 2000  11:58", "J2000 is noon TT, two minutes earlier in UTC")
	var t: float = Units.years_from_unix(Time.get_unix_time_from_datetime_string("2026-10-13T19:42:00"))
	assert_eq(Format.date(t, false), "13 OCT 2026")
	_in("pt_PT")
	assert_eq(Format.date(t, true), "13 OUT 2026  19:42")
	assert_eq(Format.date(10345.0, false), "ANO 12 345", "far from today only the year")


func test_physical_values() -> void:
	_in("pt_PT")
	assert_eq(Format.distance(1.524), "1,52 UA")
	assert_eq(Format.distance(Units.au_from_km(384400.0)), "384 400 km")
	assert_eq(Format.gravity(3.71), "0,38 g", "gravity on Mars")
	assert_eq(Format.temperature(254.0), "254 K (-19 °C)")
