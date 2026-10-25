class_name TimelineBar
extends HBoxContainer
## The timeline above the toolbar: a mark per snapshot, oldest first
## (brighter for those taken before a change), each saying when and why;
## clicking one goes back to it and pauses there.

signal rewound

var simulation: Simulation

var _shown: int = -1


func _ready() -> void:
	add_theme_constant_override(&"separation", 1)
	alignment = BoxContainer.ALIGNMENT_END
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func tick_count() -> int:
	return get_child_count()


func tick(index: int) -> Button:
	return get_child(index) as Button


func _process(_delta: float) -> void:
	if simulation == null or simulation.timeline == null:
		return
	var snapshots: Array[Dictionary] = simulation.timeline.snapshots
	var key: int = snapshots.size() * 1000003 + (hash(snapshots.back()["time"]) if not snapshots.is_empty() else 0)
	if key != _shown:
		_shown = key
		_rebuild(snapshots)


func _rebuild(snapshots: Array[Dictionary]) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for index: int in snapshots.size():
		var snapshot: Dictionary = snapshots[index]
		var mark: Button = Button.new()
		mark.custom_minimum_size = Vector2(5, 7)
		mark.focus_mode = Control.FOCUS_NONE
		mark.theme_type_variation = &"IconButton"
		var change: bool = snapshot["label_key"] != Timeline.AUTO
		mark.modulate = Palette.color(&"ui_accent") if change else Palette.color(&"ui_text_dim")
		var why: String = tr("SNAPSHOT_AUTO") if not change else tr("SNAPSHOT_BEFORE")
		mark.tooltip_text = "%s  ·  %s" % [Format.date(float(snapshot["time"]), true), why]
		mark.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		mark.pressed.connect(func() -> void:
			simulation.timeline.rewind(simulation, index)
			simulation.clock.paused = true
			rewound.emit())
		add_child(mark)
