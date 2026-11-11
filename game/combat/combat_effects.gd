extends Node2D
## #110: combat feedback effects - visual only. Code-drawn flat geometric
## (no external assets, gradients or glow), brief, and receded enough to keep
## entity/state colors dominant. One node per effect, spawned into the AREA
## or scene root so it survives a dying enemy; every effect owns its own
## lifetime and frees itself - no remnant, no gameplay state.
## (#289: summon_circle is the one exception, playing supplied sprite art.)

enum Kind { DEATH_BURST, HIT_SPARK, MUZZLE }

const DEATH_SHARDS: int = 8
const DEATH_LIFETIME: float = 0.3
const DEATH_START_R: float = 6.0
const DEATH_END_R: float = 30.0
const HIT_SPIKES: int = 4
const HIT_LIFETIME: float = 0.15
const HIT_START_R: float = 3.0
const HIT_END_R: float = 14.0
const HIT_COLOR: Color = Color(1.0, 0.95, 0.6)
const MUZZLE_SPIKES: int = 3
const MUZZLE_LIFETIME: float = 0.15
const MUZZLE_START_R: float = 3.0
const MUZZLE_END_R: float = 16.0
const SUMMON_FRAMES: SpriteFrames = preload("res://data/sprites/spell_upgrades_frames.tres")
const SUMMON_ANIM: StringName = &"summon_ally"
const SUMMON_CIRCLE_OFFSET: Vector2 = Vector2(0.0, -13.0) ## The circle sits below the cell centre.

var _kind: int = Kind.DEATH_BURST
var _color: Color = Color.WHITE
var _t: float = 0.0
var _life: float = DEATH_LIFETIME

## Spawn a death burst at `pos` tinted with the enemy's own color. Deferred
## add: safe from physics callbacks, and the parent (area) owns the node.
static func death_burst(parent: Node, pos: Vector2, color: Color) -> void:
	var fx: Node2D = _make(Kind.DEATH_BURST, color, DEATH_LIFETIME)
	fx.position = pos
	parent.call_deferred("add_child", fx)

## Brief contact spark at the damage-apply site. Distinct from the #109
## over-bright flash: tiny, short, and at the hit position only.
static func hit_spark(parent: Node, pos: Vector2) -> void:
	var fx: Node2D = _make(Kind.HIT_SPARK, HIT_COLOR, HIT_LIFETIME)
	fx.position = pos
	parent.call_deferred("add_child", fx)

## Floating number for the damage a hit dealt, at the enemy's position,
## colored by the hit's rolled crit tier (#208).
static func damage_number(parent: Node, at: Vector2, amount: int, crit_tier: int = 0) -> void:
	if amount <= 0:
		return
	if parent is CanvasItem: at = (parent as CanvasItem).to_local(at) # global to parent-local
	parent.call_deferred("add_child", DamageNumber.create(at, amount, crit_tier))

## Muzzle accent at the cast point, rotated to the cast direction and tinted
## with the spell's own projectile color.
static func muzzle(parent: Node, pos: Vector2, angle: float, color: Color) -> void:
	var fx: Node2D = _make(Kind.MUZZLE, color, MUZZLE_LIFETIME)
	fx.position = pos
	fx.rotation = angle
	parent.call_deferred("add_child", fx)

## #289: one-shot summoning circle from the supplied spell sheet, drawn at
## scale 1 with the circle centred on `pos`. Frees itself when it finishes.
static func summon_circle(parent: Node, pos: Vector2) -> void:
	var fx := AnimatedSprite2D.new()
	fx.sprite_frames = SUMMON_FRAMES
	fx.animation = SUMMON_ANIM
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.offset = SUMMON_CIRCLE_OFFSET
	fx.position = pos
	fx.add_to_group(&"combat_fx")
	fx.animation_finished.connect(fx.queue_free)
	parent.call_deferred("add_child", fx)
	fx.play()

static func _make(kind: int, color: Color, life: float) -> Node2D:
	var fx: Node2D = new()
	fx.set(&"_kind", kind)
	fx.set(&"_color", color)
	fx.set(&"_life", life)
	fx.add_to_group(&"combat_fx")
	fx.set_meta("kind", Kind.keys()[kind])
	fx.set_meta("life", life)
	return fx

func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var f: float = clampf(_t / _life, 0.0, 1.0)
	var c: Color = _color
	c.a = 1.0 - f
	match _kind:
		Kind.DEATH_BURST:
			_draw_burst(f, c)
		Kind.HIT_SPARK:
			_draw_spark(f, c)
		Kind.MUZZLE:
			_draw_muzzle(f, c)

func _draw_burst(f: float, c: Color) -> void:
	var r: float = lerpf(DEATH_START_R, DEATH_END_R, f)
	var s: float = lerpf(6.0, 1.5, f)
	for i in DEATH_SHARDS:
		var dir: Vector2 = Vector2.RIGHT.rotated(TAU * float(i) / float(DEATH_SHARDS))
		var side: Vector2 = dir.orthogonal() * s * 0.5
		draw_colored_polygon(PackedVector2Array([dir * r + side, dir * (r + s * 1.5), dir * r - side]), c)

func _draw_spark(f: float, c: Color) -> void:
	var r: float = lerpf(HIT_START_R, HIT_END_R, f)
	for i in HIT_SPIKES:
		var dir: Vector2 = Vector2.RIGHT.rotated(TAU * (float(i) + 0.5) / float(HIT_SPIKES))
		var side: Vector2 = dir.orthogonal() * 1.5
		draw_colored_polygon(PackedVector2Array([dir * r * 0.3 + side, dir * r, dir * r * 0.3 - side]), c)

func _draw_muzzle(f: float, c: Color) -> void:
	var r: float = lerpf(MUZZLE_START_R, MUZZLE_END_R, f)
	for i in MUZZLE_SPIKES:
		var dir: Vector2 = Vector2.RIGHT.rotated((float(i) - 1.0) * 0.5)
		var side: Vector2 = dir.orthogonal() * 1.5
		draw_colored_polygon(PackedVector2Array([dir * r * 0.3 + side, dir * (r + 4.0), dir * r * 0.3 - side]), c)
	draw_circle(Vector2.ZERO, 2.5, c)
