extends SceneTree
## #496 (Colin 2026-11-10): "Keep the shop pool limited to base spells with
## no upgrades. Do not sell upgraded variants." Heavy Rain is an upgraded
## spell and must not be sold. Base vs upgraded comes from the SpellUpgrade
## DATA (resources/upgrades/*.tres result_spell), never from names.
## Run: godot --headless --path . -s scripts/test496_shop_base_spells.gd
var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[496] ", label, " -> ", "PASS" if ok else "FAIL")

func _initialize() -> void:
	var upgrades: Array[SpellUpgrade] = []
	for f in DirAccess.open("res://resources/upgrades").get_files():
		if f.ends_with(".tres"):
			var up := load("res://resources/upgrades/" + f) as SpellUpgrade
			if up != null:
				upgrades.append(up)
	_check(upgrades.size() > 0, "upgrade data loads (%d SpellUpgrades)" % upgrades.size())
	var upgraded := {} # result spell path -> upgrade id
	for up in upgrades:
		if up.result_spell != null:
			upgraded[up.result_spell.resource_path] = up.id

	var demo: ShopCatalog = load("res://resources/shop/demo_catalog.tres")
	var pool := {}
	var leaks: Array[String] = []
	for e in demo.entries:
		var s := e.good as Spell
		_check(s != null, "entry is a Spell")
		if s == null:
			continue
		pool[s.resource_path] = true
		if upgraded.has(s.resource_path):
			leaks.append("%s (%s)" % [s.spell_name, upgraded[s.resource_path]])
	_check(leaks.is_empty(), "no upgraded variant is sold %s" % [leaks])

	# Named examples from the issue, resolved through upgrade data.
	var heavy_rain := load("res://resources/spells/heavy_rain.tres") as Spell
	_check(upgraded.has(heavy_rain.resource_path), "upgrade data marks Heavy Rain as upgraded")
	_check(not pool.has(heavy_rain.resource_path), "Heavy Rain is not in the shop pool")
	for p in ["res://resources/spells/fire_ball_beam_piercing.tres", "res://resources/spells/fire_ball_split.tres"]:
		_check(upgraded.has(p) and not pool.has(p), "upgraded %s is not sold" % p.get_file())

	# Every SOURCE-only spell (an upgrade tree root) is sold: the base of
	# each tree stays buyable, so players can start the tree from the shop.
	for up in upgrades:
		var src := up.source_spell
		if src != null and not upgraded.has(src.resource_path):
			_check(pool.has(src.resource_path), "tree root %s is sold" % src.spell_name)

	# Base spells stay buyable at the flat price (Fire Ball, Water Ball...).
	var all_flat := true
	for e in demo.entries:
		if e.price != 10:
			all_flat = false
	_check(all_flat, "base spells keep the flat 10c price")
	_check(demo.entries.size() == 9, "pool is the 9 base player spells (was 39 with variants) - got %d" % demo.entries.size())

	print("[496] DONE failures=", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(failures)
