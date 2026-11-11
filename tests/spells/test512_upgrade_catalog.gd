extends SceneTree
## #512: UpgradeCatalog (moved out of Main._ready) hands SpellProgress every
## upgrade row under data/upgrades, once each, and a fresh array per call.
## Run: godot --headless --fixed-fps 60 --path . -s tests/spells/test512_upgrade_catalog.gd

var _fails := 0
var _checks := 0

func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[512u] ", label, " -> ", "PASS" if ok else "FAIL")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var a := UpgradeCatalog.all()
	var b := UpgradeCatalog.all()
	_check("rows are returned", a.size() > 0)
	_check("a fresh array per call", not is_same(a, b) and a.size() == b.size())
	a.clear()
	_check("clearing one copy leaves the catalog intact", UpgradeCatalog.all().size() == b.size())
	var files := 0
	var on_disk := {}
	for fn in DirAccess.get_files_at("res://data/upgrades"):
		if fn.ends_with(".tres"):
			files += 1
			on_disk["res://data/upgrades/" + fn] = true
	var seen := {}
	var all_ok := true
	for u: SpellUpgrade in b:
		all_ok = all_ok and u != null and on_disk.has(u.resource_path) and not seen.has(u.resource_path)
		seen[u.resource_path] = true
	_check("every row is a distinct upgrade .tres", all_ok)
	_check("every upgrade .tres is a row (%d files)" % files, seen.size() == files)
	print("test512u done: %d checks, %d failures" % [_checks, _fails])
	print("[512u] RESULT: ", "ALL PASS" if _fails == 0 else "FAIL")
	quit(0 if _fails == 0 else 1)
