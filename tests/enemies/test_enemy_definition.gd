extends SceneTree
## #98 (Foundation E1) harness: EnemyDefinition resource - stats + reward
## table per enemy type, required on every enemy scene.
##
## Legs:
##   (a) the Mustache Warrior scene carries its definition with the exact
##       current stats.
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
	var def_script: Script = load("res://game/enemies/enemy_definition.gd")
	_check(def_script != null, "EnemyDefinition resource script exists")
	var enemy_scene: PackedScene = load("res://game/enemies/enemy.tscn")
	# Single-entry fixture table BUILT IN CODE (Placeholder Bolt). The
	# production demo_table.tres is content-owned data - #212 added the
	# summon spell entry - so loading it here would couple these exact-roll
	# assertions to unrelated content changes.
	var fix_entry_script: Script = load("res://game/economy/reward_entry.gd")
	var fix_table_script: Script = load("res://game/economy/reward_table.gd")
	var bolt_entry: Resource = fix_entry_script.new()
	bolt_entry.set("spell", load("res://data/spells/placeholder_bolt.tres"))
	bolt_entry.set("weight", 1.0)
	var demo_table: Resource = fix_table_script.new()
	demo_table.set("entries", Array([bolt_entry], TYPE_OBJECT, "Resource", fix_entry_script))
	_check(demo_table != null, "single-entry fixture reward table (Placeholder Bolt)")
	if def_script == null or enemy_scene == null or demo_table == null:
		print("[98] DONE failures=", failures)
		quit(failures)
		return

	# (a) the scene's own definition -> exact current stats.
	# NOTE: _ready defers to the first frame in a SceneTree harness, so
	# hp init and definition overrides are read AFTER a process frame.
	var e1: Node = enemy_scene.instantiate()
	root.add_child(e1)
	await process_frame
	_check(e1.get("definition") != null and e1.get("definition").resource_path == "res://data/enemies/mustache_warrior.tres", "(a) scene carries the mustache_warrior definition")
	_check(e1.get("max_hp") == 30 and e1.get("hp") == 30, "(a) max_hp/hp 30 unchanged")
	_check(is_equal_approx(e1.get("speed"), 110.0), "(a) speed 110 unchanged")
	_check(e1.get("contact_damage") == 10, "(a) contact_damage 10 unchanged")
	_check(is_equal_approx(e1.get("contact_cooldown"), 0.8), "(a) contact_cooldown 0.8 unchanged")
	_check(is_equal_approx(e1.get("contact_range"), 40.0), "(a) contact_range 40 unchanged")

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
	var entry_script: Script = load("res://game/economy/reward_entry.gd")
	var table_script: Script = load("res://game/economy/reward_table.gd")
	var other_entry: Resource = entry_script.new()
	other_entry.set("spell", load("res://data/spells/fire_ball.tres"))
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

	await _test_fishy_audio()

	if failures == 0:
		print("[98] PASS")
	else:
		print("[98] DONE failures=", failures)
	quit(failures)


func _test_fishy_audio() -> void:
	var p: Player = load("res://game/player/player.tscn").instantiate()
	root.add_child(p)
	var fish: Enemy = load("res://game/enemies/enemy_fishy.tscn").instantiate()
	root.add_child(fish)
	var second: Enemy = load("res://game/enemies/enemy_fishy.tscn").instantiate()
	root.add_child(second)
	fish.set_physics_process(false)
	second.set_physics_process(false)
	var audio := fish.get_node("FishyAudio") as FishyAudio
	var other := second.get_node("FishyAudio") as FishyAudio
	audio.set_physics_process(false)
	other.set_physics_process(false)
	await process_frame
	fish._player = p
	second._player = p
	fish.position = p.position + Vector2(200, 0)
	second.position = fish.position
	var behavior := fish._behavior as EnemyBehaviorFishy
	var other_behavior := second._behavior as EnemyBehaviorFishy
	behavior.notice_radius = 100.0
	behavior.leash_radius = 500.0
	behavior.home = fish.global_position
	behavior._update_engaged(fish, p, true)
	other_behavior.engaged = false
	audio._idle_left = 0.0
	other._idle_left = 0.0
	audio.step(0.01)
	other.step(0.01)
	_check(audio.whistle_count == 1 and audio._whistle.playing, "Fishy: actual unaware guard starts full whistle nearby")
	_check(other.whistle_count == 0, "Fishy: global one-whistler cap")
	_check(not audio._whistle.stream.loop and absf(audio._whistle.stream.get_length() - 16.4) < 0.02, "Fishy: approved full nonlooping B2 melody")
	_check(audio._idle_left >= 46.3 and audio._idle_left <= 66.4, "Fishy: full cue plus 30-50s quiet spacing")
	behavior.notice_radius = INF
	behavior._update_engaged(fish, p, true)
	audio.step(0.01)
	_check(not audio._whistle.playing, "Fishy: real dungeon awareness stops whistle")
	behavior.notice_radius = 100.0
	behavior.engaged = false
	audio._idle_left = 0.0
	audio.step(0.01)
	p.position += Vector2(1000, 0)
	audio.step(0.01)
	_check(not audio._whistle.playing, "Fishy: range exit stops whistle")
	p.position = Vector2.ZERO
	p.hp = 0
	audio.step(0.01)
	_check(not audio._whistle.playing, "Fishy: player death silences whistle")
	p.hp = 100
	fish.hp = 0
	audio.step(0.01)
	_check(not audio._whistle.playing, "Fishy: enemy death silences whistle")
	fish.free()
	second.free()
	p.free()
