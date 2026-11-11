class_name Barricade
extends StaticBody2D
## #420: deployable wooden barricade. Daniel, 2026-11-09 (WhatsApp):
##   "Barricades are high health wooden structures that block spells and can
##    be destroyed by players. Special Moustache men can deploy barricades as
##    cover. They start decaying HP as soon as they're placed (staying for a
##    maximum of 30s)."
## Follow-up (same thread): "Barricades block both friendly and enemy
## piercing and lobbed spells are not blocked. Any player source damage."
##
## Spell blocking needs no projectile changes:
##   - Ordinary (untagged) shots, friendly AND enemy: this is a solid body
##     with apply_damage_from, so Projectile._on_body_entered dispatches the
##     hit and then despawns the shot. Enemy shots are rejected by the gate
##     below (no HP lost) but are still eaten.
##   - PIERCING shots: Projectile returns before queue_free on a PIERCING
##     hit, so they fly on through (a player's piercing shot still damages
##     the barricade on the way, once per shot).
##   - LOBBED shots (mustache rocks): Projectile._lobs_over skips every body
##     in the "cover" group, which this joins in _ready.
##
## Damage gate ("any player source damage"): a projectile is accepted when
## its source is the Player or a Player-owned Summon. Plain apply_damage is
## the non-projectile path; its only production callers that can reach a
## barricade are the player-side AoE/melee passes (Water splash, Stone
## Hammer, summon melee - each targets barricades through the "barricades"
## group / slide contact), so it is accepted. Enemy attacks never call it:
## enemies target the player, summons or the defense core only.
##
## Decay: HP drains at max_hp / LIFETIME per second from the moment the
## barricade enters the tree, so an untouched barricade reaches 0 exactly at
## LIFETIME; the LIFETIME clock is also a hard cap. Dies once at 0 HP.
##
## Cover: joins the #406 "cover" group so the cover machine can hold behind
## it (enemy_behavior_cover.gd). Movement: a solid StaticBody2D, like the
## #214 container (whether it should block movement is human-open on #420).
## All numbers are PLACEHOLDER tuning (Daniel: "use reasonable defaults").

const CombatEffects = preload("res://game/combat/combat_effects.gd")

signal health_changed(current: int, max_hp: int)
signal died()

const LIFETIME: float = 30.0 ## Daniel: "staying for a maximum of 30s"
const WIDTH: float = 44.0 ## across the line of fire (PLACEHOLDER)
const THICKNESS: float = 12.0 ## along the line of fire (PLACEHOLDER)
const WOOD := Color(0.55, 0.36, 0.18)
const WOOD_DARK := Color(0.33, 0.2, 0.09)
const WOOD_LIGHT := Color(0.72, 0.5, 0.27)

@export var max_hp: int = 150 ## "high health": ~6 Fire Balls / 15 Mana Shots (PLACEHOLDER)

var hp: int = 0
## The enemy that deployed this barricade (null when placed by hand).
var deployer: Node2D = null
## Seconds since placement (the decay / max-lifetime clock).
var age: float = 0.0
var _decay_acc: float = 0.0
var _dead := false
var _flash_t := 0.0

func _ready() -> void:
	add_to_group(&"cover")
	add_to_group(&"barricades")
	hp = max_hp
	if not has_node("CollisionShape2D"):
		var cs := CollisionShape2D.new()
		cs.name = "CollisionShape2D"
		var rect := RectangleShape2D.new()
		rect.size = Vector2(THICKNESS, WIDTH)
		cs.shape = rect
		add_child(cs)
	queue_redraw()

## Seconds left before the max-lifetime cap removes it.
func time_left() -> float:
	return maxf(0.0, LIFETIME - age)

func _physics_process(delta: float) -> void:
	if _dead:
		return
	age += delta
	_flash_t = maxf(0.0, _flash_t - delta)
	_decay_acc += float(max_hp) / LIFETIME * delta
	var drain := int(_decay_acc)
	if drain > 0:
		_decay_acc -= drain
		_lose(drain)
	if not _dead and age >= LIFETIME:
		_lose(hp)
	queue_redraw()

