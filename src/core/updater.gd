class_name Updater
extends Node
## Keeps an exported game up to date from its GitHub releases: looks for a
## newer build on the player's channel, then on request downloads it,
## checks its SHA-256, puts its files in place (see UpdateInstaller) and
## starts the new version. Only an exported game updates itself; from the
## editor or the tests it stays disabled.

signal state_changed

enum State { DISABLED, IDLE, CHECKING, UP_TO_DATE, AVAILABLE, DOWNLOADING, INSTALLING, RESTARTING, FAILED }

const HEADERS: PackedStringArray = ["Accept: application/vnd.github+json", "User-Agent: PixelSpaceSandbox-updater"]
## Seconds the "restarting" message stays before the new version starts.
const RESTART_DELAY: float = 1.5

var state: State = State.IDLE
var channel: UpdateChecker.Channel = UpdateChecker.Channel.STABLE
var current_version: String = GameVersion.current()
## The release on offer (see UpdateChecker.parse_releases).
var release: Dictionary = {}
## Share of the download done (0..1).
var progress: float = 0.0
## Translation key of what went wrong, when FAILED.
var error_key: String = ""

var _http: HTTPRequest
var _download_path: String = ""
## The worker-thread task putting the files in place (it may wait for busy
## files), and what it reported.
var _install_task: int = -1
var _install_errors: PackedStringArray = []


## Whether this run of the game can update itself: an exported game that
## knows where its releases are.
static func supported() -> bool:
	return (
		OS.has_feature("template") and not OS.has_feature("editor")
		and not str(ProjectSettings.get_setting(UpdateChecker.REPOSITORY_SETTING, "")).is_empty()
	)


## The folder the running game is in.
static func install_dir() -> String:
	return OS.get_executable_path().get_base_dir()


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 30.0
	# One chunk is read per frame: 64 KiB (the default) caps a download at about 4 MB/s.
	_http.download_chunk_size = 1 << 20
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	if not supported():
		_set_state(State.DISABLED)


func _exit_tree() -> void:
	if _install_task != -1:
		WorkerThreadPool.wait_for_task_completion(_install_task)
		_install_task = -1


func _process(_delta: float) -> void:
	if _install_task != -1 and WorkerThreadPool.is_task_completed(_install_task):
		WorkerThreadPool.wait_for_task_completion(_install_task)
		_install_task = -1
		_finish_install()
	if state == State.DOWNLOADING:
		var total: int = _http.get_body_size()
		var size: int = int(release.get("size", 0))
		if total <= 0:
			total = size
		if total > 0:
			progress = clampf(float(_http.get_downloaded_bytes()) / total, 0.0, 1.0)
			state_changed.emit()


## Looks for a newer build (does nothing when disabled, the channel is off,
## or a check, download or install is under way).
func check() -> void:
	if state in [State.DISABLED, State.CHECKING, State.DOWNLOADING, State.INSTALLING, State.RESTARTING]:
		return
	if channel == UpdateChecker.Channel.OFF:
		return
	_set_state(State.CHECKING)
	_http.set_meta(&"step", "releases")
	if _http.request(UpdateChecker.releases_url(), HEADERS) != OK:
		_fail("UPDATE_ERROR_NETWORK")


## What a releases reply means (also how tests feed one in).
func handle_releases(result: int, code: int, body: String) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("UPDATE_ERROR_NETWORK")
		return
	release = UpdateChecker.pick(UpdateChecker.parse_releases(body, UpdateChecker.asset_suffix()), channel, current_version)
	_set_state(State.UP_TO_DATE if release.is_empty() else State.AVAILABLE)


## Downloads and installs the release on offer, then restarts the game.
func install() -> void:
	if state != State.AVAILABLE:
		return
	if not UpdateInstaller.can_write(install_dir()):
		_fail("UPDATE_ERROR_FOLDER")
		return
	if str(release.get("sha256_url", "")).is_empty():
		_fail("UPDATE_ERROR_CHECKSUM")
		return
	_download_path = install_dir().path_join(str(release["asset_name"]))
	progress = 0.0
	_set_state(State.DOWNLOADING)
	_http.download_file = _download_path
	_http.set_meta(&"step", "download")
	if _http.request(str(release["asset_url"]), HEADERS) != OK:
		_fail("UPDATE_ERROR_NETWORK")


## The release's page, for when the game cannot update itself.
func open_page() -> void:
	if not str(release.get("page_url", "")).is_empty():
		OS.shell_open(str(release["page_url"]))


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	match str(_http.get_meta(&"step", "")):
		"releases":
			handle_releases(result, code, body.get_string_from_utf8())
		"download":
			_http.download_file = ""
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				_fail("UPDATE_ERROR_NETWORK")
				return
			_set_state(State.INSTALLING)
			_http.set_meta(&"step", "checksum")
			if _http.request(str(release["sha256_url"]), HEADERS) != OK:
				_fail("UPDATE_ERROR_NETWORK")
		"checksum":
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				_fail("UPDATE_ERROR_NETWORK")
				return
			var expected: String = UpdateChecker.sha256_from_listing(body.get_string_from_utf8(), str(release["asset_name"]))
			if expected.is_empty() or expected != UpdateChecker.file_sha256(_download_path):
				_fail("UPDATE_ERROR_CHECKSUM")
				return
			# On a worker thread: the window stays responsive while busy
			# files are tried again.
			var zip_path: String = _download_path
			var folder: String = install_dir()
			_install_task = WorkerThreadPool.add_task(
				func() -> void: _install_errors = UpdateInstaller.install(zip_path, folder),
				false,
				"Install update"
			)


func _finish_install() -> void:
	DirAccess.remove_absolute(_download_path)
	if not _install_errors.is_empty():
		push_warning("Update: %s" % "; ".join(_install_errors))
		_fail("UPDATE_ERROR_INSTALL")
		return
	_set_state(State.RESTARTING)
	get_tree().create_timer(RESTART_DELAY).timeout.connect(_restart)


func _restart() -> void:
	OS.create_process(OS.get_executable_path(), [])
	get_tree().quit()


func _fail(key: String) -> void:
	if not _download_path.is_empty() and FileAccess.file_exists(_download_path):
		DirAccess.remove_absolute(_download_path)
	error_key = key
	_set_state(State.FAILED)


func _set_state(new_state: State) -> void:
	state = new_state
	state_changed.emit()
