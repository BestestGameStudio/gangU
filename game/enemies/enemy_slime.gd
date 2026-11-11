class_name EnemySlime
extends Enemy
## #392 (Daniel): a slime splits into two on death, each child with half the
## stats. A slime only splits when its max HP is at least SPLIT_MIN_HP
## (Daniel, 2026-11-09: "slimes must have at least 20 HP to split", then
## "actually 40"; compared against the dying slime's max HP).
##
## Lives in a subclass so enemy.gd stays untouched (enemy-creation skill).
## Children are the same scene with a generated EnemyDefinition holding the
## halved stats; they carry the "split_child" meta so objectives can count
## them. Which stats halve: max_hp, contact_damage, speed (Daniel: "each with
## 1/2 stats"); contact_cooldown and contact_range are copied unchanged.
## Integer stats round up with a floor of 1.
##
## ORDERING (stove-jebs review of #394): the split runs BEFORE died is
## emitted, not off a died connection. A died->_split connection loses to any
## watcher that connected first (objectives and spawners connect a child's
## handlers at the parent's children_spawned, before the child's _ready),
## which let CLEAR_ALL complete and ELIMINATION spawn its boss while split
## descendants were still pending. Splitting inside the killing apply_damage
## makes children_spawned strictly precede this slime's died for every
## watcher, whatever the connect order.

const SPLIT_MIN_HP: int = 40
const SPLIT_COUNT: int = 2
const SPLIT_OFFSET: float = 12.0
## Emitted synchronously during the killing apply_damage, strictly before this
## slime's died, with the not-yet-in-tree children (they enter the tree
## deferred, D14). Watchers can raise their targets before counting the death.
signal children_spawned(children: Array)

const META_SPLIT_CHILD := &"split_child"

## Split on the killing blow, before Enemy announces the death.
func apply_damage(amount: int, crit_tier: int = 0) -> void:
	if hp > 0 and amount >= hp:
		_split()
	super.apply_damage(amount, crit_tier)

static func can_split(max_hp_value: int) -> bool:
	return max_hp_value >= SPLIT_MIN_HP

static func _half_int(v: int) -> int:
	return maxi(1, ceili(v / 2.0))

## Half-stats definition for a child of an enemy with these stats.
static func halved_definition(parent: Enemy) -> EnemyDefinition:
	var d := EnemyDefinition.new()
	d.max_hp = _half_int(parent.max_hp)
	d.contact_damage = _half_int(parent.contact_damage)
	d.speed = parent.speed * 0.5
	d.contact_cooldown = parent.contact_cooldown
	d.contact_range = parent.contact_range
	if parent.definition != null:
		d.reward_table = parent.definition.reward_table
		d.behavior = parent.definition.behavior
	return d

## Children keep the parent's movement/targeting context so they never become a
## straight-line exception: terrain and player_path above, plus anything an
## area or objective handed this enemy after spawn. Duck-typed by property
## name so a pathfinding field added to Enemy later (e.g. #384's `nav`, any
## tree-avoidance nav) is inherited without editing this file again.
const INHERITED_PROPS: Array[StringName] = [&"nav", &"can_swim", &"objective_target", &"objective_aggro_range"]

func _inherit_context(child: Enemy) -> void:
	var names := {}
	for p in get_property_list():
		names[p["name"]] = true
	for prop in INHERITED_PROPS:
		if names.has(prop):
			child.set(prop, get(prop))

## Set by EnemySpawner when this slime came through it. Death-spawned
## children then go back through the same spawner seam
## (request_spawn_deferred): should_spawn policy, wiring, alive counters and
## spawned/spawn_died signals all govern descendants too (stove-jebs #394
## review). Null in hand-built scenes/tests: the slime instantiates and
## deferred-adds children itself, same D14-safe timing.
var spawner: EnemySpawner = null

func _split() -> void:
	if not can_split(max_hp):
		return
	var area := get_parent()
	if area == null or scene_file_path.is_empty():
		return
	var scene := load(scene_file_path) as PackedScene
	var pos := global_position
	var kids: Array = []
	for i in SPLIT_COUNT:
		var side := -1.0 if i == 0 else 1.0
		var local: Vector2 = (area as Node2D).to_local(pos + Vector2(side * SPLIT_OFFSET, 0.0)) if area is Node2D else pos
		var entry := SpawnEntry.new(local, scene, reward_table, halved_definition(self))
		var child: Enemy = null
		if spawner != null:
			child = spawner.request_spawn_deferred(entry)
		else:
			var opts := EnemySpawner.SpawnOptions.new()
			opts.wire_enemy = true
			opts.player_path = player_path
			opts.terrain = terrain
			opts.reward_table = reward_table
			opts.definition = entry.definition
			child = EnemySpawner.spawn(scene, local, opts) as Enemy
			area.call_deferred("add_child", child)
		if child == null:
			continue # spawn policy refused this child; it never exists
		child.player_path = player_path
		child.terrain = terrain
		_inherit_context(child)
		child.set_meta(META_SPLIT_CHILD, true)
		kids.append(child)
	# Only actually-spawned children are announced, so watchers raise their
	# targets by exactly the number of descendants that will exist.
	if not kids.is_empty():
		children_spawned.emit(kids)
