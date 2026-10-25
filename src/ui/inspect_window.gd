class_name InspectWindow
extends PanelContainer
## A window describing one body, with live values. Drag it by its title;
## pin it to keep it open while inspecting other bodies; close it with ×.
## It closes by itself when its body is removed.

signal closed(window: InspectWindow)
signal pin_changed(window: InspectWindow)

const REFRESH_SECONDS: float = 0.2
const WIDTH: float = 176.0
const KIND_KEYS: Dictionary[CelestialBody.Kind, String] = {
	CelestialBody.Kind.STAR: "KIND_STAR",
	CelestialBody.Kind.PLANET: "KIND_PLANET",
	CelestialBody.Kind.DWARF_PLANET: "KIND_DWARF_PLANET",
	CelestialBody.Kind.MOON: "KIND_MOON",
	CelestialBody.Kind.BLACK_HOLE: "KIND_BLACK_HOLE",
}

var simulation: Simulation
var body_index: int = -1
var pinned: bool = false

var _title: Label
var _pin: Button
var _rows: GridContainer
var _since_refresh: float = 0.0
var _dragging: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 4)
	add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 2)
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	header.gui_input.connect(_header_input)
	column.add_child(header)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_child(_title)
	_pin = _header_button("INSPECT_PIN")
	_pin.toggle_mode = true
	_pin.toggled.connect(func(on: bool) -> void:
		pinned = on
		_pin.text = "INSPECT_PINNED" if on else "INSPECT_PIN"
		pin_changed.emit(self)
	)
	header.add_child(_pin)
	var close: Button = _header_button("×")
	close.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	close.pressed.connect(close_window)
	header.add_child(close)
	_rows = GridContainer.new()
	_rows.columns = 2
	_rows.add_theme_constant_override(&"h_separation", 6)
	_rows.add_theme_constant_override(&"v_separation", 0)
	column.add_child(_rows)


func show_body(sim: Simulation, index: int) -> void:
	simulation = sim
	body_index = index
	refresh()


func close_window() -> void:
	closed.emit(self)
	queue_free()


func set_pinned(on: bool) -> void:
	_pin.button_pressed = on


func _process(delta: float) -> void:
	_since_refresh += delta
	if _since_refresh >= REFRESH_SECONDS:
		_since_refresh = 0.0
		refresh()


## The rows currently shown, as [label key, value] pairs.
func rows() -> Array[PackedStringArray]:
	var found: Array[PackedStringArray] = []
	var children: Array[Node] = _rows.get_children()
	for k: int in range(0, children.size() - 1, 2):
		found.append(PackedStringArray([(children[k] as Label).text, (children[k + 1] as Label).text]))
	return found


func refresh() -> void:
	if simulation == null or body_index < 0:
		return
	if body_index >= simulation.system.size() or not simulation.is_present(body_index):
		close_window()
		return
	var system: StarSystem = simulation.system
	var b: CelestialBody = system.body(body_index)
	_title.text = Format.body_name(b).to_upper()
	var values: Array[PackedStringArray] = []
	values.append(_row("INSPECT_KIND", tr(KIND_KEYS[b.kind])))
	if b.is_star():
		values.append(_row("INSPECT_MASS", Format.tr_units("UNIT_SUNS", Format.significant(b.mass, 3))))
		values.append(_row("INSPECT_RADIUS", Format.tr_units("UNIT_KM", Format.number(Units.km_from_au(b.radius)))))
		values.append(_row("INSPECT_LUMINOSITY", Format.tr_units("UNIT_SUNS", Format.significant(b.luminosity, 3))))
		values.append(_row("INSPECT_TEMPERATURE", Format.temperature(b.temperature)))
		values.append(_row("INSPECT_HABITABLE_ZONE", "%s – %s" % [
			Format.significant(Astro.habitable_zone_inner(b.luminosity), 3),
			Format.distance(Astro.habitable_zone_outer(b.luminosity)),
		]))
		_add_orbit(values)
	elif b.kind == CelestialBody.Kind.BLACK_HOLE:
		values.append(_row("INSPECT_MASS", Format.tr_units("UNIT_SUNS", Format.significant(b.mass, 3))))
		values.append(_row("INSPECT_RADIUS", Format.tr_units("UNIT_KM", Format.number(Units.km_from_au(b.radius), 1))))
		_add_orbit(values)
	else:
		values.append(_row("INSPECT_MASS", _mass_text(b.mass)))
		values.append(_row("INSPECT_RADIUS", Format.tr_units("UNIT_KM", Format.number(Units.km_from_au(b.radius)))))
		values.append(_row("INSPECT_GRAVITY", Format.gravity(Astro.surface_gravity(b.mass, b.radius))))
		var x: float = system.x(body_index)
		var y: float = system.y(body_index)
		var z: float = system.z(body_index)
		var star: int = simulation.main_star_at(x, y, z)
		if star != -1:
			var star_distance: float = system.distance(star, body_index)
			values.append(_row("INSPECT_STAR_DISTANCE", Format.distance(star_distance)))
			values.append(_row("INSPECT_LIGHT_TIME", Format.duration(Units.light_time_seconds(star_distance))))
		var parent: int = simulation.parent_of(body_index)
		if b.kind == CelestialBody.Kind.MOON and parent != -1:
			values.append(_row("INSPECT_PARENT_DISTANCE", Format.distance(system.distance(parent, body_index))))
		_add_orbit(values)
		values.append(_row("INSPECT_ROTATION", _rotation_text(b.rotation_hours)))
		values.append(_row("INSPECT_AXIAL_TILT", "%s°" % Format.significant(b.axial_tilt_deg, 3)))
		# Starlight from every star whose light has arrived, as if from one
		# star at 1 AU.
		var flux: float = simulation.flux_at(x, y, z)
		values.append(_row("INSPECT_TEMPERATURE", Format.temperature(Astro.equilibrium_temperature(flux, 1.0, b.albedo))))
		values.append(_row("INSPECT_IN_HABITABLE_ZONE", tr("YES") if flux > 0.0 and Astro.in_habitable_zone(1.0, flux) else tr("NO")))
		if b.approximate_phase and simulation.is_pristine():
			values.append(_row("INSPECT_NOTE", tr("INSPECT_APPROXIMATE_PHASE")))
	for news: Dictionary in simulation.news_for(body_index):
		var about: String = Format.body_name(system.body(news["body"])) if int(news["body"]) >= 0 else ""
		values.append(_row(
			Format.tr_units(str(news["label_key"]), about),
			Format.tr_units("NEWS_ARRIVES_IN", Format.duration(float(news["seconds"])))
		))
	_fill(values)


