class_name UpdateInstaller
extends RefCounted
## Puts a downloaded build in place of the running one. The archive is
## unpacked into a staging folder first, so a broken download changes
## nothing; then each file of the game is moved aside (to "<name>.old":
## a running program can be renamed, not overwritten) and the new one moved
## in. If any file cannot be swapped, the ones already swapped go back, so
## the game is never half old and half new. The next start clears the old
## files away.

const STAGING: String = ".update"
const OLD_SUFFIX: String = ".old"
## How long to keep trying to move a busy file. On Windows an antivirus
## scans a program right after it is written and holds it meanwhile; the
## game's program, with everything packed in, is big and takes seconds.
const RETRY_SECONDS: float = 15.0
const RETRY_STEP_MSEC: int = 250
## rwxr-xr-x, for the game and its native library on Linux.
const EXECUTABLE: int = (
	FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER | FileAccess.UNIX_EXECUTE_OWNER
	| FileAccess.UNIX_READ_GROUP | FileAccess.UNIX_EXECUTE_GROUP | FileAccess.UNIX_READ_OTHER | FileAccess.UNIX_EXECUTE_OTHER
)


## Whether the game's folder can be written (not, say, a protected system
## folder), so it can update itself there.
static func can_write(install_dir: String) -> bool:
	var probe: String = install_dir.path_join(".write_test")
	var file: FileAccess = FileAccess.open(probe, FileAccess.WRITE)
	if file == null:
		return false
	file.close()
	DirAccess.remove_absolute(probe)
	return true


## Unpacks the archive and swaps its files in, trying busy files again for
## retry_seconds. Returns what went wrong (nothing when it worked). Blocks
## while it waits: call it from a worker thread.
static func install(zip_path: String, install_dir: String, retry_seconds: float = RETRY_SECONDS) -> PackedStringArray:
	var errors: PackedStringArray = []
	var staging: String = install_dir.path_join(STAGING)
	_remove_tree(staging)
	var reader: ZIPReader = ZIPReader.new()
	if reader.open(zip_path) != OK:
		errors.append("cannot open the download")
		return errors
	var names: PackedStringArray = []
	for name: String in reader.get_files():
		if name.ends_with("/"):
			continue
		if name.contains("..") or name.begins_with("/"):
			errors.append("unsafe path in the download: %s" % name)
			continue
		var target: String = staging.path_join(name)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			errors.append("cannot unpack %s" % name)
			continue
		file.store_buffer(reader.read_file(name))
		file.close()
		names.append(name)
	reader.close()
	if names.is_empty():
		errors.append("the download is empty")
	if not errors.is_empty():
		_remove_tree(staging)
		return errors
	var swapped: PackedStringArray = []
	for name: String in names:
		var target: String = install_dir.path_join(name)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var moved_aside: bool = false
		if FileAccess.file_exists(target):
			_remove(target + OLD_SUFFIX, retry_seconds)
			if _move(target, target + OLD_SUFFIX, retry_seconds) != OK:
				errors.append("cannot move %s aside" % name)
				break
			moved_aside = true
		if _move(staging.path_join(name), target, retry_seconds) != OK:
			errors.append("cannot put %s in place" % name)
			if moved_aside:
				_move(target + OLD_SUFFIX, target, retry_seconds)
			break
		swapped.append(name)
		if OS.get_name() != "Windows" and (name.ends_with(".x86_64") or name.ends_with(".so")):
			FileAccess.set_unix_permissions(target, EXECUTABLE)
	if not errors.is_empty():
		_undo(swapped, install_dir, retry_seconds)
	_remove_tree(staging)
	return errors


## Puts back the old files of an update that could not finish.
static func _undo(swapped: PackedStringArray, install_dir: String, retry_seconds: float) -> void:
	for k: int in range(swapped.size() - 1, -1, -1):
		var target: String = install_dir.path_join(swapped[k])
		_remove(target, retry_seconds)
		if FileAccess.file_exists(target + OLD_SUFFIX):
			_move(target + OLD_SUFFIX, target, retry_seconds)


static func _move(from: String, to: String, retry_seconds: float) -> Error:
	var error: Error = FAILED
	for attempt: int in 1 + ceili(retry_seconds * 1000.0 / RETRY_STEP_MSEC):
		if attempt > 0:
			OS.delay_msec(RETRY_STEP_MSEC)
		error = DirAccess.rename_absolute(from, to)
		if error == OK:
			break
	return error


static func _remove(path: String, retry_seconds: float) -> void:
	for attempt: int in 1 + ceili(retry_seconds * 1000.0 / RETRY_STEP_MSEC):
		if not FileAccess.file_exists(path):
			return
		if attempt > 0:
			OS.delay_msec(RETRY_STEP_MSEC)
		DirAccess.remove_absolute(path)


## Clears what an earlier update left behind: the old files and the
## staging folder.
static func clean_up(install_dir: String) -> void:
	var dir: DirAccess = DirAccess.open(install_dir)
	if dir == null:
		return
	for file: String in dir.get_files():
		if file.ends_with(OLD_SUFFIX):
			dir.remove(file)
	_remove_tree(install_dir.path_join(STAGING))


static func _remove_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	for sub: String in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
