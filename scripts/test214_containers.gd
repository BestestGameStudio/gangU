extends SceneTree
## #214 harness: destroyable containers (system contract, headless).
## Owner choices (Daniel, WhatsApp 2026-11-08 12:49): SOLID body, PLAYER
## SPELLS ONLY damage. Proves: real ENGINE projectile hits (never manual
## callback invocation), damage accumulation to the exact threshold,
## zero-overkill die-ONCE with post-death no-ops, null/exhausted table = no
## drop, pool-eligible drop parented to the area at the container's WORLD
## position under a TRANSFORMED parent (world position assigned after
## parenting), instance-override precedence, the source gate (enemy/ally/
## unknown/fake-Projectile callers rejected, legacy receivers still damaged
## through the unchanged fallback), solid-body movement blocking, and area
## teardown. All fixtures are built in code; no production .tres is loaded.

var failures := 0

class StubReceiver extends StaticBody2D:
	## Legacy #5 receiver shape: apply_damage only, no source gate.
	var got: int = 0
	func apply_damage(amount: int) -> void:
		got += amount

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[214] ", name, " -> ", "PASS" if cond else "FAIL")

func _spell(p_damage: float) -> Spell:
	var s := Spell.new()
	s.spell_name = "Fixture Bolt"
	s.damage = p_damage
	s.radius = 4.0
	s.range = 600.0
	s.projectile_speed = 500.0
	return s

func _def(p_hp: int, p_table: RewardTable = null) -> ContainerDefinition:
	var d := ContainerDefinition.new()
	d.max_hp = p_hp
	d.reward_table = p_table
	return d

func _table_with(entry: RewardEntry) -> RewardTable:
	var t := RewardTable.new()
	t.entries = [entry]
	return t

func _currency_entry(amount: int) -> RewardEntry:
	var e := RewardEntry.new()
	e.kind = RewardEntry.Kind.CURRENCY
	e.currency_amount = amount
	e.weight = 1.0
	return e

func _spell_entry(p_spell: Spell) -> RewardEntry:
	var e := RewardEntry.new()
	e.kind = RewardEntry.Kind.SPELL
	e.spell = p_spell
	e.weight = 1.0
	return e

func _container(p_def: ContainerDefinition, pos: Vector2) -> DestroyableContainer:
	var c: DestroyableContainer = preload("res://scenes/destroyable_container.tscn").instantiate()
	c.definition = p_def
	c.position = pos
	return c

func _player(stage: Node2D) -> Player:
	var p: Player = preload("res://scenes/player.tscn").instantiate()
	p.add_to_group("player")
	stage.add_child(p)
	p.global_position = Vector2(2000, 2000) ## far from every hit line
	return p

## Fire a REAL projectile at `target` from 60px above it; engine collision
## does the rest. setup() runs BEFORE tree entry so _ready sees the spell.
func _fire(stage: Node2D, p_spell: Spell, target: Vector2, p_source: Node2D) -> Projectile:
	var pr: Projectile = preload("res://scenes/projectile.tscn").instantiate()
	pr.setup(p_spell, Vector2.DOWN, p_source)
	stage.add_child(pr)
	pr.global_position = target + Vector2(0, -60)
	return pr

