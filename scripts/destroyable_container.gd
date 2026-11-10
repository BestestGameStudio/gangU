class_name DestroyableContainer
extends StaticBody2D
## #214: destroyable container. Owner choices (Daniel, WhatsApp 2026-11-08
## 12:49 "solid and player spell"): the body is SOLID (blocks movement, eats
## untagged projectiles) and takes damage from PLAYER-CAST SPELLS ONLY - no
## enemy, ally, or environment damage by default.
##
## Source gate: projectiles dispatch apply_damage_from(amount, projectile)
## (projectile.gd's additive #214 branch); the accept test requires an actual
## Projectile whose source is the Player. Plain apply_damage(amount) is kept
## as the #5 duck-type OUTER GUARD and REJECTS: GDScript gives it no caller
## identity, so no duck-typed caller (enemy contact, summon melee, future
## code) can silently bypass the gate.
##
## Death: dies ONCE at 0 HP (clamps inside only, post-death hits are no-ops),
## then rolls its optional RewardTable through the existing RewardPool /
## RewardDrop flow. The drop is parented to the container's parent (the area)
## so it survives queue_free and frees on area swap/reload; its WORLD position
## is assigned AFTER parenting (deferred FIFO) because a pre-parenting
## assignment lands wrong under a transformed area - the enemy.gd ordering
## bug is deliberately NOT copied here.

const CombatEffects = preload("res://scripts/combat_effects.gd")

signal health_changed(new_hp: int)
signal died()

@export var definition: ContainerDefinition
## Instance override: when set it WINS over the definition's table
## (enemy.gd:33 idiom). Both null means no loot.
@export var reward_table: RewardTable

## Readable like enemy.gd's hp; written only inside this script.
var hp: int = 0
var _dead: bool = false

func _ready() -> void:
	# #406: a solid container is cover (Daniel: "any cover") - cover-seeking
	# mobs discover every solid that opted into this group.
	add_to_group(&"cover")
	if definition != null:
		hp = maxi(definition.max_hp, 0)
		if has_node("Visual"):
			$Visual.color = definition.body_color

## #5 duck-type outer guard: source unknown -> rejected (Daniel's gate).
func apply_damage(amount: int) -> void:
	print("[214] container rejected ", amount, " damage from an unknown source")

## The gated damage path (projectile dispatch). PLAYER-cast spells only.
## crit_tier (#208) only colors the damage number.
func apply_damage_from(amount: int, projectile: Node2D, crit_tier: int = 0) -> void:
	if _dead:
		return
	if not (projectile is Projectile):
		print("[214] container rejected damage: caller is not a real Projectile")
		return
	if not (projectile.get("source") is Player):
		print("[214] container rejected damage: projectile source is not the Player")
		return
	var before := hp
	hp = maxi(0, hp - maxi(amount, 0))
	OnHit.record(self, before, hp) # #390: only the accepted (Player-source) path records
	health_changed.emit(hp)
	CombatEffects.damage_number(get_parent(), global_position, amount, crit_tier)
	if hp == 0:
		_dead = true
		died.emit()
		_spawn_reward_drop()
		queue_free()

## Roll the effective table (instance override wins) against the pool's
## granted set and defer-spawn the drop into my parent (the area). Null table
## or null roll (pool exhausted / empty table) means no drop.
func _spawn_reward_drop() -> void:
	var table: RewardTable = reward_table
	if table == null and definition != null:
		table = definition.reward_table
	if table == null:
		return
	var pool := Run.reward_pool()
	var granted: Array = pool.granted() if pool != null else []
	var entry := table.roll(granted)
	if entry == null:
		return
	var drop: RewardDrop = preload("res://scenes/reward_drop.tscn").instantiate()
	drop.setup(entry)
	# Parent FIRST (deferred), then assign the WORLD position: under a
	# transformed area a pre-parenting assignment lands wrong. Deferred calls
	# run FIFO, so the position assignment happens after the add.
	get_parent().call_deferred("add_child", drop)
	drop.set_deferred("global_position", global_position)
