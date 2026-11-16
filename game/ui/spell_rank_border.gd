class_name SpellRankBorder
extends Control
## #255: rank border around a SpellIcon, in the owned spell's upgrade tier
## color (SpellProgress.get_tier): 0 Base silver, 1 Specialization gold,
## 2 Mastery red, 3 Signature purple.
## #700: the code-drawn frames are replaced by ornate frame art in SpriteU
## format (assets/sprites/ui/icon-frame-*.png, provenance in
## assets/sprites/ui/SOURCE.md): a 3-tone metal frame with a top crest gem and
## corner studs, one colorway per tier, palette-true to UiStyle.RANK_COLORS.
## The frame's interior is transparent, so the icon art shows through; it is
## drawn slightly LARGER than the icon rect so its rails wrap the icon's own
## baked frame. tier = NONE hides it (empty slots, shop, directory).

const NONE := -1
const MAX_TIER := 3

const TIER_FRAMES: Array[Texture2D] = [
	preload("res://assets/sprites/ui/icon-frame-silver.png"),
	preload("res://assets/sprites/ui/icon-frame-gold.png"),
	preload("res://assets/sprites/ui/icon-frame-red.png"),
	preload("res://assets/sprites/ui/icon-frame-purple.png"),
]

var tier := NONE

func _init() -> void:
	name = "RankBorder"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # pixel art: no softening
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

func set_tier(value: int) -> void:
	var t := clampi(value, NONE, MAX_TIER)
	if t == tier:
		return
	tier = t
	visible = tier != NONE
	queue_redraw()

## Pixel unit: 1 px at the 22 px panel icons, 2 px at the 48 px HUD squares.
func unit() -> float:
	return maxf(1.0, roundf(minf(size.x, size.y) / 24.0))

func color() -> Color:
	return UiStyle.RANK_COLORS[tier] if tier != NONE else Color.TRANSPARENT

## Outermost extent of the drawing past the icon rect, per side, in px: the
## frame's 3 px rails (in art pixels) scaled by the pixel unit.
func overhang() -> float:
	return 3.0 * unit()

func _draw() -> void:
	if tier == NONE:
		return
	var m := overhang()
	draw_texture_rect(TIER_FRAMES[tier], Rect2(Vector2(-m, -m), size + Vector2(2.0 * m, 2.0 * m)), false)