## What the body circles and its orbit: the real one while the system is
## untouched, else the one it is on right now.
func _add_orbit(values: Array[PackedStringArray]) -> void:
	var system: StarSystem = simulation.system
	var b: CelestialBody = system.body(body_index)
	var parent: int = simulation.parent_of(body_index)
	if parent == -1:
		if not b.is_star():
			values.append(_row("INSPECT_ORBITS", tr("INSPECT_NOTHING")))
		return
	values.append(_row("INSPECT_ORBITS", Format.body_name(system.body(parent))))
	if simulation.is_pristine() and b.orbit != null:
		var elements: Dictionary = b.orbit.elements_at(simulation.clock.time)
		values.append(_row("INSPECT_SEMI_MAJOR_AXIS", Format.distance(float(elements["a"]))))
		values.append(_row("INSPECT_ECCENTRICITY", Format.significant(float(elements["e"]), 3)))
		values.append(_row("INSPECT_PERIOD", Format.duration(b.orbit.period_years() * Units.YEAR_SECONDS)))
		return
	var orbit: PackedFloat64Array = simulation.orbit_elements(body_index)
	if orbit.is_empty():
		return
	if orbit[0] > 0.0:
		values.append(_row("INSPECT_SEMI_MAJOR_AXIS", Format.distance(orbit[0])))
		values.append(_row("INSPECT_ECCENTRICITY", Format.significant(orbit[1], 3)))
		values.append(_row("INSPECT_PERIOD", Format.duration(TAU / orbit[2] * Units.YEAR_SECONDS)))
	else:
		values.append(_row("INSPECT_ECCENTRICITY", Format.significant(orbit[1], 3)))
		values.append(_row("INSPECT_PERIOD", tr("INSPECT_PASSING")))


func _row(label_key: String, value: String) -> PackedStringArray:
	return PackedStringArray([label_key, value])


func _fill(values: Array[PackedStringArray]) -> void:
	var children: Array[Node] = _rows.get_children()
	if children.size() != values.size() * 2:
		for child: Node in children:
			_rows.remove_child(child)
			child.queue_free()
		for value: PackedStringArray in values:
			var name_label: Label = Label.new()
			name_label.theme_type_variation = &"DimLabel"
			_rows.add_child(name_label)
			var value_label: Label = Label.new()
			value_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_rows.add_child(value_label)
		children = _rows.get_children()
	for k: int in values.size():
		(children[k * 2] as Label).text = values[k][0]
		(children[k * 2 + 1] as Label).text = values[k][1]


func _mass_text(mass: float) -> String:
	var earths: float = Units.kg_from_solar_masses(mass) / Units.EARTH_MASS_KG
	if earths >= 1e-4:
		return Format.tr_units("UNIT_EARTHS", Format.significant(earths, 3))
	return Format.tr_units("UNIT_KG", Format.scientific(Units.kg_from_solar_masses(mass), 3))


func _rotation_text(hours: float) -> String:
	var text: String = Format.duration(absf(hours) * 3600.0)
	return Format.tr_units("INSPECT_RETROGRADE", text) if hours < 0.0 else text


func _header_button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = &"ArrowButton"
	return button


func _header_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		if button.pressed:
			move_to_front()
		accept_event()
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and _dragging:
		var limit: Vector2 = get_viewport_rect().size - size
		position = (position + motion.relative).clamp(Vector2.ZERO, limit.max(Vector2.ZERO)).round()
		accept_event()