## True when `src` is the Player or a Summon owned by a Player.
static func is_player_side(src: Variant) -> bool:
	if src == null or not is_instance_valid(src):
		return false
	if src is Player:
		return true
	return src is Summon and is_instance_valid(src.player) and src.player is Player

## Projectile dispatch (#214 additive branch in projectile.gd).
func apply_damage_from(amount: int, projectile: Node2D, crit_tier: int = 0) -> void:
	if _dead:
		return
	if not (projectile is Projectile) or not is_player_side(projectile.get("source")):
		return # enemy (or unknown) shot: blocked, no damage
	_take_hit(amount, crit_tier)

## Non-projectile player-side damage (Water splash, Stone Hammer, summon
## melee - see the header for why this path is accepted).
func apply_damage(amount: int, crit_tier: int = 0) -> void:
	if _dead:
		return
	_take_hit(amount, crit_tier)

func _take_hit(amount: int, crit_tier: int) -> void:
	var before := hp
	_flash_t = 0.1
	_lose(maxi(amount, 0))
	OnHit.record(self, before, hp) # #390
	if get_parent() != null:
		CombatEffects.damage_number(get_parent(), global_position, amount, crit_tier)

func _lose(amount: int) -> void:
	if _dead or amount <= 0:
		return
	hp = maxi(0, hp - amount)
	health_changed.emit(hp, max_hp)
	if hp == 0:
		_dead = true
		died.emit()
		if get_parent() != null:
			CombatEffects.death_burst(get_parent(), global_position, WOOD)
		queue_free()

func _draw() -> void:
	var frac := float(hp) / float(maxi(max_hp, 1))
	var tint := Color(2.0, 2.0, 2.0) if _flash_t > 0.0 else Color.WHITE
	# Drawn in local space: x = along the line of fire, y = across it. The
	# deployer rotates the body to face the player.
	var half_t := THICKNESS * 0.5
	var half_w := WIDTH * 0.5
	draw_rect(Rect2(-half_t + 2.0, -half_w + 2.0, THICKNESS, WIDTH), Color(0, 0, 0, 0.3))
	var planks := 4
	var pw := WIDTH / planks
	for i in planks:
		var y := -half_w + i * pw
		var c := (WOOD if i % 2 == 0 else WOOD_LIGHT).lerp(WOOD_DARK, (1.0 - frac) * 0.6)
		draw_rect(Rect2(-half_t, y + 0.5, THICKNESS, pw - 1.0), c * tint)
	# Cross brace + posts.
	draw_line(Vector2(-half_t + 1, -half_w + 2), Vector2(half_t - 1, half_w - 2), WOOD_DARK * tint, 2.0)
	draw_rect(Rect2(-half_t - 1.0, -half_w - 2.0, THICKNESS + 2.0, 4.0), WOOD_DARK * tint)
	draw_rect(Rect2(-half_t - 1.0, half_w - 2.0, THICKNESS + 2.0, 4.0), WOOD_DARK * tint)
	# Cracks appear as it decays / takes damage.
	if frac < 0.66:
		draw_line(Vector2(-2, -half_w * 0.6), Vector2(3, -half_w * 0.1), Color(0.12, 0.07, 0.03), 1.5)
	if frac < 0.33:
		draw_line(Vector2(2, half_w * 0.2), Vector2(-3, half_w * 0.7), Color(0.12, 0.07, 0.03), 1.5)
	# HP bar (local -x side would rotate with the body; keep it short and
	# readable in any orientation by drawing it unrotated).
	draw_set_transform(Vector2.ZERO, -global_rotation)
	var bw := 34.0
	var by := -WIDTH * 0.5 - 12.0
	draw_rect(Rect2(-bw * 0.5, by, bw, 4.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-bw * 0.5, by, bw * frac, 4.0), Color(0.9, 0.65, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0)
