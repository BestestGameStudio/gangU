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

const SPLIT_MIN_HP: int = 40
const SPLIT_COUNT: int = 2
const SPLIT_OFFSET: float = 12.0
const META_SPLIT_CHILD := &"split_child"

func _ready() -> void:
	super._ready()
	died.connect(_split)

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

func _split() -> void:
	if not can_split(max_hp):
		return
	var area := get_parent()
	if area == null or scene_file_path.is_empty():
		return
	var scene := load(scene_file_path) as PackedScene
	var pos := global_position
	for i in SPLIT_COUNT:
		var child := scene.instantiate() as Enemy
		child.definition = halved_definition(self)
		child.reward_table = reward_table
		child.player_path = player_path
		child.terrain = terrain
		child.set_meta(META_SPLIT_CHILD, true)
		var side := -1.0 if i == 0 else 1.0
		child.position = (area as Node2D).to_local(pos + Vector2(side * SPLIT_OFFSET, 0.0)) if area is Node2D else pos
		area.call_deferred("add_child", child)
