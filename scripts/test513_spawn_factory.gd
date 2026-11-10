extends SceneTree
## #513: construction is shared, tree entry and ownership remain at callers.
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("[513 spawn] ", label, " -> ", "PASS" if ok else "FAIL")
func _initialize() -> void:
	var scene := load("res://scenes/enemy.tscn") as PackedScene
	var definition := EnemyDefinition.new()
	var table := RewardTable.new()
	var terrain := TerrainMap.new()
	var context := WolfContext.new()
	context.anchor = Vector2(30, 40)
	context.has_anchor = true
	var opts := EnemySpawner.SpawnOptions.new()
	opts.wire_enemy = true
	opts.player_path = NodePath("../../Player")
	opts.terrain = terrain
	opts.reward_table = table
	opts.definition = definition
	opts.context = context
	var enemy := EnemySpawner.spawn(scene, Vector2(11, 22), opts) as Enemy
	_check(enemy != null and not enemy.is_inside_tree() and enemy.get_parent() == null, "factory returns unattached enemy before ready")
	_check(enemy.position == Vector2(11, 22) and enemy.player_path == opts.player_path, "position and target wired before tree entry")
	_check(enemy.definition == definition and enemy.reward_table == table and enemy.terrain == terrain, "typed stats reward terrain preserved")
	_check(enemy.context == context and (enemy.context as WolfContext).has_anchor, "context instance preserved")
	enemy.free()
	terrain.free()
	# Default options must not clear authored definition/target/reward values.
	var boss_scene := load("res://scenes/head_boss.tscn") as PackedScene
	var original := boss_scene.instantiate() as Enemy
	var boss := EnemySpawner.spawn(boss_scene, Vector2(5, 6), EnemySpawner.SpawnOptions.new()) as Enemy
	_check(boss.definition == original.definition and boss.player_path == original.player_path and boss.reward_table == original.reward_table, "default options preserve authored fields")
	original.free()
	boss.free()
	# DungeonObjective accepts fixture roots that are not Enemy or Node2D.
	var plain := Node.new()
	var plain_scene := PackedScene.new()
	plain_scene.pack(plain)
	plain.free()
	var generic := EnemySpawner.spawn(plain_scene, Vector2(8, 9), EnemySpawner.SpawnOptions.new())
	_check(generic is Node and not generic is Node2D and not generic.is_inside_tree(), "generic boss fixture contract retained")
	generic.free()
	var spatial := Node2D.new()
	var spatial_scene := PackedScene.new()
	spatial_scene.pack(spatial)
	spatial.free()
	var placed := EnemySpawner.spawn(spatial_scene, Vector2(8, 9), EnemySpawner.SpawnOptions.new()) as Node2D
	_check(placed.position == Vector2(8, 9), "non-enemy spatial fixture placed before parenting")
	placed.free()
	quit(1 if failures else 0)
