extends SceneTree
## #98 (Foundation E1) harness: EnemyDefinition resource - stats + reward
## table per enemy type, opt-in with exact current fallback.
##
## Legs:
##   (a) enemy WITHOUT a definition keeps the exact current stats and
##       reward behavior (export fallback unchanged).
##   (b) enemy WITH a definition uses the definition's stats as a set.
##   (c) definition reward_table rolls identically to a directly assigned
##       table (same drop result on death).
##   (d) BOTH assigned: the direct reward_table WINS (instance override).
##   (e) null everywhere: no drop (existing null behavior preserved).
## Fail-when-broken: (b)/(c)/(d) fail on current main (no definition
## support) - exercised stringly via load()/set()/get() so the harness
## RUNS on the old base and reports FAIL legs instead of a parse error.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[98] ", name, " -> PASS")
	else:
		failures += 1
		print("[98] ", name, " -> FAIL")

func _drop_labels(parent: Node) -> Array:
	var out: Array = []
	for c in parent.get_children():
		if c.has_node("NameLabel"):
			out.append(c.get_node("NameLabel").text)
	return out

func _initialize() -> void:
	var def_script: Script = load("res://scripts/enemy_definition.gd")
	_check(def_script != null, "EnemyDefinition resource script exists")
	var enemy_scene: PackedScene = load("res://scenes/enemy.tscn")
	var demo_table: Resource = load("res://resources/rewards/demo_table.tres")
	_check(demo_table != null, "demo reward table loads (fixture)")
	if def_script == null or enemy_scene == null or demo_table == null:
		print("[98] DONE failures=", failures)
		quit(failures)
		return

	# (a) fallback: no definition -> exact current stats.
	# NOTE: _ready defers to the first frame in a SceneTree harness, so
	# hp init and definition overrides are read AFTER a process frame.
	var e1: Node = enemy_scene.instantiate()
	root.add_child(e1)
	await process_frame
	_check(e1.get("definition") == null, "(a) no definition assigned")
	_check(e1.get("max_hp") == 30 and e1.get("hp") == 30, "(a) fallback max_hp/hp 30 unchanged")
	_check(is_equal_approx(e1.get("speed"), 110.0), "(a) fallback speed 110 unchanged")
	_check(e1.get("contact_damage") == 10, "(a) fallback contact_damage 10 unchanged")
	_check(is_equal_approx(e1.get("contact_cooldown"), 0.8), "(a) fallback contact_cooldown 0.8 unchanged")
	_check(is_equal_approx(e1.get("contact_range"), 40.0), "(a) fallback contact_range 40 unchanged")

	# (b) definition stats take effect as a set (assigned before _ready).
	var def_b: Resource = def_script.new()
	def_b.set("max_hp", 55)
	def_b.set("speed", 140.0)
	def_b.set("contact_damage", 7)
	def_b.set("contact_cooldown", 1.5)
	def_b.set("contact_range", 60.0)
	var e2: Node = enemy_scene.instantiate()
	e2.set("definition", def_b)
	root.add_child(e2)
	await process_frame
	_check(e2.get("max_hp") == 55 and e2.get("hp") == 55, "(b) definition max_hp 55 takes effect (hp init from definition)")
	_check(is_equal_approx(e2.get("speed"), 140.0), "(b) definition speed 140 takes effect")
	_check(e2.get("contact_damage") == 7, "(b) definition contact_damage 7 takes effect")
	_check(is_equal_approx(e2.get("contact_cooldown"), 1.5), "(b) definition contact_cooldown 1.5 takes effect")
	_check(is_equal_approx(e2.get("contact_range"), 60.0), "(b) definition contact_range 60 takes effect")
	e2.apply_damage(10)
	_check(e2.get("hp") == 45, "(b) damage applies against definition-based hp (55-10=45)")

	# (c) definition reward_table rolls identically to direct assignment.
	var area := Node2D.new()
	root.add_child(area)
	var def_c: Resource = def_script.new()
	def_c.set("reward_table", demo_table)
	var e_def: Node = enemy_scene.instantiate()
	e_def.set("definition", def_c)
	e_def.position = Vector2(100, 100)
	var e_dir: Node = enemy_scene.instantiate()
	e_dir.set("reward_table", demo_table)
	e_dir.position = Vector2(200, 100)
	area.add_child(e_def)
	area.add_child(e_dir)
	await process_frame # let _ready init hp before the kills
	e_def.apply_damage(999)
	e_dir.apply_damage(999)
	await process_frame
	await process_frame
	var labels := _drop_labels(area)
	print("[98] (c) drops: ", labels)
	_check(labels.size() == 2, "(c) both definition-only and direct-only enemies drop")
	_check(labels.count("Placeholder Bolt") == 2, "(c) definition reward rolls identically to direct assignment (same entry)")

	# (d) BOTH assigned: direct reward_table WINS (instance override).
	var entry_script: Script = load("res://scripts/reward_entry.gd")
	var table_script: Script = load("res://scripts/reward_table.gd")
	var other_entry: Resource = entry_script.new()
	other_entry.set("spell", load("res://resources/spells/fire_ball.tres"))
	other_entry.set("weight", 1.0)
	var other_table: Resource = table_script.new()
	# Typed Array[RewardEntry] - a plain array is rejected by the export type.
	other_table.set("entries", Array([other_entry], TYPE_OBJECT, "Resource", entry_script))
	_check(other_table.get("entries").size() == 1, "(d) fixture table built with Fire Ball entry")
	var def_d: Resource = def_script.new()
	def_d.set("reward_table", demo_table) # definition says Placeholder Bolt
	var e_both: Node = enemy_scene.instantiate()
	e_both.set("definition", def_d)
	e_both.set("reward_table", other_table) # direct says Fire Ball
	e_both.position = Vector2(300, 100)
	area.add_child(e_both)
	await process_frame # _ready hp init before the kill
	e_both.apply_damage(999)
	await process_frame
	await process_frame
	labels = _drop_labels(area)
	print("[98] (d) drops: ", labels)
	_check(labels.count("Fire Ball") == 1, "(d) direct reward_table WINS over definition table (both assigned)")
	_check(labels.count("Placeholder Bolt") == 2, "(d) definition table did not roll while direct assigned")

	# (e) null everywhere: definition without a table + no direct table
	# -> no drop (existing null behavior preserved).
	var def_e: Resource = def_script.new()
	var e_none: Node = enemy_scene.instantiate()
	e_none.set("definition", def_e)
	e_none.position = Vector2(400, 100)
	area.add_child(e_none)
	await process_frame # _ready hp init before the kill
	e_none.apply_damage(999)
	await process_frame
	await process_frame
	labels = _drop_labels(area)
	_check(labels.size() == 3, "(e) null definition table + no direct table -> no drop (null behavior preserved)")

	if failures == 0:
		print("[98] PASS")
	else:
		print("[98] DONE failures=", failures)
	quit(failures)
