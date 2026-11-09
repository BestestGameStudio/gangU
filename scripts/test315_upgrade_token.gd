extends SceneTree
## #315 harness: boss-only upgrade token. Real main.tscn flow: enter the
## DungeonC boss arena, kill the Head boss, a token drop spawns, the player
## picks it up, then spends it from the real Tab panel to advance Spirit
## Punch one tier (base -> Burst) through the apply_upgrade -> replace_spell
## route with 0 casts. Mechanics are PROVISIONAL placeholders (see
## SpellProgress #315 block).
## Run: godot --headless -s scripts/test315_upgrade_token.gd
## Rendered (screenshots to /tmp/ci/shots315): run under xvfb with
## --rendering-driver opengl3 and pass `-- --shots`.
var scene: Node
var p: Player
var caster: SpellCaster
var prog: SpellProgress
var panel: EquipPanel
var boss: Enemy
var drop: RewardDrop
var phase := 0
var t := 0.0
var ok := true
var shots := false

var token_table: RewardTable = load("res://resources/rewards/boss_token_table.tres")
var base: Spell = load("res://resources/spells/spirit_punch.tres")
var burst: Spell = load("res://resources/spells/spirit_punch_burst.tres")
var launch: Spell = load("res://resources/spells/spirit_punch_launch.tres")

func _check(cond: bool, name: String) -> void:
	print("[315] ", "PASS " if cond else "FAIL ", name)
	if not cond:
		ok = false

func _shot(name: String) -> void:
	if not shots:
		return
	DirAccess.make_dir_recursive_absolute("/tmp/ci/shots315")
	root.get_texture().get_image().save_png("/tmp/ci/shots315/%s.png" % name)
	print("[315] shot ", name)

func _done() -> bool:
	print("---\n[315] %s" % ("ALL PASS" if ok else "FAILURES PRESENT"))
	quit(0 if ok else 1)
	return true

func _initialize() -> void:
	shots = OS.get_cmdline_user_args().has("--shots")
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")
	caster = p.get_node("SpellCaster")

func _static_legs() -> void:
	# Boss-only: every boss definition carries the token table; no other
	# enemy definition or the mob demo table carries a token entry.
	_check(token_table.entries.size() == 1 and token_table.entries[0].kind == RewardEntry.Kind.UPGRADE_TOKEN,
		"token table = one UPGRADE_TOKEN entry")
	# Boss set comes from the bestiary's boss flags (scene basename = the
	# enemy .tres name), so a new boss type cannot slip past this check.
	var bosses: Array = Bestiary.CATALOG.filter(func(e): return e.get("boss", false)).map(func(e): return (e["scene"] as String).get_file().get_basename())
	_check(bosses.size() >= 4, "boss allow-list covers every bestiary boss (incl. Siege Brute)")
	for path in bosses:
		var d: EnemyDefinition = load("res://resources/enemies/%s.tres" % path)
		_check(d.reward_table == token_table, "%s drops the token table" % path)
	var dir := DirAccess.open("res://resources/enemies")
	for f in dir.get_files():
		if not f.ends_with(".tres") or f.get_basename() in bosses:
			continue
		var d: EnemyDefinition = load("res://resources/enemies/" + f)
		_check(d.reward_table == null or not _has_token(d.reward_table), "non-boss %s cannot drop a token" % f)
	_check(not _has_token(load("res://resources/rewards/demo_table.tres")), "mob demo table cannot drop a token")
	var pool := RewardPool.new()
	pool.remove_on_grant(token_table.entries[0])
	_check(pool.is_eligible(token_table.entries[0]), "token stays pool-eligible after grant (repeats per boss)")
	pool.free()

func _has_token(table: RewardTable) -> bool:
	for e in table.entries:
		if e.kind == RewardEntry.Kind.UPGRADE_TOKEN:
			return true
	return false

func _token_buttons() -> Array:
	var out: Array = []
	for c in panel._upgrade_box.find_children("*", "UpgradeCard", true, false):
		if c is UpgradeCard and not c.is_queued_for_deletion() and not c.get_parent().get_parent().is_queued_for_deletion():
			out.append(c)
	return out

