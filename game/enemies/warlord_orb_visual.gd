class_name WarlordOrbVisual
extends Node2D
## #177: the Mustache Warlord's orb, drawn from the sheet's ranged-orb cell
## (row 8) with the sheet's sparkle FX (row 9) as a spinning glow behind the
## head. Used as a Projectile.visual_override, so only the boss's orbs change.
## The art faces +X (comet tail behind), matching the projectile's rotation.
## Scale: head ~5 px * ORB_SCALE ~= 12.5 px, matching the 6 px hit radius of
## data/spells/warlord_orb.tres. Visual only.

const SHEET: Texture2D = preload("res://assets/sprites/mustache_warrior.png")
## Tight regions in the packed sheet (64x48 cells).
const ORB_REGION: Rect2 = Rect2(27, 405, 12, 6) ## row 8, col 0
const SPARKLE_REGION: Rect2 = Rect2(150, 446, 19, 21) ## row 9, col 2
const BURST_REGION: Rect2 = Rect2(215, 445, 18, 21) ## row 9, col 3
## Orb head centre relative to ORB_REGION's centre (texture px).
const HEAD_OFFSET: Vector2 = Vector2(2.5, -0.5)
const ORB_SCALE: float = 2.5
const SPARKLE_SCALE: float = 0.9
const SPIN_RATE: float = 9.0
const PULSE_RATE: float = 20.0
const PULSE_AMP: float = 0.12
const POP_TIME: float = 0.22

var _t: float = 0.0
var _orb: Sprite2D
var _glow: Sprite2D

static func _atlas(region: Rect2) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = SHEET
	a.region = region
	return a

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_glow = Sprite2D.new()
	_glow.name = "Glow"
	_glow.texture = _atlas(SPARKLE_REGION)
	_glow.scale = Vector2(SPARKLE_SCALE, SPARKLE_SCALE)
	_glow.modulate = Color(1, 1, 1, 0.7)
	add_child(_glow)
	_orb = Sprite2D.new()
	_orb.name = "Orb"
	_orb.texture = _atlas(ORB_REGION)
	_orb.offset = -HEAD_OFFSET
	_orb.scale = Vector2(ORB_SCALE, ORB_SCALE)
	add_child(_orb)

func _process(delta: float) -> void:
	_t += delta
	_glow.rotation += SPIN_RATE * delta
	var k: float = 1.0 + PULSE_AMP * sin(_t * PULSE_RATE)
	_glow.scale = Vector2(SPARKLE_SCALE, SPARKLE_SCALE) * k
	_orb.scale = Vector2(ORB_SCALE, ORB_SCALE) * (1.0 + PULSE_AMP * 0.5 * sin(_t * PULSE_RATE))

## Impact pop (the sheet's burst FX): grows and fades, then frees itself.
## Deferred add (D14) - hits fire inside physics callbacks.
static func spawn_pop(parent: Node, pos: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _atlas(BURST_REGION)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.position = pos
	s.scale = Vector2(0.6, 0.6)
	s.add_to_group(&"warlord_orb_pops")
	s.ready.connect(func() -> void:
		var tw := s.create_tween()
		tw.set_parallel(true)
		tw.tween_property(s, "scale", Vector2(1.8, 1.8), POP_TIME)
		tw.tween_property(s, "modulate:a", 0.0, POP_TIME)
		tw.chain().tween_callback(s.queue_free))
	parent.call_deferred("add_child", s)
	return s
