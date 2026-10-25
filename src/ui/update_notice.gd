class_name UpdateNotice
extends HBoxContainer
## A line on the title screen about updates: looking, up to date, a newer
## version with a button to install it, the download's progress, or what
## went wrong (with a button to open the release page). Hidden when the game
## cannot update itself.

var updater: Updater

var _label: Label
var _button: Button


func _ready() -> void:
	add_theme_constant_override(&"separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.theme_type_variation = &"DimLabel"
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_label)
	_button = Button.new()
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(_on_button)
	add_child(_button)
	updater = Updater.new()
	add_child(updater)
	updater.state_changed.connect(_refresh)
	_refresh()


func text() -> String:
	return _label.text


func action_button() -> Button:
	return _button


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _label != null:
		_refresh()


func _on_button() -> void:
	if updater.state == Updater.State.AVAILABLE:
		updater.install()
	elif updater.state == Updater.State.FAILED:
		updater.open_page()


func _refresh() -> void:
	var version: String = str(updater.release.get("version", ""))
	_button.visible = false
	visible = true
	match updater.state:
		Updater.State.DISABLED, Updater.State.IDLE:
			visible = false
		Updater.State.CHECKING:
			_label.text = tr("UPDATE_CHECKING")
		Updater.State.UP_TO_DATE:
			_label.text = tr("UPDATE_NONE")
		Updater.State.AVAILABLE:
			_label.text = Format.tr_units("UPDATE_AVAILABLE", version)
			_button.text = tr("UPDATE_INSTALL")
			_button.visible = true
		Updater.State.DOWNLOADING:
			_label.text = Format.tr_units("UPDATE_DOWNLOADING", "%d%%" % roundi(updater.progress * 100.0))
		Updater.State.INSTALLING:
			_label.text = tr("UPDATE_INSTALLING")
		Updater.State.RESTARTING:
			_label.text = Format.tr_units("UPDATE_RESTARTING", version)
		Updater.State.FAILED:
			_label.text = Format.tr_units("UPDATE_FAILED", tr(updater.error_key))
			_button.text = tr("UPDATE_OPEN_PAGE")
			_button.visible = not str(updater.release.get("page_url", "")).is_empty()
