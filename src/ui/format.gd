class_name Format
extends RefCounted
## Numbers, dates and durations as the player reads them, in the interface
## language: "1 234,5" in Portuguese, "1,234.5" in English.

const STANDARD_GRAVITY: float = 9.80665


static func _portuguese() -> bool:
	return TranslationServer.get_locale().begins_with("pt")


## A number with a fixed count of decimals and grouped thousands.
static func number(value: float, decimals: int = 0) -> String:
	var text: String = String.num(absf(value), decimals)
	if decimals > 0 and not text.contains("."):
		text += "." + "0".repeat(decimals)
	var parts: PackedStringArray = text.split(".")
	var whole: String = parts[0]
	var grouped: String = ""
	var count: int = 0
	for k: int in range(whole.length() - 1, -1, -1):
		grouped = whole[k] + grouped
		count += 1
		if count % 3 == 0 and k > 0:
			grouped = (" " if _portuguese() else ",") + grouped
	var result: String = grouped
	if parts.size() > 1 and decimals > 0:
		result += ("," if _portuguese() else ".") + parts[1].left(decimals).rpad(decimals, "0")
	var is_zero: bool = result.replace("0", "").replace(",", "").replace(".", "").replace(" ", "").is_empty()
	return ("-" + result) if value < 0.0 and not is_zero else result


## A number with about this many significant digits ("0,0549", "11,9", "1 898").
static func significant(value: float, digits: int = 3) -> String:
	if value == 0.0:
		return "0"
	var magnitude: int = floori(log(absf(value)) / log(10.0))
	if magnitude < -4:
		return scientific(value, digits)
	return number(value, clampi(digits - 1 - magnitude, 0, 6))


## Scientific notation the pixel font can draw: "1,07e16".
static func scientific(value: float, digits: int = 3) -> String:
	if value == 0.0:
		return "0"
	var exponent: int = floori(log(absf(value)) / log(10.0))
	var mantissa: float = value / pow(10.0, exponent)
	if absf(mantissa) >= 9.9995:
		mantissa /= 10.0
		exponent += 1
	return "%se%d" % [number(mantissa, digits - 1), exponent]


## A length of time in words: "8 min 19 s", "1 h", "27,3 days", "1 year",
## "11,9 years", "4,6 billion years".
static func duration(seconds: float) -> String:
	var s: float = absf(seconds)
	if s < 59.5:
		return tr_units("DURATION_SECONDS", number(s, 0 if s >= 9.95 else 1))
	if s < 3570.0:
		var minutes: float = floorf((s + 0.5) / 60.0)
		var rest: float = roundf(s - minutes * 60.0)
		var text: String = tr_units("DURATION_MINUTES", number(minutes))
		return text if rest < 1.0 else "%s %s" % [text, tr_units("DURATION_SECONDS", number(rest))]
	if s < 23.95 * 3600.0:
		var hours: float = floorf((s + 30.0) / 3600.0)
		var minutes: float = roundf((s - hours * 3600.0) / 60.0)
		var text: String = tr_units("DURATION_HOURS", number(hours))
		return text if minutes < 1.0 else "%s %s" % [text, tr_units("DURATION_MINUTES", number(minutes))]
	var days: float = s / Units.DAY_SECONDS
	if days < Units.YEAR_DAYS * 0.999:
		var day_text: String = _tidy(days)
		return tr_units("DURATION_DAY" if day_text == "1" else "DURATION_DAYS", day_text)
	return years(days / Units.YEAR_DAYS)


## A number of years in words, switching to millions and billions.
static func years(value: float) -> String:
	var a: float = absf(value)
	if a >= 1e9:
		return tr_units("DURATION_BILLION_YEARS", _tidy(value / 1e9))
	if a >= 1e6:
		var million_text: String = _tidy(value / 1e6)
		return tr_units("DURATION_MILLION_YEAR" if million_text == "1" else "DURATION_MILLION_YEARS", million_text)
	if a >= 1000.0:
		return tr_units("DURATION_YEARS", number(value))
	var year_text: String = _tidy(value)
	return tr_units("DURATION_YEAR" if year_text == "1" else "DURATION_YEARS", year_text)


## Three significant digits without trailing zeros: "1", "4,6", "27,3".
static func _tidy(value: float) -> String:
	if absf(value - roundf(value)) < 0.005 * maxf(1.0, absf(value)):
		return number(roundf(value))
	var text: String = significant(value, 3)
	var separator: String = "," if _portuguese() else "."
	if text.contains(separator) and not text.contains("e"):
		text = text.rstrip("0").trim_suffix(separator)
	return text


## A translated unit pattern ("%s days") filled with a number.
static func tr_units(key: String, value: String) -> String:
	return String(TranslationServer.translate(key)).replace("%s", value)


## The time-speed multiplier: "x1", "x86 400", "x0,01".
static func multiplier(seconds_per_second: float) -> String:
	if seconds_per_second < 1.0:
		return "x" + significant(seconds_per_second, 1)
	if seconds_per_second >= 1e6:
		return "x" + scientific(seconds_per_second, 2)
	return "x" + number(seconds_per_second)


## A moment as a date ("13 OCT 2026  19:42") or, far from today, a year.
## With show_time false only the date is shown.
static func date(years_since_j2000: float, show_time: bool) -> String:
	var unix: float = Units.unix_from_years(years_since_j2000)
	var calendar_year: float = 2000.0 + years_since_j2000
	if absf(calendar_year) >= 9999.0:
		return String(TranslationServer.translate("YEAR_LABEL")).replace("%s", number(floorf(calendar_year)))
	var moment: Dictionary = Time.get_datetime_dict_from_unix_time(roundi(unix))
	var month: String = String(TranslationServer.translate("MONTH_%d" % int(moment["month"])))
	var text: String = "%02d %s %d" % [int(moment["day"]), month, int(moment["year"])]
	if show_time:
		text += "  %02d:%02d" % [int(moment["hour"]), int(moment["minute"])]
	return text


## Distance in AU ("1,52 AU") or, when small, in km ("384 400 km").
static func distance(au: float) -> String:
	if au < 0.01:
		return tr_units("UNIT_KM", number(Units.km_from_au(au)))
	return tr_units("UNIT_AU", significant(au, 3))


static func gravity(meters_per_second_squared: float) -> String:
	return tr_units("UNIT_G", significant(meters_per_second_squared / STANDARD_GRAVITY, 2))


static func temperature(kelvin: float) -> String:
	return "%s K (%s °C)" % [number(kelvin), number(kelvin - 273.15)]
