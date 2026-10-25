class_name UpdateInstaller
extends RefCounted
## Puts a downloaded build in place of the running one. The archive is
## unpacked into a staging folder first, so a broken download changes
## nothing; then each file of the game is moved aside (to "<name>.old":
## a running program can be renamed, not overwritten) and the new one moved
## in. The next start clears the old files away.

const STAGING: String = ".update"
const OLD_SUFFIX: String = ".old"
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


## Unpacks the archive and swaps its files in. Returns what went wrong
## (nothing when it worked).
static func install(zip_path: String, install_dir: String) -> PackedStringArray:
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
	for name: String in names:
		var target: String = install_dir.path_join(name)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target + OLD_SUFFIX)
			if DirAccess.rename_absolute(target, target + OLD_SUFFIX) != OK:
				errors.append("cannot move %s aside" % name)
				continue
		if DirAccess.rename_absolute(staging.path_join(name), target) != OK:
			errors.append("cannot put %s in place" % name)
			continue
		if OS.get_name() != "Windows" and (name.ends_with(".x86_64") or name.ends_with(".so")):
			FileAccess.set_unix_permissions(target, EXECUTABLE)
	return errors


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
