class_name UpdateSelfTest
extends RefCounted
## A check the shipped game can run on any PC (`-- --update-self-test=<zip>`
## on the command line): while running, it installs a build from a zip over
## its own files, as an update does, and prints whether that worked. On
## Windows this is the delicate part: a running program and its loaded
## library can only be renamed, not overwritten. The Windows CI job runs it.

const FLAG: String = "--update-self-test="


static func requested() -> bool:
	return not zip_path().is_empty()


static func zip_path() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(FLAG):
			return argument.trim_prefix(FLAG)
	return ""


## Installs the zip over the running game. True when every file was put in
## place.
static func run() -> bool:
	var install_dir: String = Updater.install_dir()
	var errors: PackedStringArray = UpdateInstaller.install(zip_path(), install_dir)
	print("Update self-test: installed into %s: %s" % [install_dir, "ok" if errors.is_empty() else "; ".join(errors)])
	return errors.is_empty()