func _drops_in(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is RewardDrop:
			out.append(c)
	return out

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)
	current_scene = stage
	await process_frame

	# --- definition defaults (fixture values, not production balance) ---
	var d0 := _def(10)
	_check(d0.max_hp == 10 and d0.reward_table == null, "definition defaults: fixture max_hp, null table")

	# --- real ENGINE hit from a PLAYER-sourced projectile, exact damage ---
	var player := _player(stage)
	var c1 := _container(_def(20), Vector2(400, 400))
	stage.add_child(c1)
	await _frames(2)
	_fire(stage, _spell(7.0), Vector2(400, 400), player)
	await _frames(20)
	_check(c1.hp == 13, "engine player-spell hit reduces hp 20 -> 13 (exact spell damage)")

	# --- accumulation across hits to the exact threshold, die-ONCE ---
	var died_count := [0]
	c1.died.connect(func(): died_count[0] += 1)
	_fire(stage, _spell(7.0), Vector2(400, 400), player)
	await _frames(20)
	_check(c1.hp == 6, "second hit accumulates 13 -> 6")
	_fire(stage, _spell(6.0), Vector2(400, 400), player)
	await _frames(20)
	await process_frame
	await process_frame
	_check(died_count[0] == 1 and not is_instance_valid(c1), "exact-threshold hit dies ONCE and frees")

	# --- zero overkill: one big gated hit dies once; same-frame repeat is a no-op ---
	var c2 := _container(_def(5), Vector2(700, 400))
	stage.add_child(c2)
	await _frames(2)
	var died2 := [0]
	c2.died.connect(func(): died2[0] += 1)
	var detached := Projectile.new() ## real Projectile instance, never enters the tree
	detached.source = player
	c2.apply_damage_from(999, detached)
	c2.apply_damage_from(5, detached) ## queue_free is end-of-frame: still valid, must no-op
	_check(died2[0] == 1 and c2.hp == 0, "zero-overkill: one big hit dies once, post-death hit no-op")
	detached.free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(c2), "dead container is freed")

	# --- null table: no drop ---
	var c3 := _container(_def(5), Vector2(100, 400))
	stage.add_child(c3)
	await _frames(2)
	_fire(stage, _spell(99.0), Vector2(100, 400), player)
	await _frames(20)
	await process_frame
	_check(_drops_in(stage).is_empty(), "null table dies with NO drop")

	# --- loot table: pool-eligible drop parented to the area ---
	var pool := RewardPool.new()
	pool.name = "RewardPool"
	stage.add_child(pool)
	var entry_s1 := _spell_entry(_spell(7.0))
	var table_s1 := _table_with(entry_s1)
	pool.setup(table_s1)
	var c4 := _container(_def(5, table_s1), Vector2(100, 700))
	stage.add_child(c4)
	await _frames(2)
	_fire(stage, _spell(99.0), Vector2(100, 700), player)
	await _frames(20)
	await process_frame
	await process_frame
	var drops := _drops_in(stage)
	_check(drops.size() == 1 and drops[0].entry == entry_s1, "table drop spawns with the rolled entry")
	_check(drops.size() == 1 and drops[0].get_parent() == stage, "drop parented to the area (survives the container)")

	# --- exhausted pool (SPELL entry granted): roll returns null, no second drop ---
	pool.remove_on_grant(entry_s1)
	var c5 := _container(_def(5, table_s1), Vector2(200, 700))
	stage.add_child(c5)
	await _frames(2)
	_fire(stage, _spell(99.0), Vector2(200, 700), player)
	await _frames(20)
	await process_frame
	_check(_drops_in(stage).size() == 1, "exhausted pool: no drop (null roll)")

	# --- instance override WINS over the definition table ---
	var entry_cur := _currency_entry(9)
	var table_cur := _table_with(entry_cur)
	var entry_s2 := _spell_entry(_spell(3.0))
	var table_s2 := _table_with(entry_s2)
	var c6 := _container(_def(5, table_s2), Vector2(300, 700))
	c6.reward_table = table_cur ## instance override
	stage.add_child(c6)
	await _frames(2)
	_fire(stage, _spell(99.0), Vector2(300, 700), player)
	await _frames(20)
	await process_frame
	await process_frame
	var drops2 := _drops_in(stage)
	_check(drops2.size() == 2 and drops2[1].entry == entry_cur, "instance override wins over definition table")

	# --- TRANSFORMED parent: drop lands at the container's WORLD position ---
	var area := Node2D.new()
	area.name = "TransformedArea"
	area.position = Vector2(500, 300)
	stage.add_child(area)
	var entry_cur2 := _currency_entry(4)
	var c7 := _container(_def(5, _table_with(entry_cur2)), Vector2(50, 0)) ## world (550, 300)
	area.add_child(c7)
	await _frames(2)
	var want_world := c7.global_position
	_fire(stage, _spell(99.0), want_world, player)
	await _frames(20)
	await process_frame
	await process_frame
	var area_drops := _drops_in(area)
	_check(area_drops.size() == 1 and area_drops[0].global_position.distance_to(want_world) < 1.0,
		"transformed parent: drop at the container WORLD position (assigned after parenting)")

	# --- source gate: non-Player projectile source (enemy/ally shape) rejected ---
	var enemy_source := Node2D.new()
	enemy_source.name = "EnemyStandIn"
	stage.add_child(enemy_source)
	var c8 := _container(_def(20), Vector2(700, 700))
	stage.add_child(c8)
	await _frames(2)
	_fire(stage, _spell(7.0), Vector2(700, 700), enemy_source)
	await _frames(20)
	_check(c8.hp == 20, "projectile from non-Player source (enemy/ally) rejected, hp unchanged")

	# --- outer guard: plain apply_damage (unknown source) rejected ---
	c8.apply_damage(7)
	_check(c8.hp == 20, "plain apply_damage (unknown source) rejected, hp unchanged")

	# --- caller gate: a non-Projectile carrying .source is still rejected ---
	var fake := Node2D.new()
	fake.set("source", player)
	c8.apply_damage_from(7, fake)
	_check(c8.hp == 20, "non-Projectile caller with .source rejected (real Projectile required)")
	fake.free()

	# --- legacy receivers still damaged through the unchanged fallback ---
	var stub := StubReceiver.new()
	var stub_shape := CollisionShape2D.new()
	var stub_rect := RectangleShape2D.new()
	stub_rect.size = Vector2(20, 20)
	stub_shape.shape = stub_rect
	stub.add_child(stub_shape)
	stub.position = Vector2(100, 100)
	stage.add_child(stub)
	await _frames(2)
	_fire(stage, _spell(7.0), Vector2(100, 100), player)
	await _frames(20)
	_check(stub.got == 7, "legacy apply_damage receiver still damaged (dispatch fallback unchanged)")

	# --- SOLID: the body blocks real player physics movement ---
	var c9 := _container(_def(20), Vector2(500, 1100))
	stage.add_child(c9)
	player.global_position = Vector2(400, 1100)
	await _frames(2)
	Input.action_press("move_right")
	await _frames(45)
	Input.action_release("move_right")
	_check(player.global_position.x < 487.0, "solid body blocks the player (cannot walk through)")

	# --- teardown: freeing the area frees container AND its drop ---
	var area2 := Node2D.new()
	stage.add_child(area2)
	var entry_cur3 := _currency_entry(2)
	var c10 := _container(_def(5, _table_with(entry_cur3)), Vector2(50, 50))
	area2.add_child(c10)
	await _frames(2)
	_fire(stage, _spell(99.0), Vector2(50, 50), player)
	await _frames(20)
	await process_frame
	await process_frame
	var drop_ref: RewardDrop = null
	for ch in area2.get_children():
		if ch is RewardDrop:
			drop_ref = ch
	area2.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(c10) and (drop_ref == null or not is_instance_valid(drop_ref)),
		"area teardown frees the container and its drop")

	print("[214] failures=", failures)
	quit(1 if failures > 0 else 0)
