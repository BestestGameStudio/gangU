extends SceneTree
## #515 harness: named physics layers/masks replace ActorCollision's per-pair
## exceptions, and a crowd of non-enemy bodies cannot hide a projectile hit.
## Real engine physics. Proves:
## - every actor/trigger/projectile scene has the documented layer and mask,
## - players, enemies and summons pass through each other but still collide
##   with world props, and summons still block each other (legacy),
## - trigger areas only see the Player,
## - 20 friendly summons packed around a shot do not stop it hitting the
##   enemy ahead.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[515] ", name, " -> ", "PASS" if cond else "FAIL")

func _frames(n: int) -> void:
	for i in range(n):
		await physics_frame

func _lm(scene: String) -> Array:
	var paths := {
		"barricade": "res://game/enemies/barricade.tscn",
		"beast_boss": "res://game/enemies/bosses/beast_boss.tscn",
		"bestiary_station": "res://game/ui/bestiary_station.tscn",
		"defense_wave_boss": "res://game/enemies/bosses/defense_wave_boss.tscn",
		"destroyable_container": "res://game/economy/destroyable_container.tscn",
		"enemy": "res://game/enemies/enemy.tscn",
		"enemy_barricader": "res://game/enemies/enemy_barricader.tscn",
		"enemy_bird": "res://game/enemies/enemy_bird.tscn",
		"enemy_fishy": "res://game/enemies/enemy_fishy.tscn",
		"enemy_slime": "res://game/enemies/enemy_slime.tscn",
		"enemy_wolf": "res://game/enemies/enemy_wolf.tscn",
		"exit_portal": "res://game/world/exit_portal.tscn",
		"gate": "res://game/world/gate.tscn",
		"head_boss": "res://game/enemies/bosses/head_boss.tscn",
		"mustache_warlord": "res://game/enemies/bosses/mustache_warlord.tscn",
		"player": "res://game/player/player.tscn",
		"revive_item": "res://game/player/revive_item.tscn",
		"reward_drop": "res://game/economy/reward_drop.tscn",
		"shop_vendor": "res://game/ui/shop_vendor.tscn",
		"spell_directory": "res://game/ui/spell_directory.tscn",
		"spell_pickup": "res://game/spells/spell_pickup.tscn",
		"summon": "res://game/spells/summons/summon.tscn",
	}
	var n: CollisionObject2D = load(paths[scene]).instantiate()
	var r := [n.collision_layer, n.collision_mask]
	n.free()
	return r

func _spell() -> Spell:
	var s := Spell.new()
	s.mode = Spell.CastMode.PROJECTILE
	s.spell_name = "Fixture Bolt"
	s.damage = 7.0
	s.radius = 4.0
	s.range = 600.0
	s.projectile_speed = 500.0
	return s

