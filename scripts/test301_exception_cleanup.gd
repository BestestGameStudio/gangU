extends SceneTree
## #301 harness: bodies that hold ActorCollision pair exceptions unpair on
## exit, so a freed summon/enemy leaves no stale entry in peers' collision
## exception lists (engine "Parameter \"body\" is null" on the next list
## read). Uses the production death paths (apply_damage -> queue_free).
## Scope: summon + enemy free sites only. Player-freed-first is NOT
## covered (player is persistent; excluded by design). The zero-ERROR
## gate on this script's output covers the stale-read regression.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[301] ", name, " -> ", "PASS" if cond else "FAIL")

func _all_valid(list: Array) -> bool:
	for e in list:
		if not is_instance_valid(e):
			return false
	return true

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _initialize() -> void:
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)
	current_scene = stage
	await process_frame

	var def: SummonDefinition = load("res://resources/summons/ally.tres")
	var player: Player = load("res://scenes/player.tscn").instantiate()
	player.add_to_group("player")
	stage.add_child(player)
	player.global_position = Vector2(1000, 1000)
	player.set_process(false)
	player.set_physics_process(false)
	var manager := SummonManager.new()
	manager.caster_path = NodePath("../Stage/Player/SpellCaster")
	root.add_child(manager)
	await _frames(2)

	# --- 1: summon death cleans the player's exception list --------------
	var s1: Summon = manager.request_spawn(def, Vector2(1000, 1040))
	await _frames(2)
	_check(player.get_collision_exceptions().has(s1), "setup: player paired with summon")
	s1.apply_damage(100000) # production death: queue_free
	await _frames(4)
	# This read is the regression probe: a stale entry makes the engine log.
	var after_summon: Array = player.get_collision_exceptions()
	_check(after_summon.is_empty(), "summon death: player exception list empty on read (no stale entry)")

	# --- 2: summon death cleans an enemy's exception list ----------------
	var s2: Summon = manager.request_spawn(def, Vector2(1000, 1040))
	var e2: Enemy = load("res://scenes/enemy.tscn").instantiate()
	stage.add_child(e2)
	e2.global_position = Vector2(1200, 1000)
	e2.set_process(false)
	e2.set_physics_process(false)
	e2.max_hp = 100000 # survives summon contact damage; death would free
	e2.hp = 100000 # the fixture body mid-test (harness hygiene)
	await _frames(3)
	_check(e2.get_collision_exceptions().has(s2), "setup: enemy paired with summon (summons group)")
	var e2_before: int = e2.get_collision_exceptions().size()
	s2.apply_damage(100000)
	await _frames(4)
	var e2_after: Array = e2.get_collision_exceptions()
	_check(e2_after.size() == e2_before - 1 and _all_valid(e2_after), "summon death: enemy list shrank by one, all remaining entries valid (no stale)")

	# --- 3: enemy death cleans the player's exception list ---------------
	var e3: Enemy = load("res://scenes/enemy.tscn").instantiate()
	stage.add_child(e3)
	e3.global_position = Vector2(1200, 1040)
	e3.set_process(false)
	e3.set_physics_process(false)
	await _frames(3)
	_check(player.get_collision_exceptions().has(e3), "setup: player paired with enemy (#290)")
	var p_before3: int = player.get_collision_exceptions().size()
	e3.apply_damage(100000) # production death: queue_free
	await _frames(4)
	var p_after3: Array = player.get_collision_exceptions()
	_check(p_after3.size() == p_before3 - 1 and _all_valid(p_after3), "enemy death: player list shrank by one, all remaining entries valid (no stale)")

	# --- 4: >1 peer - one death preserves the remaining valid pair -------
	var s4a: Summon = manager.request_spawn(def, Vector2(1000, 1040))
	var s4b: Summon = manager.request_spawn(def, Vector2(1000, 1080))
	s4b.max_hp = 100000 # fixture survives the whole test
	s4b.hp = 100000
	await _frames(3)
	s4a.apply_damage(100000)
	await _frames(4)
	var remaining: Array = player.get_collision_exceptions()
	_check(remaining.has(s4b) and is_instance_valid(s4b), "peer death: surviving summon pairing preserved")
	_check(_all_valid(remaining), "peer death: every remaining list entry is a valid body (no stale)")

	# --- 5: same-frame double death (summon + enemy) - no stale reads ----
	var s5: Summon = manager.request_spawn(def, Vector2(1000, 1040))
	var e5: Enemy = load("res://scenes/enemy.tscn").instantiate()
	stage.add_child(e5)
	e5.global_position = Vector2(1200, 1080)
	e5.set_process(false)
	e5.set_physics_process(false)
	await _frames(3)
	s5.apply_damage(100000)
	e5.apply_damage(100000)
	await _frames(5)
	# Survivor-side reads after both frees: engine gate covers stale logs.
	var after_both: Array = player.get_collision_exceptions()
	_check(after_both.has(s4b) and _all_valid(after_both), "same-frame double death: surviving pair remains, no stale entries")

	s4b.queue_free()
	await _frames(2)
	print("[301] SUMMARY failures=", failures)
	print("TEST301_PASS" if failures == 0 else "TEST301_FAIL")
	quit(0 if failures == 0 else 1)
