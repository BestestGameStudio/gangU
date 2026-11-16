extends SceneTree
## #686: the Sand General drops an upgrade token (rolled from the shared
## boss_token_table, like any boss) in addition to its coin reward - and
## exactly once: repeated post-defeat hits must not spawn extra drops.

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[statue token drop] ", label, " -> ", "PASS" if ok else "FAIL")

func _initialize() -> void:
	call_deferred("_run")

func _count_drops(region: Node2D) -> Dictionary:
	var coins := 0
	var tokens := 0
	for child in region.get_children():
		var drop := child as RewardDrop
		if drop == null or drop.entry == null:
			continue
		if drop.entry.kind == RewardEntry.Kind.CURRENCY:
			coins += 1
		elif drop.entry.kind == RewardEntry.Kind.UPGRADE_TOKEN:
			tokens += 1
	return {"coins": coins, "tokens": tokens}

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

	# One big hit through the phase-2 threshold down to 0: boss defeated.
	arena.apply_damage(arena.hp)
	_check(arena.hp == 0, "boss HP reaches 0")
	await process_frame
	await process_frame
	# #694: nothing drops while the death animation plays...
	var early := _count_drops(region)
	_check(early.coins == 0 and early.tokens == 0, "no drops during the death animation")
	# ...and the reward pops out right after it finishes.
	await create_timer(DesertStatue.death_animation_seconds() + 0.1, false).timeout

	var counts := _count_drops(region)
	_check(counts.coins == 1, "victory coins still drop exactly once")
	_check(counts.tokens == 1, "an upgrade token drops alongside the coins")

	# Repeated post-defeat hits spawn no further drops.
	if is_instance_valid(arena.possessed):
		arena.damage_statue(arena.possessed, 100, 0)
	arena.apply_damage(100)
	await process_frame
	await process_frame
	var after := _count_drops(region)
	_check(after.coins == 1 and after.tokens == 1, "post-defeat hits spawn no extra drops")
	area.queue_free()

	await process_frame
	print("[statue token drop] DONE failures=", failures)
	quit(1 if failures else 0)
