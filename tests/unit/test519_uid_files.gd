extends SceneTree
## #519 (audit: commit missing .uid files): every tracked `.gd` script must
## have its `.gd.uid` committed next to it, so opening the editor (or running
## `--import`) does not dirty the tree and uid:// references stay stable.
##
## Checks against `git ls-files` rather than the filesystem, because an import
## pass (CI runs one) generates missing `.uid` files locally and would hide the
## gap. Also flags orphan `.uid` files whose `.gd` is no longer tracked.
## Falls back to a filesystem walk (with a warning) when git is unavailable.

var _fails := 0

func _check(label: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	print("[519] ", label, " -> ", "PASS" if ok else "FAIL")

func _initialize() -> void:
	_run.call_deferred()

func _git_files() -> PackedStringArray:
	var out: Array = []
	var root := ProjectSettings.globalize_path("res://")
	var code := OS.execute("git", ["-C", root, "ls-files", "--cached", "--", "*.gd", "*.gd.uid"], out, true)
	if code != 0 or out.is_empty():
		return PackedStringArray()
	var files := PackedStringArray()
	for line in String(out[0]).split("\n", false):
		files.append(line.strip_edges())
	return files

func _walk(dir_path: String, files: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		_walk(dir_path.path_join(sub), files)
	for f in dir.get_files():
		if f.ends_with(".gd") or f.ends_with(".gd.uid"):
			files.append(dir_path.path_join(f).trim_prefix("res://"))

func _run() -> void:
	var files := _git_files()
	var source := "git ls-files"
	if files.is_empty():
		print("[519] WARNING: git unavailable, falling back to a filesystem walk")
		source = "filesystem"
		_walk("res://", files)
	var gd := {}
	var uid := {}
	for f in files:
		if f.ends_with(".gd.uid"):
			uid[f.trim_suffix(".uid")] = true
		elif f.ends_with(".gd"):
			gd[f] = true
	_check("found .gd scripts via %s (%d)" % [source, gd.size()], gd.size() > 0)

	var missing: Array = []
	for f in gd:
		if not uid.has(f):
			missing.append(f)
	missing.sort()
	for f in missing:
		print("[519]   missing: ", f, ".uid")
	_check("every .gd has a committed .uid (%d missing)" % missing.size(), missing.is_empty())

	var orphans: Array = []
	for f in uid:
		if not gd.has(f):
			orphans.append(f)
	orphans.sort()
	for f in orphans:
		print("[519]   orphan: ", f, ".uid")
	_check("no orphan .uid without its .gd (%d orphans)" % orphans.size(), orphans.is_empty())

	print("RESULT: ", "ALL PASS" if _fails == 0 else "%d FAIL" % _fails)
	quit(0 if _fails == 0 else 1)
