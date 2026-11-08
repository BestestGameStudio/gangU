class_name Summon
extends CharacterBody2D
## #209: player summon entity (foundation). A damageable ally with the same
## documented contract as Enemy: died(), health_changed() and a single
## apply_damage() entry point that clamps HP and emits only from inside, so
## summon HP can never change silently.
## NO movement or AI lives here: summon control/behavior is deferred (#209
## foundation excludes it; later issues own it). This entity is intentionally
## inert - it exists, takes damage, and dies.

signal died()
signal health_changed(current: int, max_hp: int)

var max_hp: int = 30
var hp: int
## DamageCalc receiver seam: enemy contact damage on a summon computes
## through the one standard damage path, same as the player.
var damage_modifiers := DamageModifiers.new()
var definition: SummonDefinition

func setup(def: SummonDefinition) -> void:
	definition = def
	if definition != null:
		max_hp = definition.max_hp

func _ready() -> void:
	hp = max_hp
	add_to_group("summons")

func apply_damage(amount: int) -> void:
	if hp <= 0:
		return
	hp = clampi(hp - amount, 0, max_hp)
	health_changed.emit(hp, max_hp)
	if hp == 0:
		died.emit()
		queue_free()
