class_name UpdateChecker
extends RefCounted
## Which published release, if any, the game should update to: reads
## GitHub's list of releases, keeps the ones with a file for this system,
## and picks the newest one newer than the running version on the player's
## channel. Every push to the beta branch is published as a test build
## (vX.Y.Z-dev.N, a pre-release); final versions are plain releases.

enum Channel {
	## Final versions only.
	STABLE,
	## Final versions and every test build of the beta branch.
	TESTING,
	## Never look.
	OFF,
}

## Where the releases are: "owner/name" on GitHub (a project setting, so a
## fork can point at its own).
const REPOSITORY_SETTING: String = "pixel_space_sandbox/updates/repository"
const API: String = "https://api.github.com/repos/%s/releases?per_page=20"


static func releases_url() -> String:
	return API % str(ProjectSettings.get_setting(REPOSITORY_SETTING, ""))


## The channel a build follows until the player chooses: a test build
## follows the test builds.
static func default_channel(version: String) -> Channel:
	return Channel.TESTING if GameVersion.is_test_build(version) else Channel.STABLE


## The end of the file name of this system's download.
static func asset_suffix() -> String:
	return "-windows.zip" if OS.get_name() == "Windows" else "-linux.zip"


## The releases in a GitHub reply that have a file ending in asset_suffix:
## [{tag, version, prerelease, page_url, notes, asset_name, asset_url, size,
## sha256_url}]. Drafts and unreadable entries are left out.
static func parse_releases(reply: String, suffix: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	# A JSON object, unlike JSON.parse_string, does not print a broken reply.
	var json: JSON = JSON.new()
	if json.parse(reply) != OK or not json.data is Array:
		return found
	for entry: Variant in json.data:
		if not entry is Dictionary:
			continue
		var release: Dictionary = entry
		var tag: String = str(release.get("tag_name", ""))
		if bool(release.get("draft", false)) or not GameVersion.is_valid(tag):
			continue
		var info: Dictionary = {
			"tag": tag, "version": tag.trim_prefix("v"), "prerelease": bool(release.get("prerelease", false)),
			"page_url": str(release.get("html_url", "")), "notes": str(release.get("body", "")),
		}
		var urls: Dictionary[String, String] = {}
		var sizes: Dictionary[String, int] = {}
		var assets: Variant = release.get("assets", [])
		if assets is Array:
			for asset: Variant in assets:
				if asset is Dictionary:
					var name: String = str((asset as Dictionary).get("name", ""))
					urls[name] = str((asset as Dictionary).get("browser_download_url", ""))
					sizes[name] = int((asset as Dictionary).get("size", 0))
		for name: String in urls:
			if name.to_lower().ends_with(suffix.to_lower()):
				info["asset_name"] = name
				info["asset_url"] = urls[name]
				info["size"] = sizes[name]
				info["sha256_url"] = urls.get(name + ".sha256", "")
		if info.has("asset_url"):
			found.append(info)
	return found


## The newest release newer than the running version on a channel, or empty.
static func pick(releases: Array[Dictionary], channel: Channel, current: String) -> Dictionary:
	if channel == Channel.OFF:
		return {}
	var best: Dictionary = {}
	for release: Dictionary in releases:
		if channel == Channel.STABLE and release["prerelease"]:
			continue
		if GameVersion.compare(release["version"], current) <= 0:
			continue
		if best.is_empty() or GameVersion.compare(release["version"], best["version"]) > 0:
			best = release
	return best


## The SHA-256 (lower case hex) a .sha256 listing gives for a file, as
## written by sha256sum ("<hash>  <name>"), or empty.
static func sha256_from_listing(listing: String, file_name: String) -> String:
	for line: String in listing.split("\n"):
		var parts: PackedStringArray = line.strip_edges().split(" ", false)
		if parts.size() >= 1 and parts[0].length() == 64 and parts[0].is_valid_hex_number():
			if parts.size() == 1 or parts[parts.size() - 1].trim_prefix("*") == file_name:
				return parts[0].to_lower()
	return ""


## The SHA-256 of a file (lower case hex), or empty when it cannot be read.
static func file_sha256(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		context.update(file.get_buffer(1 << 20))
	return context.finish().hex_encode()