func _header() -> String:
	for c in panel._upgrade_box.get_children():
		if c is Label and not c.is_queued_for_deletion():
			return c.text
	return ""

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if scene.current_area == null or scene.get_node_or_null("EquipPanel") == null:
				return false
			prog = scene.get_node("SpellProgress")
			panel = scene.get_node("EquipPanel")
			_static_legs()
			caster.unlock_spell(base)
			_check(prog.upgrade_tokens() == 0, "run starts with 0 tokens")
			_check(not prog.can_upgrade(base) and not prog.can_token_upgrade(base), "base: no upgrade at 0 casts / 0 tokens")
			scene._swap(load("res://scenes/dungeon_c.tscn").instantiate())
			phase = 1; t = 0
		1:
			if t < 0.4:
				return false
			for e in scene.current_area.get_children():
				if e is Enemy:
					boss = e
			_check(boss != null and boss.definition == load("res://resources/enemies/head_boss.tres"), "Head boss spawned in DungeonC")
			if boss == null:
				return _done()
			boss.set_physics_process(false)
			p.global_position = boss.global_position + Vector2(-260, 60)
			_shot("1_boss_arena")
			boss.apply_damage(boss.hp)
			phase = 2; t = 0
		2:
			if t < 0.3:
				return false
			for c in scene.current_area.get_children():
				if c is RewardDrop:
					drop = c
			_check(drop != null and drop.entry.kind == RewardEntry.Kind.UPGRADE_TOKEN, "boss kill drops an Upgrade Token")
			if drop == null:
				return _done()
			_check(drop.get_node("NameLabel").text == "Upgrade Token", "drop is labelled 'Upgrade Token'")
			p.global_position = drop.global_position + Vector2(-90, 0)
			phase = 3; t = 0
		3:
			# Wait out the boss corpse animation so the drop is visible.
			if t < (3.0 if shots else 0.5):
				return false
			_shot("2_token_drop")
			p.global_position = drop.global_position
			phase = 4; t = 0
		4:
			if t < 0.3:
				return false
			_check(not is_instance_valid(drop) or drop.is_queued_for_deletion(), "walk-over picks the token up")
			_check(prog.upgrade_tokens() == 1, "token count = 1 after pickup")
			_check(prog.can_token_upgrade(base) and not prog.can_upgrade(base), "token enables a tier step at 0 casts")
			_check(not prog.apply_upgrade_with_token(base, &"nope"), "unknown path refuses")
			_check(prog.upgrade_tokens() == 1, "refusal keeps the token")
			panel.show_panel()
			panel._on_slot_pressed(2) # #375: select the equipped base via its slot
			var bs := _token_buttons()
			_check(_header() == "Upgrades (Upgrade Tokens: 1)", "panel header shows token count")
			_check(bs.size() == 1 and bs[0].name_label.text == "Burst [S]" and bs[0].action_label.text == "Choose - use upgrade token" if bs.size() == 1 else false,
				"panel offers ONLY the next tier (Burst) via token: %s" % [bs.map(func(b): return b.name_label.text + " - " + b.action_label.text)])
			phase = 5; t = 0
		5:
			if t < 0.3:
				return false
			_shot("3_panel_use_token")
			var bs := _token_buttons()
			if bs.size() != 1:
				return _done()
			bs[0].pressed.emit()
			phase = 6; t = 0
		6:
			if t < 0.3:
				return false
			_check(caster.get_slots()[2] == burst and base not in caster.get_unlocked(), "token upgraded base -> Burst in place (slot 2)")
			_check(prog.get_tier(burst) == 1, "tier 1 recorded on Burst")
			_check(prog.upgrade_tokens() == 0, "token consumed")
			_check(prog.cast_count(burst) == 0, "cast counts untouched (Burst starts at 0)")
			_check(not prog.can_token_upgrade(burst) and not prog.apply_upgrade_with_token(burst, &"spirit_punch_launch"),
				"no second step without a second token")
			panel._on_slot_pressed(2) # #375: Burst inherited base's slot; click to select
			_shot("4_after_token_upgrade")
			# A qualified spell uses the free cast route: the token is kept.
			prog.add_upgrade_token(1)
			for i in 15:
				prog._on_spell_cast(burst)
			_check(prog.can_upgrade(burst) and not prog.can_token_upgrade(burst), "threshold met -> token not offered")
			panel._refresh()
			var bs := _token_buttons()
			_check(bs.size() == 1 and bs[0].name_label.text == "Launch [M]" and bs[0].action_label.text == "Choose upgrade" if bs.size() == 1 else false, "cast-ready path shows the normal button")
			if bs.size() == 1:
				bs[0].pressed.emit()
			_check(caster.get_slots()[2] == launch and prog.upgrade_tokens() == 1, "cast route applied, token kept")
			return _done()
	return false
