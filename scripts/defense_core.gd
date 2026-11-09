class_name DefenseCore
extends Node2D
## #337: the object the player defends in a DEFENSE objective. It has a large
## HP pool and enemies can attack it: it implements the same target contract
## the chase/contact behavior uses for Player and Summon (hp, global_position,
## damage_modifiers, apply_damage), plus `contact_radius` so attackers stop at
## its rim instead of its centre.
## It has NO physics body, so player spells (which hit bodies) never damage it
## and it does not block movement. Code-drawn crystal + overhead HP bar.
## max_hp is a tunable default chosen by the implementer, not approved balance.

signal health_changed(current: int, max_hp: int)
## Emitted once when hp reaches 0. DungeonObjective treats it as a failed defense.
signal destroyed()

@export var max_hp: int = 800
## Attackers stop and hit at contact_range + contact_radius from the centre.
@export var contact_radius: float = 30.0

var hp: int
var damage_modifiers := DamageModifiers.new()
var _flash_t := 0.0
var _anim_t := 0.0

const BAR_W := 84.0
const BAR_H := 8.0
const BAR_Y := -62.0
const CRYSTAL := Color(0.35, 0.85, 1.0)
const CRYSTAL_DARK := Color(0.12, 0.38, 0.6)
const BROKEN := Color(0.3, 0.3, 0.34)

func _ready() -> void:
	hp = max_hp
	add_to_group(&"defense_cores")
	queue_redraw()

func is_destroyed() -> bool:
	return hp <= 0

## Single HP mutation point (D7). crit_tier only matters for the number color.
func apply_damage(amount: int, crit_tier: int = 0) -> void:
	if hp <= 0:
		return
	var before := hp
	hp = clampi(hp - amount, 0, max_hp)
	OnHit.record(self, before, hp) # #390
	_flash_t = 0.12
	health_changed.emit(hp, max_hp)
	if get_parent() != null:
		CombatEffects.damage_number(get_parent(), global_position, amount, crit_tier)
	queue_redraw()
	if hp == 0:
		destroyed.emit()

const CombatEffects = preload("res://scripts/combat_effects.gd")

func _process(delta: float) -> void:
	_anim_t += delta
	if _flash_t > 0.0:
		_flash_t -= delta
	queue_redraw()

func _draw() -> void:
	var alive := hp > 0
	var base := CRYSTAL if alive else BROKEN
	if _flash_t > 0.0:
		base = Color(1.0, 0.55, 0.5)
	var bob := sin(_anim_t * 2.0) * 3.0 if alive else 0.0
	# pedestal
	draw_colored_polygon(PackedVector2Array([Vector2(-34, 22), Vector2(34, 22), Vector2(26, 34), Vector2(-26, 34)]), Color(0.25, 0.27, 0.32))
	if alive:
		draw_circle(Vector2(0, bob - 4), 40.0, Color(base, 0.12))
	# crystal
	var top := Vector2(0, -44 + bob)
	var pts := PackedVector2Array([top, Vector2(20, -8 + bob), Vector2(0, 20 + bob), Vector2(-20, -8 + bob)])
	draw_colored_polygon(pts, base.darkened(0.15))
	draw_colored_polygon(PackedVector2Array([top, Vector2(0, 20 + bob), Vector2(-20, -8 + bob)]), base.lightened(0.25))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), CRYSTAL_DARK if alive else Color(0.15, 0.15, 0.17), 2.0)
	# HP bar
	var frac := float(hp) / float(maxi(max_hp, 1))
	draw_rect(Rect2(-BAR_W / 2 - 1, BAR_Y - 1, BAR_W + 2, BAR_H + 2), Color(0, 0, 0, 0.8))
	draw_rect(Rect2(-BAR_W / 2, BAR_Y, BAR_W * frac, BAR_H), Color(0.3, 0.9, 1.0) if frac > 0.3 else Color(1.0, 0.35, 0.3))
