extends SceneTree
## #212 harness: the summon spell (playable contract, headless).
## Proves: shipped resources wire up (spell -> ally definition -> guard
## behavior); the real unlock -> slot -> cast path on the production player
## scene spawns the ally with NO projectile (projectile_count 0 guard) while
## cooldown/signals are preserved and a positive-count spell still fires;
## guard behavior legs (return priority, engage + contact damage through the
## standard path, hold position); the local taunt range BOTH sides plus
## foundation global semantics for taunt_range 0; and the demo reward table
## carrying the summon spell entry (acquisition route).

var failures := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[212] ", name, " -> ", "PASS" if cond else "FAIL")

func _projectile_count(parent: Node) -> int:
	var n := 0
	for c in parent.get_children():
		if c is Projectile:
			n += 1
	return n

func _initialize() -> void:
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)
	current_scene = stage
	await process_frame

	# --- shipped resources ---
	var spell: Spell = load("res://resources/spells/summon_ally.tres")
	var def: SummonDefinition = load("res://resources/summons/ally.tres")
	_check(spell != null and def != null, "summon spell + ally definition resources load")
	_check(spell.summon == def and spell.projectile_count == 0 and spell.cooldown == 5.0, "spell wires the ally definition, count 0, 5s cooldown")
	_check(def.behavior != null and def.max_hp == 30 and def.enemy_targetable, "ally definition carries the guard behavior + approved stats")

	# --- production composition: real player scene + manager wiring ---
	var player: Player = load("res://scenes/player.tscn").instantiate()
	player.add_to_group("player")
	stage.add_child(player)
	player.global_position = Vector2(600, 600)
	var manager := SummonManager.new()
	manager.caster_path = NodePath("../Stage/Player/SpellCaster")
	root.add_child(manager)
	await process_frame
	var caster: SpellCaster = player.get_node("SpellCaster")

	# #262: the real player's default spells now self-bind at caster._ready.
	# Clear BOTH default slots BEFORE the grants below so this fixture's
	# grant + assign flow runs against free slots exactly as before
	# (summon -> slot 0, bolt -> slot 1, via the new auto-bind).
	caster.clear_slot(0)
	caster.clear_slot(1)

	# --- acquisition -> equip -> cast ---
	caster.unlock_spell(spell)
	_check(caster.get_unlocked().has(spell), "grant lands the spell in the unlock inventory (reward-drop route)")
	_check(caster.assign_slot(0, spell), "equip: assign_slot lands the granted spell")
	_check(caster.can_cast_slot(0), "slot castable before the first cast")
	var cast_emitted := [0]
	caster.spell_cast.connect(func(_s): cast_emitted[0] += 1)
	caster.cast_slot(0)
	await process_frame
	_check(manager.live_count() == 1, "cast spawns the ally through the manager hook at the player")
	_check(_projectile_count(stage) == 0, "count 0 guard: NO projectile for the summon-only cast")
	_check(cast_emitted[0] == 1 and not caster.can_cast_slot(0), "cooldown + spell_cast preserved for the summon-only cast")
	var bolt: Spell = load("res://resources/spells/placeholder_bolt.tres")
	caster.unlock_spell(bolt)
	caster.assign_slot(1, bolt)
	caster.cast_slot(1)
	await process_frame
	_check(_projectile_count(stage) == 1, "positive-count spell still fires exactly one projectile (guard parity)")
	for c in stage.get_children():
		if c is Projectile:
			c.queue_free()
	for s in get_nodes_in_group("summons"):
		s.queue_free()
	await process_frame

	# --- behavior (a): follow when the player is too far ---
	player.global_position = Vector2(2000, 2000)
	var ally_a: Summon = manager.request_spawn(def, Vector2(0, 0))
	await process_frame
	_check(ally_a.player == player, "manager wires the guarding player before tree entry")
	var d0: float = ally_a.global_position.distance_to(player.global_position)
	for i in 30:
		await physics_frame
	_check(ally_a.global_position.distance_to(player.global_position) < d0 - 40.0, "follow: ally closes on a too-far player")

	# --- behavior (b): #280 engagement beats the follow-return ---
	var enemy_b: Enemy = load("res://scenes/enemy.tscn").instantiate()
	stage.add_child(enemy_b)
	enemy_b.global_position = Vector2(-60, 0)
	var ally_b: Summon = manager.request_spawn(def, Vector2(0, 0))
	await process_frame
	for i in 20:
		await physics_frame
	_check(ally_b.global_position.distance_to(enemy_b.global_position) < 60.0, "engagement first (#280): ally engages the nearby enemy despite the far player")
	_check(ally_b.global_position.distance_to(player.global_position) > 1500.0, "no return while an enemy lives (#280): ally does not head for the far player")
	enemy_b.queue_free()
	ally_a.queue_free()
	ally_b.queue_free()
	await process_frame

	# --- behavior (c): engage + contact damage through the standard path ---
	player.global_position = Vector2(0, 100)
	var enemy_c: Enemy = load("res://scenes/enemy.tscn").instantiate()
	stage.add_child(enemy_c)
	enemy_c.global_position = Vector2(0, 60)
	var ally_c: Summon = manager.request_spawn(def, Vector2(0, 0))
	await process_frame
	var enemy_hp0: int = enemy_c.hp
	var hits := [0]
	enemy_c.health_changed.connect(func(_cur, _mx): hits[0] += 1)
	for i in 90:
		await physics_frame
	_check(enemy_c.hp < enemy_hp0, "engage: ally's close-range attack lands on the enemy")
	_check(hits[0] >= 1 and hits[0] <= 3, "contact cooldown respected (~0.8s between hits over 1.5s)")
	enemy_c.queue_free()
	ally_c.queue_free()
	await process_frame

	# --- behavior (d): hold position near the player with no enemy ---
	player.global_position = Vector2(2000, 2050)
	var ally_d: Summon = manager.request_spawn(def, Vector2(2000, 2100))
	await process_frame
	var idle_pos: Vector2 = ally_d.global_position
	for i in 20:
		await physics_frame
	_check(ally_d.global_position.distance_to(idle_pos) < 1.0, "idle: ally holds position inside the follow band with no enemy")
	ally_d.queue_free()
	await process_frame

	# --- local taunt: inside/outside the radius, foundation default preserved ---
	player.global_position = Vector2(4300, 4000)
	var enemy_t: Enemy = load("res://scenes/enemy.tscn").instantiate()
	stage.add_child(enemy_t)
	enemy_t.global_position = Vector2(4000, 4000)
	var ally_near: Summon = manager.request_spawn(def, Vector2(4060, 4000))
	await process_frame
	_check(enemy_t._resolve_target() == ally_near, "local taunt: enemy within taunt_range prefers the ally")
	ally_near.global_position = Vector2(4500, 4000)
	_check(enemy_t._resolve_target() == player, "beyond taunt_range the enemy keeps the player")
	var plain := SummonDefinition.new()
	var ally_far: Summon = manager.request_spawn(plain, Vector2(4600, 4000))
	await process_frame
	_check(enemy_t._resolve_target() == ally_far, "taunt_range 0 preserves the #209 global semantics")
	enemy_t.queue_free()
	ally_near.queue_free()
	ally_far.queue_free()
	await process_frame

	# --- acquisition wiring: a spell entry leaves the pool on grant ---
	# #465 (Daniel, 2026-11-09: regular mobs drop currency only): the
	# production mob table no longer carries spells, so this uses an
	# in-code fixture table (summon + bolt entries).
	var table := RewardTable.new()
	var summon_entry := RewardEntry.new()
	summon_entry.kind = RewardEntry.Kind.SPELL
	summon_entry.spell = spell
	summon_entry.weight = 1.0
	var bolt_entry := RewardEntry.new()
	bolt_entry.kind = RewardEntry.Kind.SPELL
	bolt_entry.spell = load("res://resources/spells/placeholder_bolt.tres")
	bolt_entry.weight = 1.0
	var fixture_entries: Array[RewardEntry] = [summon_entry, bolt_entry]
	table.entries = fixture_entries
	_check(summon_entry.kind == RewardEntry.Kind.SPELL and summon_entry.weight == 1.0, "fixture table carries the summon spell entry (weight 1.0)")
	_check(bolt_entry.spell.spell_name == "Placeholder Bolt", "fixture Placeholder Bolt entry present")
	var pool := RewardPool.new()
	root.add_child(pool)
	pool.setup(table)
	_check(pool.is_eligible(summon_entry), "pool: summon spell eligible before grant")
	pool.remove_on_grant(summon_entry)
	_check(not pool.is_eligible(summon_entry) and pool.is_eligible(bolt_entry), "pool: grant removes only the summon entry (spell leaves the pool)")

	print("[212] failures: ", failures)
	quit(1 if failures > 0 else 0)
