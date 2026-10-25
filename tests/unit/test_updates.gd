extends TestCase
## Updating the game from its GitHub releases: versions compare as semver
## (a test build comes before the version it leads to), the newest release
## for the player's channel and system is chosen, the download is checked
## against its SHA-256, and the new files replace the old ones, which are
## cleared away on the next start.

const WORK: String = "user://test_updates"

## A GitHub "list releases" reply, newest first as GitHub sends it.
const REPLY: String = """[
	{"tag_name": "v0.2.0-dev.12", "name": "dev 12", "draft": false, "prerelease": true, "body": "",
	 "html_url": "https://github.com/o/r/releases/tag/v0.2.0-dev.12",
	 "assets": [
		{"name": "PixelSpaceSandbox-v0.2.0-dev.12-windows.zip", "size": 100, "browser_download_url": "https://dl/w12.zip"},
		{"name": "PixelSpaceSandbox-v0.2.0-dev.12-windows.zip.sha256", "size": 90, "browser_download_url": "https://dl/w12.zip.sha256"},
		{"name": "PixelSpaceSandbox-v0.2.0-dev.12-linux.zip", "size": 100, "browser_download_url": "https://dl/l12.zip"}
	 ]},
	{"tag_name": "v0.3.0-dev.13", "name": "draft", "draft": true, "prerelease": true, "body": "", "html_url": "", "assets": [
		{"name": "PixelSpaceSandbox-v0.3.0-dev.13-windows.zip", "size": 100, "browser_download_url": "https://dl/w13.zip"}
	 ]},
	{"tag_name": "v0.1.0", "name": "stable", "draft": false, "prerelease": false, "body": "", "html_url": "https://github.com/o/r/releases/tag/v0.1.0",
	 "assets": [
		{"name": "PixelSpaceSandbox-v0.1.0-windows.zip", "size": 100, "browser_download_url": "https://dl/w010.zip"}
	 ]},
	{"tag_name": "v0.2.0-dev.9", "name": "dev 9", "draft": false, "prerelease": true, "body": "", "html_url": "",
	 "assets": [
		{"name": "PixelSpaceSandbox-v0.2.0-dev.9-windows.zip", "size": 100, "browser_download_url": "https://dl/w9.zip"}
	 ]}
]"""


func before_each() -> void:
	_remove(WORK)
	DirAccess.make_dir_recursive_absolute(WORK)


func after_each() -> void:
	_remove(WORK)


