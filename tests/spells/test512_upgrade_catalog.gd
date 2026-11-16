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
	# Loader-order guard (#700): in a headless -s run, touching the catalog
	# cold can hand back upgrade .tres rows WITHOUT their script instanced
	# (script members read null; seen locally and on clean main). Load the
	# Spell/SpellUpgrade scripts first, then the catalog DYNAMICALLY - a
	# static UpgradeCatalog/SpellUpgrade reference in this file would
	# compile the catalog (and its preloads) before these loads run.
	load("res://game/spells/spell.gd")
	load("res://game/spells/spell_upgrade.gd")
	var catalog: GDScript = load("res://game/spells/upgrade_catalog.gd")
	var a: Array = catalog.all()
	var b: Array = catalog.all()
	_check("rows are returned", a.size() > 0)
	_check("a fresh array per call", not is_same(a, b) and a.size() == b.size())
	a.clear()
	_check("clearing one copy leaves the catalog intact", catalog.all().size() == b.size())
	var files := 0
	var on_disk := {}
	for fn in DirAccess.get_files_at("res://data/upgrades"):
		if fn.ends_with(".tres"):
			files += 1
			on_disk["res://data/upgrades/" + fn] = true
	var seen := {}
	var all_ok := true
	for u in b:
		all_ok = all_ok and u != null and on_disk.has(u.resource_path) and not seen.has(u.resource_path)
		seen[u.resource_path] = true
	_check("every row is a distinct upgrade .tres", all_ok)
	_check("every upgrade .tres is a row (%d files)" % files, seen.size() == files)
	# #703: upgrade PATHS are gone (Daniel 2026-11-15). Each spell has one
	# fixed linear chain: at most ONE successor row per source spell, and a
	# tier-2/3 row's source must itself be the result of a chain row.
	var rows_per_source := {}
	var results := {}
	for u in b:
		_check("row %s has its script instanced" % u.resource_path, u.get("tier") != null)
		if u.source_spell != null:
			rows_per_source[u.source_spell] = int(rows_per_source.get(u.source_spell, 0)) + 1
		if u.result_spell != null:
			results[u.result_spell] = u
	var chain_ok := true
	for source in rows_per_source:
		if int(rows_per_source[source]) > 1:
			chain_ok = false
			print("[512u] BRANCH: ", source.resource_path, " has ", rows_per_source[source], " successor rows")
	_check("no spell has more than one successor upgrade (linear chains)", chain_ok)
	var link_ok := true
	for u in b:
		if u.tier >= 2 and not results.has(u.source_spell):
			link_ok = false
			print("[512u] BROKEN CHAIN: ", u.resource_path, " tier ", u.tier, " source has no incoming row")
	_check("tier 2/3 rows extend an existing chain link", link_ok)
	print("test512u done: %d checks, %d failures" % [_checks, _fails])
	print("[512u] RESULT: ", "ALL PASS" if _fails == 0 else "FAIL")
	quit(0 if _fails == 0 else 1)
