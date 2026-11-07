extends Node2D
class_name SpellCaster
## Casting core (#3): owns collected spells, per-spell cooldowns, and spawning
## projectiles toward the cursor. Consumes the shared `cast` input action.
## Supports many spells and later switching (#10) via add_spell/next_spell.

signal spell_cast(spell: Spell)
signal cooldown_started(spell: Spell, duration: float)
signal spell_equipped(spell: Spell)
## #10: emitted on EVERY add (starting spells and pickups) so HUD rows follow.
signal spell_added(spell: Spell)

@export var projectile_scene: PackedScene
@export var starting_spells: Array[Spell] = []

var spells: Array[Spell] = []
var current_index: int = 0
var _cooldowns: Dictionary = {} ## Spell -> remaining seconds

var _bar_fill: Polygon2D
var _bar_bg: Polygon2D

var equipped_spell: Spell:
	get:
		if spells.is_empty():
			return null
		return spells[current_index]

func _ready() -> void:
	for s in starting_spells:
		add_spell(s)
	# Simple on-player cooldown bar so a blocked recast is visible in-game (#3
	# acceptance). The real HUD is #11.
	_bar_bg = $CooldownBarBG
	_bar_fill = $CooldownBarFill

func add_spell(spell: Spell) -> void:
	spells.append(spell)
	spell_added.emit(spell)
	if spells.size() == 1:
		current_index = 0
		spell_equipped.emit(spell)

func next_spell() -> void:
	if spells.size() > 1:
		current_index = (current_index + 1) % spells.size()
		spell_equipped.emit(equipped_spell)

func cooldown_remaining(spell: Spell) -> float:
	return _cooldowns.get(spell, 0.0)

func can_cast() -> bool:
	return equipped_spell != null and cooldown_remaining(equipped_spell) <= 0.0

func _process(delta: float) -> void:
	for s in _cooldowns.keys():
		_cooldowns[s] = maxf(_cooldowns[s] - delta, 0.0)
	_update_bar()
	if Input.is_action_just_pressed(&"cast") and can_cast():
		cast()
	# #10: switching is caster-owned (player.gd untouched). The action has no
	# key bound until the human key choice lands; harness drives next_spell().
	if InputMap.has_action(&"switch_spell") and Input.is_action_just_pressed(&"switch_spell"):
		next_spell()

func cast() -> void:
	var spell := equipped_spell
	var dir := global_position.direction_to(get_global_mouse_position())
	if dir.length_squared() == 0.0:
		dir = Vector2.RIGHT.rotated(get_parent().rotation)
	var p: Projectile = projectile_scene.instantiate()
	p.setup(spell, dir, get_parent())
	get_tree().current_scene.add_child(p)
	p.global_position = global_position
	_cooldowns[spell] = spell.cooldown
	cooldown_started.emit(spell, spell.cooldown)
	spell_cast.emit(spell)

func _update_bar() -> void:
	if equipped_spell == null:
		return
	# Keep the bar upright: the parent player rotates to face the cursor.
	_bar_bg.global_rotation = 0.0
	_bar_fill.global_rotation = 0.0
	var frac := 1.0 - clampf(cooldown_remaining(equipped_spell) / equipped_spell.cooldown, 0.0, 1.0)
	_bar_fill.scale.x = maxf(frac, 0.001)