static func _remove(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	for sub: String in dir.get_directories():
		_remove(path.path_join(sub))
	DirAccess.remove_absolute(path)


static func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_versions_compare_as_semver() -> void:
	assert_eq(GameVersion.compare("v0.2.0-dev.9", "0.2.0-dev.12"), -1, "build 9 before build 12 (as numbers)")
	assert_eq(GameVersion.compare("0.2.0-dev.12", "0.2.0"), -1, "a test build comes before the version it leads to")
	assert_eq(GameVersion.compare("0.2.0", "0.2.1-dev.1"), -1, "and after the previous one")
	assert_eq(GameVersion.compare("0.10.0", "0.9.9"), 1, "numbers, not text")
	assert_eq(GameVersion.compare("v1.0.0", "1.0.0"), 0, "the v does not matter")
	assert_true(GameVersion.is_valid("0.2.0-dev.3"))
	assert_false(GameVersion.is_valid("latest"))
	assert_true(GameVersion.is_test_build("0.2.0-dev.3"))
	assert_false(GameVersion.is_test_build("0.2.0"))


func test_the_newest_release_for_the_channel_and_system_is_chosen() -> void:
	var releases: Array[Dictionary] = UpdateChecker.parse_releases(REPLY, "-windows.zip")
	assert_eq(releases.size(), 3, "drafts are left out")
	var newest: Dictionary = UpdateChecker.pick(releases, UpdateChecker.Channel.TESTING, "0.2.0-dev.9")
	assert_eq(newest.get("tag"), "v0.2.0-dev.12", "the testing channel sees test builds")
	assert_eq(newest.get("asset_url"), "https://dl/w12.zip")
	assert_eq(newest.get("sha256_url"), "https://dl/w12.zip.sha256", "with its checksum")
	assert_eq(newest.get("size"), 100)
	assert_true(UpdateChecker.pick(releases, UpdateChecker.Channel.TESTING, "0.2.0-dev.12").is_empty(), "nothing newer than what runs")
	assert_true(UpdateChecker.pick(releases, UpdateChecker.Channel.STABLE, "0.0.9").get("tag") == "v0.1.0", "the stable channel sees only final versions")
	assert_true(UpdateChecker.pick(releases, UpdateChecker.Channel.STABLE, "0.2.0-dev.1").is_empty(), "and never goes back")
	assert_true(UpdateChecker.pick(releases, UpdateChecker.Channel.OFF, "0.0.1").is_empty(), "off is off")
	var linux: Array[Dictionary] = UpdateChecker.parse_releases(REPLY, "-linux.zip")
	assert_eq(UpdateChecker.pick(linux, UpdateChecker.Channel.TESTING, "0.1.0").get("asset_url"), "https://dl/l12.zip", "each system its own file")
	assert_eq(UpdateChecker.parse_releases("not json", "-windows.zip").size(), 0, "a broken reply gives nothing")


func test_downloads_are_checked_against_their_sha256() -> void:
	var path: String = WORK.path_join("abc.txt")
	_write(path, "abc")
	var expected: String = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
	assert_eq(UpdateChecker.file_sha256(path), expected, "the standard test vector")
	var listing: String = "%s  PixelSpaceSandbox-v0.2.0-dev.12-windows.zip\n" % expected.to_upper()
	assert_eq(UpdateChecker.sha256_from_listing(listing, "PixelSpaceSandbox-v0.2.0-dev.12-windows.zip"), expected, "read from the .sha256 file")
	assert_eq(UpdateChecker.sha256_from_listing("nonsense", "x.zip"), "", "nothing readable")


func test_a_new_build_replaces_the_old_files_and_they_are_cleared_later() -> void:
	var install: String = WORK.path_join("game")
	DirAccess.make_dir_recursive_absolute(install)
	_write(install.path_join("PixelSpaceSandbox.exe"), "old game")
	_write(install.path_join("libpixelspace.windows.x86_64.dll"), "old kernel")
	_write(install.path_join("settings_note.txt"), "the player's file")
	var zip_path: String = WORK.path_join("update.zip")
	var packer: ZIPPacker = ZIPPacker.new()
	assert_eq(packer.open(zip_path), OK)
	for entry: Array in [["PixelSpaceSandbox.exe", "new game"], ["libpixelspace.windows.x86_64.dll", "new kernel"]]:
		packer.start_file(entry[0])
		packer.write_file((entry[1] as String).to_utf8_buffer())
		packer.close_file()
	packer.close()
	assert_true(UpdateInstaller.can_write(install), "the game's folder can be written")
	var errors: PackedStringArray = UpdateInstaller.install(zip_path, install)
	assert_true(errors.is_empty(), "; ".join(errors))
	assert_eq(FileAccess.get_file_as_string(install.path_join("PixelSpaceSandbox.exe")), "new game", "the new game is in place")
	assert_eq(FileAccess.get_file_as_string(install.path_join("libpixelspace.windows.x86_64.dll")), "new kernel")
	assert_eq(FileAccess.get_file_as_string(install.path_join("PixelSpaceSandbox.exe.old")), "old game", "the running one is only moved aside")
	assert_eq(FileAccess.get_file_as_string(install.path_join("settings_note.txt")), "the player's file", "other files are left alone")
	UpdateInstaller.clean_up(install)
	assert_false(FileAccess.file_exists(install.path_join("PixelSpaceSandbox.exe.old")), "the next start clears the old files")
	assert_false(DirAccess.dir_exists_absolute(install.path_join(UpdateInstaller.STAGING)), "and what was unpacked")
	assert_true(FileAccess.file_exists(install.path_join("settings_note.txt")))


func test_a_broken_download_changes_nothing() -> void:
	var install: String = WORK.path_join("game")
	DirAccess.make_dir_recursive_absolute(install)
	_write(install.path_join("PixelSpaceSandbox.exe"), "old game")
	var zip_path: String = WORK.path_join("update.zip")
	_write(zip_path, "this is not a zip")
	var errors: PackedStringArray = UpdateInstaller.install(zip_path, install)
	assert_false(errors.is_empty(), "the problem is reported")
	assert_eq(FileAccess.get_file_as_string(install.path_join("PixelSpaceSandbox.exe")), "old game", "the game is untouched")


func test_the_update_channel_is_a_setting() -> void:
	var path: String = WORK.path_join("settings.cfg")
	var settings: GameSettings = GameSettings.new(path)
	assert_eq(settings.update_channel, UpdateChecker.default_channel(GameVersion.current()), "follows the build at first")
	assert_eq(UpdateChecker.default_channel("0.2.0-dev.4"), UpdateChecker.Channel.TESTING, "a test build follows the test builds")
	assert_eq(UpdateChecker.default_channel("0.2.0"), UpdateChecker.Channel.STABLE)
	settings.update_channel = UpdateChecker.Channel.OFF
	settings.write()
	var again: GameSettings = GameSettings.new(path)
	again.read()
	assert_eq(again.update_channel, UpdateChecker.Channel.OFF, "and is saved")
