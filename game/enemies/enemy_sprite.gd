class_name EnemySprite
extends AnimatedSprite2D
## #177: Mustache Warrior animation driver. Lives as the "Sprite" child of an
## Enemy (game/enemies/enemy.tscn, game/enemies/bosses/mustache_warlord.tscn) and is VISUAL
## ONLY: it reads the body's velocity / health_changed and plays whatever a
## behavior asks for through Enemy.play_action(). HP, damage, AI and the
## died() contract never depend on it.
##
## Animations (data/sprites/mustache_warrior_frames.tres):
##   idle / walk          - locomotion, looping, picked from body velocity
##   attack / hurt        - one-shots; locomotion resumes when they finish
##   lunge / spin / ranged / windup_* - boss actions (hold=true keeps them
##                          up until the behavior calls clear_action())
##   death                - played only by the detached corpse (spawn_corpse)
## The art faces RIGHT; flip_h mirrors it toward the target / travel.

## Velocity below this reads as standing still (idle instead of walk).
const WALK_THRESHOLD: float = 10.0
## Telegraph glow: pulse rate (rad/s) and the over-bright peak colour.
const GLOW_RATE: float = 28.0
const GLOW_COLOR: Color = Color(1.45, 1.6, 1.05) # bright but keeps the pixel detail
## Corpse fade after the death animation ends.
const CORPSE_FADE: float = 0.35

## Actions a hit may interrupt. Anything else (boss wind-ups, lunges, spins)
## has super armor: the hit still flashes but the animation keeps playing.
const HURT_INTERRUPTS: Array[StringName] = [&"", &"attack", &"hurt"]

## #476: 8-way sheets (the wolf art) carry one variant per animation per
## screen direction: idle_s/idle_se/idle_e/idle_ne/idle_n/idle_nw/idle_w/
## idle_sw, and the same suffixes for walk/attack/hurt/death/telegraph/
## pounce. When idle_s exists the sprite plays the variant for the body's
## travel direction and never mirrors; sheets without variants keep the
## flip_h behaviour above. Suffix for an octant of Vector2.angle().
const DIR_SUFFIXES: Array[StringName] = [&"e", &"se", &"s", &"sw", &"w", &"nw", &"n", &"ne"]

## #173: true when the sheet's side-on art faces LEFT (the Head boss walk
## row); face() then mirrors the other way. Default: art faces right.
@export var art_faces_left: bool = false
## #173: colour of the death burst Enemy spawns for this art (Mustache
## Warrior green by default, matching Enemy.SPRITE_BURST_COLOR).
@export var burst_color: Color = Color(0.62, 0.9, 0.24)

var _action: StringName = &""
var _hold: bool = false
var _last_hp: int = -1
var _glow: bool = false
var _glow_t: float = 0.0
var _is_corpse: bool = false
## #476: last travel direction (8-way sheets) and whether this sheet
## carries directional variants.
var _facing: Vector2 = Vector2.RIGHT
var _directional: bool = false

func _ready() -> void:
	animation_finished.connect(_on_animation_finished)
	_directional = sprite_frames != null and sprite_frames.has_animation(&"idle_s")
	if _is_corpse:
		play(_variant(&"death"))
		return
	var body := get_parent()
	if body != null and body.has_signal("health_changed"):
		body.connect(&"health_changed", _on_health_changed)
	play(&"idle")

## Current one-shot / held action, or &"" while on locomotion.
func current_action() -> StringName:
	return _action

## Play `anim` from its first frame. hold=false: locomotion resumes when a
## non-looping anim finishes. hold=true: stays until clear_action().
func play_action(anim: StringName, hold: bool = false) -> void:
	var variant := _variant(anim)
	if sprite_frames == null or not sprite_frames.has_animation(variant):
		return
	_action = anim # base name: HURT_INTERRUPTS / current_action() stay directional-agnostic
	_hold = hold
	stop()
	play(variant)

func clear_action() -> void:
	_action = &""
	_hold = false
	set_glow(false)

## Telegraph glow (boss wind-ups): pulses self_modulate over-bright.
func set_glow(on: bool) -> void:
	_glow = on
	_glow_t = 0.0
	if not on:
		self_modulate = Color.WHITE

## The animation for `base` in the current travel direction, when this
## sheet carries directional variants; otherwise `base` itself.
func _variant(base: StringName) -> StringName:
	if not _directional or sprite_frames == null:
		return base
	var octant := int(round(_facing.angle() / (PI / 4.0))) & 7
	var name := StringName("%s_%s" % [base, DIR_SUFFIXES[octant]])
	return name if sprite_frames.has_animation(name) else base

## Mirror toward a horizontal direction (art faces right). Tiny x is ignored
## so a target straight above/below never flickers the facing.
func face(dir_x: float) -> void:
	if absf(dir_x) > 0.5:
		flip_h = (dir_x < 0.0) != art_faces_left

func _process(delta: float) -> void:
	if _is_corpse:
		return
	if _glow:
		_glow_t += delta
		var k: float = 0.5 + 0.5 * sin(_glow_t * GLOW_RATE)
		self_modulate = Color.WHITE.lerp(GLOW_COLOR, k)
	var body := get_parent() as CharacterBody2D
	if body == null:
		return
	if _action == &"":
		if _directional:
			# 8-way art: pick the variant for the travel direction; a standing
			# wolf keeps its last facing (the telegraph aims it).
			if body.velocity.length() > WALK_THRESHOLD:
				_facing = body.velocity
			var loco := _variant(&"walk" if body.velocity.length() > WALK_THRESHOLD else &"idle")
			if animation != loco or not is_playing():
				play(loco)
		else:
			face(body.velocity.x)
			var loco: StringName = &"walk" if body.velocity.length() > WALK_THRESHOLD else &"idle"
			if animation != loco or not is_playing():
				play(loco)

func _on_health_changed(current: int, _max_hp: int) -> void:
	# Enemies only ever lose HP; the first event (no previous value) is a hit.
	var dropped: bool = _last_hp < 0 or current < _last_hp
	if dropped and current > 0 and HURT_INTERRUPTS.has(_action):
		play_action(&"hurt")
	_last_hp = current

func _on_animation_finished() -> void:
	if _is_corpse:
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, CORPSE_FADE)
		tw.tween_callback(queue_free)
		return
	if not _hold:
		_action = &""

## Death: a detached copy plays the death animation at the body's spot and
## frees itself, so the Enemy can keep its free-on-death contract (#5/#110).
## Deferred add (D14) into `parent` (the area), like the combat effects.
static func spawn_corpse(src: EnemySprite, parent: Node) -> EnemySprite:
	var c := EnemySprite.new()
	c._is_corpse = true
	c._facing = src._facing
	c.sprite_frames = src.sprite_frames
	c.texture_filter = src.texture_filter
	c.flip_h = src.flip_h
	c.modulate = src.modulate
	c.offset = src.offset
	c.centered = src.centered
	c.scale = src.global_scale
	c.position = src.global_position
	c.z_index = src.z_index
	c.animation = &"death"
	c.add_to_group(&"enemy_corpses")
	parent.call_deferred("add_child", c)
	return c
