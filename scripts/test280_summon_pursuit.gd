extends SceneTree
## #280 harness: the guard ally pursues the NEAREST live enemy at ANY
## distance, so summons stop trailing the player at max distance
## (Daniel, 2026-11-08: "even if the enemy is outside the range").
## Proves: engagement beats the follow-return while an enemy lives; a
## far enemy beyond the old aggro_range is chased to contact and damaged
## through the standard path; with NO live enemies the follow/hold rules
## still behave exactly as before.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[280] ", name, " -> ", "PASS" if cond else "FAIL")

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
	player.global_position = Vector2(0, 0)
	var manager := SummonManager.new()
	manager.caster_path = NodePath("../Stage/Player/SpellCaster")
	root.add_child(manager)
	await process_frame

	# --- pursuit beyond the old aggro_range: enemy 600px away is chased ---
	var enemy: Enemy = load("res://scenes/enemy.tscn").instantiate()
	stage.add_child(enemy)
	enemy.global_position = Vector2(600, 0)
	var ally: Summon = manager.request_spawn(def, Vector2(0, 0))
	await process_frame
	_check(ally.global_position.distance_to(enemy.global_position) > def.aggro_range, "fixture: enemy starts beyond the old aggro_range")
	for i in 30:
		await physics_frame
	_check(ally.global_position.distance_to(enemy.global_position) < 600.0 - 40.0, "pursuit: ally closes on an enemy outside the old range")
	var enemy_hp0: int = enemy.hp
	for i in 240:
		await physics_frame
	_check(enemy.hp < enemy_hp0, "pursuit: ally reaches contact and lands hits through the standard path")
	if is_instance_valid(enemy):
		enemy.queue_free()
	if is_instance_valid(ally):
		ally.queue_free()
	await process_frame

	# --- engagement beats follow-return while an enemy lives ---
	player.global_position = Vector2(2000, 2000)
	var enemy_b: Enemy = load("res://scenes/enemy.tscn").instantiate()
	stage.add_child(enemy_b)
	enemy_b.global_position = Vector2(0, 0)
	var ally_b: Summon = manager.request_spawn(def, Vector2(60, 0))
	await process_frame
	for i in 30:
		await physics_frame
	_check(ally_b.global_position.distance_to(enemy_b.global_position) < 60.0, "engagement first: ally heads for the enemy, not the far player")
	_check(ally_b.global_position.distance_to(player.global_position) > 1500.0, "no trailing: ally does not follow the far player while an enemy lives")
	if is_instance_valid(enemy_b):
		enemy_b.queue_free()
	if is_instance_valid(ally_b):
		ally_b.queue_free()
	await process_frame

	# --- no live enemies: follow-return and hold behave as before ---
	player.global_position = Vector2(2000, 2000)
	var ally_c: Summon = manager.request_spawn(def, Vector2(0, 0))
	await process_frame
	var d0: float = ally_c.global_position.distance_to(player.global_position)
	for i in 30:
		await physics_frame
	_check(ally_c.global_position.distance_to(player.global_position) < d0 - 40.0, "no enemies: follow-return still closes on a too-far player")
	if is_instance_valid(ally_c):
		ally_c.queue_free()
	await process_frame
	player.global_position = Vector2(4000, 4000)
	var ally_d: Summon = manager.request_spawn(def, Vector2(4060, 4000))
	await process_frame
	var idle_pos: Vector2 = ally_d.global_position
	for i in 20:
		await physics_frame
	_check(ally_d.global_position.distance_to(idle_pos) < 1.0, "no enemies: ally holds position inside the follow band")
	if is_instance_valid(ally_d):
		ally_d.queue_free()
	await process_frame

	print("[280] failures: ", failures)
	quit(1 if failures > 0 else 0)
