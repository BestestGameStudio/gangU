class_name Summon
extends CharacterBody2D
## #209: player summon entity (foundation). A damageable ally with the same
## documented contract as Enemy: died(), health_changed() and a single
## apply_damage() entry point that clamps HP and emits only from inside, so
## summon HP can never change silently.
## #212: optional behavior slot (definition.behavior, enemy.gd idiom). With a
## behavior assigned, the summon moves/fights via _physics_process delegation;
## with none it stays intentionally inert (the #209 foundation default).

signal died()
signal health_changed(current: int, max_hp: int)

var max_hp: int = 30
var hp: int
## DamageCalc receiver seam: enemy contact damage on a summon computes
## through the one standard damage path, same as the player.
var damage_modifiers := DamageModifiers.new()
var definition: SummonDefinition
## #212: the player this summon guards. Wired by SummonManager BEFORE
## add_child (player_path idiom); null in harnesses - behaviors tolerate it.
var player: Node2D = null
## #212: per-entity damage rolls for behavior attacks, same idiom as Enemy.
var damage_rng := RandomNumberGenerator.new()

var _behavior = null

func setup(def: SummonDefinition) -> void:
	definition = def
	if definition != null:
		max_hp = definition.max_hp

func _ready() -> void:
	hp = max_hp
	add_to_group("summons")
	damage_rng.randomize()
	# #212: each Summon instantiates its OWN behavior instance, so per-summon
	# state (contact cooldown) is never shared across summons.
	if definition != null and definition.behavior != null:
		_behavior = definition.behavior.new()

func _physics_process(delta: float) -> void:
	if _behavior != null and hp > 0:
		_behavior.physics_step(self, player, delta)

func apply_damage(amount: int) -> void:
	if hp <= 0:
		return
	hp = clampi(hp - amount, 0, max_hp)
	health_changed.emit(hp, max_hp)
	if hp == 0:
		died.emit()
		queue_free()
