class_name NotificationFeed
extends VBoxContainer
## Short notices of what happened (collisions, bodies torn into rings,
## impacts), newest at the bottom; each fades after a few seconds. Clicking
## one asks to look at the body it is about.

signal focus_requested(body: int)

const LIFETIME: float = 8.0
const FADE: float = 1.5
const MAX_SHOWN: int = 4


func _ready() -> void:
	add_theme_constant_override(&"separation", 1)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Adds a notice about a body (or -1). A notice with the same key, while
## still shown, is updated instead (and shown afresh).
func push(text: String, body: int, key: String = "") -> void:
	if not key.is_empty():
		for node: Node in get_children():
			if node.get_meta(&"key", "") == key:
				var shown: Button = node as Button
				shown.text = text
				shown.set_meta(&"age", 0.0)
				shown.set_meta(&"count", count(key) + 1)
				return
	var entry: Button = Button.new()
	entry.set_meta(&"key", key)
	entry.set_meta(&"count", 1)
	entry.text = text
	entry.flat = true
	entry.focus_mode = Control.FOCUS_NONE
	entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Long notices wrap within the corner instead of running under the date.
	entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	entry.theme_type_variation = &"ArrowButton"
	entry.set_meta(&"age", 0.0)
	entry.pressed.connect(func() -> void:
		if body >= 0:
			focus_requested.emit(body))
	add_child(entry)
	while get_child_count() > MAX_SHOWN:
		var oldest: Node = get_child(0)
		remove_child(oldest)
		oldest.queue_free()


## How many times a keyed notice still shown has been pushed (0 if none).
func count(key: String) -> int:
	for node: Node in get_children():
		if node.get_meta(&"key", "") == key:
			return int(node.get_meta(&"count", 1))
	return 0


func texts() -> PackedStringArray:
	var found: PackedStringArray = []
	for entry: Node in get_children():
		found.append((entry as Button).text)
	return found


func entry(index: int) -> Button:
	return get_child(index) as Button


func _process(delta: float) -> void:
	for node: Node in get_children():
		var entry: Button = node as Button
		var age: float = float(entry.get_meta(&"age")) + delta
		entry.set_meta(&"age", age)
		entry.modulate.a = clampf((LIFETIME - age) / FADE, 0.0, 1.0)
		if age >= LIFETIME:
			remove_child(entry)
			entry.queue_free()
