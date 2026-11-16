extends SceneTree
## #685: the defeated Sand General leaves a solid, inert footprint: it
## blocks the player (WORLD layer), never deals damage or flashes (empty
## mask + the _won hit guard), and stays the statue's own size at the
## corpse so pickups and the arena exit stay clear.

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[statue corpse collider] ", label, " -> ", "PASS" if ok else "FAIL")

func _initialize() -> void:
	call_deferred("_run")

func _find_footprint(arena: DesertStatueArena) -> StaticBody2D:
	for child in arena.get_children():
		var body := child as StaticBody2D
		if body == null or body.collision_layer != PhysicsLayers.WORLD:
			continue
		for sub in body.get_children():
			if sub is CollisionShape2D:
				return body
	return null

func _footprint_circle(footprint: StaticBody2D) -> CircleShape2D:
	for sub in footprint.get_children():
		var shape := sub as CollisionShape2D
		if shape != null:
			return shape.shape as CircleShape2D
	return null

func _run() -> void:
	var area := Node2D.new()
	root.add_child(area)
	var player: Player = load("res://game/player/player.tscn").instantiate()
	player.name = "Player"
	area.add_child(player)
	player.set_physics_process(false)
	var region := Node2D.new()
	area.add_child(region)
	var arena := DesertStatueArena.new()
	region.add_child(arena)
	arena.set_physics_process(false)
	arena.start_encounter()
	await process_frame

	# No footprint while the fight runs.
	_check(_find_footprint(arena) == null, "no solid footprint before the win")

	arena.apply_damage(arena.hp)
	_check(arena.hp == 0, "boss HP reaches 0")
	await process_frame
	await process_frame # _drop_reward is call_deferred from _win()

	var footprint := _find_footprint(arena)
	_check(footprint != null, "a solid footprint appears on the fallen general")
	if footprint != null:
		_check(footprint.collision_layer == PhysicsLayers.WORLD, "footprint sits on the WORLD layer so the player collides")
		_check(footprint.collision_mask == 0, "footprint mask is empty: it never senses or deals contact")
		var circle := _footprint_circle(footprint)
		_check(circle != null and circle.radius < DesertStatue.BODY_RADIUS, "footprint is smaller than the live body (exit and pickup reach stay clear)")
		if is_instance_valid(arena.possessed):
			_check(footprint.position == arena.possessed.position, "footprint is centered on the corpse")

	# Post-defeat hits stay inert: no damage, no hit flash on the statue.
	if is_instance_valid(arena.possessed):
		var general := arena.possessed
		general.flash = 0.0
		arena.damage_statue(general, 100, 0)
		_check(general.flash == 0.0 and general.hp == 0, "post-defeat hits deal no damage and trigger no flash")

	# #685 geometry: the coin spawns at the corpse center, so the footprint
	# must leave the pickup trigger reachable. Walk the player up against the
	# footprint (tangent, no penetration): the coin must still be collected.
	var coin: RewardDrop = null
	for child in region.get_children():
		var d := child as RewardDrop
		if d != null and d.entry != null and d.entry.kind == RewardEntry.Kind.CURRENCY:
			coin = d
	_check(coin != null, "coin drop spawned at the corpse")
	if coin != null and footprint != null:
		var fr := _footprint_circle(footprint).radius
		var pr := ((player.get_node("CollisionShape2D") as CollisionShape2D).shape as CircleShape2D).radius
		var drop_shape: CircleShape2D = null
		for sub in coin.get_children():
			var s := sub as CollisionShape2D
			if s != null:
				drop_shape = s.shape as CircleShape2D
		_check(drop_shape != null and fr < drop_shape.radius, "footprint radius leaves the pickup trigger reachable")
		player.global_position = coin.global_position + Vector2.RIGHT * (fr + pr)
		player.force_update_transform()
		# Area/body sync lags a couple of physics steps; give it a few frames.
		for i in 10:
			await physics_frame
			if not is_instance_valid(coin):
				break
		_check(not is_instance_valid(coin), "player pressed against the footprint collects the coin")
		if is_instance_valid(arena.possessed):
			_check(player.global_position.distance_to(arena.possessed.global_position) >= fr + pr - 0.6, "collection happened without penetrating the footprint")
	area.queue_free()

	await process_frame
	print("[statue corpse collider] DONE failures=", failures)
	quit(1 if failures else 0)
