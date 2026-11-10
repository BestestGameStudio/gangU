extends SceneTree
## #269 harness: the Tab equip panel renders the five player stats (Daniel,
## 2026-11-08: "Display player stats in the tab menu"; stat set 2:50:48 PM:
## HP, damage amp, armor, movement speed, cooldown reduction), reading ONLY
## the public Player accessors. Proves: seeded StatModifiers render through
## the PlayerStats math (no panel-side math), defined bases show as 0%, and
## the block refreshes live on every open.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[269] ", name, " -> ", "PASS" if cond else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _press_tab() -> void:
	for pr in [true, false]:
		var k := InputEventKey.new()
		k.keycode = KEY_TAB
		k.physical_keycode = KEY_TAB
		k.pressed = pr
		get_root().push_input(k)

## #376 restyled the block into a StatGrid (icon + value cells). The rows
## this harness checked map to "<title>: <value>" of each cell.
func _stats_texts(panel: Node) -> Array:
	var out: Array = []
	var box := panel.find_child("StatsBox", true, false) as StatGrid
	if box == null:
		return out
	out.append(box.title())
	for id in box.cell_ids():
		out.append("%s: %s" % [box.cell(id).title, box.value_of(id)])
	return out

func _initialize() -> void:
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)
	current_scene = stage
	await process_frame

	var player: Player = load("res://scenes/player.tscn").instantiate()
	stage.add_child(player)
	player.global_position = Vector2(1000, 1000)
	await _frames(2)

	# Seed run-scoped modifiers through the real PlayerStats API:
	# max_hp +50 (also heals +50 per the #268 rule), amp +0.25, armor +0.2,
	# move speed +10% of the 320 base = 352. CDR untouched: defined base 0.
	player.stats.add(StatModifier.flat(PlayerStats.MAX_HP, 50.0))
	player.stats.add(StatModifier.flat(PlayerStats.DAMAGE_AMP, 0.25))
	player.stats.add(StatModifier.flat(PlayerStats.ARMOR, 0.2))
	player.stats.add(StatModifier.percent(PlayerStats.MOVE_SPEED, 0.1))
	await _frames(1)
	_check(player.max_hp == 150 and player.hp == 150, "setup: seeded max_hp 150 (and +50 heal rule)")
	_check(roundi(player.move_speed()) == 352, "setup: seeded move speed 352")

	var panel: EquipPanel = load("res://scenes/equip_panel.tscn").instantiate()
	panel.player_path = NodePath("../Player") # explicit wiring BEFORE tree entry
	stage.add_child(panel)
	await _frames(2)
	_check(not panel.visible, "panel starts hidden")

	_press_tab()
	await _frames(2)
	_check(panel.visible, "Tab opens the panel")

	var texts := _stats_texts(panel)
	_check(texts.has("Stats"), "stats header rendered")
	_check(texts.has("Health: 150/150"), "HP row from hp/max_hp")
	_check(texts.has("Damage Amp: +25%"), "damage amp row from PlayerStats math")
	_check(texts.has("Armor: +20%"), "armor row from PlayerStats math")
	_check(texts.has("Move Speed: 352"), "move speed row from PlayerStats math")
	_check(texts.has("Cooldown Reduction: +0%"), "CDR row shows the defined base 0% (not invented)")

	# Live refresh: damage the player, reopen, HP row must follow.
	player.apply_damage(30)
	_press_tab() # close
	await _frames(2)
	_press_tab() # reopen
	await _frames(2)
	texts = _stats_texts(panel)
	_check(texts.has("Health: 120/150"), "reopen refreshes live HP (120 / 150)")

	_press_tab() # leave closed
	await _frames(1)
	print("[269] SUMMARY failures=", failures)
	print("TEST269_PASS" if failures == 0 else "TEST269_FAIL")
	quit(0 if failures == 0 else 1)