func _initialize() -> void:
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)
	await process_frame

	# --- (a) scene layers and masks ---
	_check(_lm("player") == [PhysicsLayers.PLAYER, PhysicsLayers.WORLD], "player: layer player, mask world")
	for sc in ["enemy", "enemy_barricader", "enemy_bird", "enemy_fishy", "enemy_slime", "enemy_wolf", "beast_boss", "defense_wave_boss", "head_boss", "mustache_warlord"]:
		_check(_lm(sc) == [PhysicsLayers.ENEMY, PhysicsLayers.WORLD], "%s: layer enemy, mask world" % sc)
	_check(_lm("summon") == [PhysicsLayers.SUMMON, PhysicsLayers.SUMMON_MASK], "summon: layer summon, mask world+summon")
	for sc in ["barricade", "destroyable_container"]:
		_check(_lm(sc) == [PhysicsLayers.WORLD, 0], "%s: layer world, mask none" % sc)
	for sc in ["bestiary_station", "exit_portal", "gate", "revive_item", "reward_drop", "shop_vendor", "spell_directory", "spell_pickup"]:
		_check(_lm(sc) == [PhysicsLayers.PICKUP, PhysicsLayers.PLAYER], "%s: layer pickup, mask player" % sc)
	_check(ProjectSettings.get_setting("layer_names/2d_physics/layer_3") == "enemy", "project.godot names layer 3 'enemy'")

	# --- (b) projectile layers follow the source side ---
	var player: Player = preload("res://game/player/player.tscn").instantiate()
	player.add_to_group("player")
	stage.add_child(player)
	player.global_position = Vector2(3000, 3000)
	var pp: Projectile = preload("res://game/spells/projectile.tscn").instantiate()
	pp.setup(_spell(), Vector2.DOWN, player)
	_check(pp.collision_layer == PhysicsLayers.PLAYER_PROJECTILE and pp.collision_mask == PhysicsLayers.PLAYER_SHOT_MASK, "player shot: player_projectile layer, no player in mask")
	pp.free()
	var mob: Enemy = preload("res://game/enemies/enemy.tscn").instantiate()
	stage.add_child(mob)
	mob.global_position = Vector2(5000, 5000)
	mob.set_physics_process(false)
	var ep: Projectile = preload("res://game/spells/projectile.tscn").instantiate()
	ep.setup(_spell(), Vector2.DOWN, mob)
	_check(ep.collision_layer == PhysicsLayers.ENEMY_PROJECTILE and ep.collision_mask == PhysicsLayers.ENEMY_SHOT_MASK, "enemy shot: enemy_projectile layer, full body mask")
	ep.free()

	# --- (c) pass-through and blocking with real move_and_slide ---
	var e1: Enemy = preload("res://game/enemies/enemy.tscn").instantiate()
	e1.contact_damage = 0
	e1.position = Vector2(500, 500)
	stage.add_child(e1)
	e1.set_physics_process(false)
	var p1: Player = preload("res://game/player/player.tscn").instantiate()
	p1.position = Vector2(400, 500)
	stage.add_child(p1)
	p1.set_physics_process(false)
	await _frames(2)
	var hit_enemy := 0
	for i in 60:
		await physics_frame
		p1.velocity = Vector2(320, 0)
		p1.move_and_slide()
		for c in p1.get_slide_collision_count():
			if p1.get_slide_collision(c).get_collider() == e1:
				hit_enemy += 1
	_check(hit_enemy == 0 and p1.global_position.x > 650.0, "player walks through an enemy (x=%.1f)" % p1.global_position.x)
	var wall := StaticBody2D.new()
	wall.collision_layer = PhysicsLayers.WORLD
	wall.collision_mask = 0
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 200)
	cs.shape = rect
	wall.add_child(cs)
	wall.position = Vector2(1000, 500)
	stage.add_child(wall)
	p1.global_position = Vector2(900, 500)
	await _frames(2)
	for i in 40:
		await physics_frame
		p1.velocity = Vector2(320, 0)
		p1.move_and_slide()
	_check(p1.global_position.x < 1000.0, "player still blocked by a world body (x=%.1f)" % p1.global_position.x)
	e1.global_position = Vector2(900, 500)
	p1.global_position = Vector2(800, 500)
	await _frames(2)
	for i in 40:
		await physics_frame
		e1.velocity = Vector2(320, 0)
		e1.move_and_slide()
	_check(e1.global_position.x < 1000.0, "enemy still blocked by a world body (x=%.1f)" % e1.global_position.x)
	p1.queue_free()
	e1.queue_free()
	wall.queue_free()
	await _frames(2)

	# --- (d) a trigger area ignores a non-player body but fires for the Player ---
	var gate: Gate = preload("res://game/world/gate.tscn").instantiate()
	gate.position = Vector2(2000, 500)
	stage.add_child(gate)
	var seen: Array = []
	gate.entered.connect(func(g): seen.append(g))
	var e2: Enemy = preload("res://game/enemies/enemy.tscn").instantiate()
	e2.contact_damage = 0
	e2.position = Vector2(2000, 500)
	stage.add_child(e2)
	e2.set_physics_process(false)
	await _frames(4)
	_check(seen.is_empty() and not gate.get_overlapping_bodies().has(e2), "gate area does not see an enemy standing on it")
	var p2: Player = preload("res://game/player/player.tscn").instantiate()
	p2.position = Vector2(2000, 500)
	stage.add_child(p2)
	p2.set_physics_process(false)
	await _frames(4)
	_check(gate.get_overlapping_bodies().has(p2), "gate area sees the Player")
	p2.queue_free()
	e2.queue_free()
	gate.queue_free()
	await _frames(2)

	# --- (e) 20 friendly summons around a shot do not hide the enemy ahead ---
	var owner_p: Player = preload("res://game/player/player.tscn").instantiate()
	owner_p.add_to_group("player")
	owner_p.position = Vector2(3000, 2000)
	stage.add_child(owner_p)
	owner_p.set_physics_process(false)
	var crowd: Array[Summon] = []
	for i in 20:
		var s: Summon = preload("res://game/spells/summons/summon.tscn").instantiate()
		s.player = owner_p
		s.position = Vector2(4000 + (i % 5) * 2, 400 + (i / 5) * 2) ## all overlapping the shot's start
		stage.add_child(s)
		s.set_physics_process(false)
		crowd.append(s)
	var target: Enemy = preload("res://game/enemies/enemy.tscn").instantiate()
	target.position = Vector2(4000, 700) ## 300 px ahead: only the tunnelling sweep can reach it
	stage.add_child(target)
	target.set_physics_process(false)
	await _frames(2)
	var shot: Projectile = preload("res://game/spells/projectile.tscn").instantiate()
	var fast := _spell()
	fast.projectile_speed = 30000.0 ## 500 px per physics frame: the sweep, not frame overlap, must find the enemy
	fast.range = 3000.0
	shot.setup(fast, Vector2.DOWN, owner_p)
	stage.add_child(shot)
	shot.global_position = Vector2(4000, 402)
	await _frames(30)
	_check(target.hp < target.max_hp, "shot among 20 friendly summons still hits the enemy (hp=%d)" % target.hp)
	var untouched := true
	for s in crowd:
		if s.hp != s.max_hp:
			untouched = false
	_check(untouched, "friendly summons took no damage")

	await process_frame
	await process_frame
	if failures == 0:
		print("[515] RESULT: ALL PASS")
	else:
		print("[515] FAILURES: ", failures)
	quit(failures)
