extends SceneTree
## #209 harness: player summons foundation (headless).
## Proves: shared cap 10 enforced at the single request_spawn entry point
## across distinct sources; the effective_cap relic seam; the summon damage
## contract (clamp, signals inside only, died, free); the cast hook
## (spell.summon via _on_spell_cast); enemy target resolution with the
## per-definition enemy_targetable flag BOTH ways; boss-behavior exclusion;
## no-summon parity; and teardown releasing cap slots.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[209] ", name, " -> ", "PASS" if cond else "FAIL")

func _def(targetable := true, hp := 30) -> SummonDefinition:
	var d := SummonDefinition.new()
	d.max_hp = hp
	d.enemy_targetable = targetable
	return d

func _free_all_summons() -> void:
	for s in get_nodes_in_group("summons"):
		s.queue_free()

func _initialize() -> void:
	var m := SummonManager.new()
	root.add_child(m)
	await process_frame

	# --- spawn + shared cap across distinct sources ---
	var d := _def()
	var spawned: Array = []
	for i in 10:
		var s := m.request_spawn(d, Vector2(i * 30, 0))
		if s != null:
			spawned.append(s)
	_check(spawned.size() == 10 and m.live_count() == 10, "ten summons spawn under the cap")
	var refused := [false]
	m.spawn_refused.connect(func(_defn): refused[0] = true)
	_check(m.request_spawn(d, Vector2(999, 0)) == null and refused[0], "11th spawn refused at the shared cap")
	var spell := Spell.new()
	spell.mode = Spell.CastMode.PROJECTILE
	spell.summon = d
	m._on_spell_cast(spell)
	_check(m.live_count() == 10, "cast-driven spawn is refused at the same shared cap")
	m.base_cap = 11
	_check(m.effective_cap() == 11 and m.request_spawn(d, Vector2(0, 100)) != null, "cap seam: effective_cap follows base_cap (relic-modifiable point)")
	m.base_cap = 10

	# --- summon damage contract ---
	var target: Summon = spawned[0]
	var changes: Array = []
	var died := [0]
	target.health_changed.connect(func(cur, _mx): changes.append(cur))
	target.died.connect(func(): died[0] += 1)
	target.apply_damage(10)
	_check(target.hp == 20 and changes == [20], "summon apply_damage clamps and emits health_changed inside only")
	target.apply_damage(9999)
	_check(died[0] == 1, "lethal damage emits died once")
	await process_frame
	_check(not is_instance_valid(target) and m.live_count() == 10, "dead summon frees and releases its cap slot")

	# --- cast hook: only spells carrying a definition spawn ---
	var plain := Spell.new()
	plain.mode = Spell.CastMode.PROJECTILE
	m._on_spell_cast(plain)
	_check(m.live_count() == 10, "spell without a summon definition spawns nothing")
	m.base_cap = 12
	m._on_spell_cast(spell)
	_check(m.live_count() == 11, "cast with a summon definition spawns via the hook")

	# --- teardown releases cap slots (area-swap/reload semantics) ---
	_free_all_summons()
	await process_frame
	_check(m.live_count() == 0, "freeing all summons (area swap/reload) releases every cap slot")

	# --- enemy target resolution: flag ON, flag OFF, parity, boss exclusion ---
	var player: Player = load("res://scenes/player.tscn").instantiate()
	root.add_child(player)
	player.global_position = Vector2(2000, 2000)
	var enemy: Enemy = load("res://scenes/enemy.tscn").instantiate()
	root.add_child(enemy)
	enemy.global_position = Vector2(0, 500)
	await process_frame
	_check(enemy._resolve_target() == player, "no summons: enemy resolves the player (baseline parity)")
	var near := m.request_spawn(_def(true), Vector2(10, 500))
	_check(enemy._resolve_target() == near, "flag ON: enemy resolves the nearest targetable summon")
	var off := m.request_spawn(_def(false), Vector2(5, 500))
	_check(enemy._resolve_target() == near, "flag OFF summon is ignored while a targetable one exists")
	near.queue_free()
	off.queue_free()
	await process_frame
	_check(enemy._resolve_target() == player, "only flag-OFF/none left: enemy resolves the player again")
	enemy._behavior = EnemyBehaviorHead.new()
	var t := m.request_spawn(_def(true), Vector2(5, 500))
	_check(enemy._resolve_target() == player, "boss behavior (head) never retargets to a summon")
	t.queue_free()
	await process_frame

	# --- contact damage lands on a flag-ON summon, player untouched ---
	enemy._behavior = EnemyBehaviorChaseContact.new()
	enemy.global_position = Vector2(0, 800)
	var victim := m.request_spawn(_def(true), Vector2(10, 800))
	await process_frame
	for i in 30:
		await physics_frame
	_check(victim.hp < 30, "flag ON: enemy contact damage lands on the summon via the standard path")
	_check(player.hp == 100, "player untouched while the summon holds enemy attention")

	print("[209] failures: ", failures)
	quit(1 if failures > 0 else 0)
