class_name SpellIcon
extends TextureRect
## Fixed-size icon area for a spell in the UI. Shows Spell.icon when the
## spell has one; otherwise an empty UiStyle placeholder box of the same
## size, so rows never shift when an icon appears or disappears.
## #207: a spell can instead carry a shared SpriteFrames (Spell.icon_frames +
## icon_prefix).
## #238: two independent overlays, above the art and below each other in this
## order. Only surfaces that drive them show them:
##   set_cooldown_fraction - opaque wipe, full at cooldown start, whose top
##     edge moves straight down until gone (HUD only).
##   set_upgrade_available - animated rising chevron, only on icons built with
##     upgrade_overlay = true (HUD and Tab panel). Those icons stay on the
##     "<prefix>_base" art; other surfaces keep the baked "<prefix>_upgraded"
##     frame for upgrade-result spells.

const CHEVRON_FRAMES: SpriteFrames = preload("res://resources/sprites/upgrade_chevron_frames.tres")
const CHEVRON_ANIM := &"pulse"
const CHEVRON_SIDE_FRAC := 0.75
const CHEVRON_RISE_SECONDS := 0.9

var _placeholder: Panel
var _wipe: ColorRect
var _chevron: TextureRect
var _upgrade_overlay: bool
var _chevron_time := 0.0

func _init(side: float = UiStyle.ICON_SIZE, upgrade_overlay: bool = false) -> void:
	name = "SpellIcon"
	_upgrade_overlay = upgrade_overlay
	custom_minimum_size = Vector2(side, side)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Rows are HBoxes that would stretch the box to the row height.
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_placeholder = Panel.new()
	_placeholder.name = "Placeholder"
	_placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder.add_theme_stylebox_override("panel", UiStyle.icon_placeholder())
	add_child(_placeholder)
	_wipe = ColorRect.new()
	_wipe.name = "CooldownWipe"
	_wipe.color = UiStyle.COOLDOWN_WIPE
	_wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wipe.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wipe.visible = false
	add_child(_wipe)
	_chevron = TextureRect.new()
	_chevron.name = "UpgradeChevron"
	_chevron.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_chevron.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_chevron.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chevron_side := roundf(side * CHEVRON_SIDE_FRAC)
	_chevron.size = Vector2(chevron_side, chevron_side)
	_chevron.position.x = (side - chevron_side) * 0.5
	_chevron.visible = false
	add_child(_chevron)

func show_spell(spell: Spell) -> void:
	texture = _base_texture(spell)
	_placeholder.visible = texture == null

## frac = remaining cooldown / total cooldown in [0, 1]: the wipe covers the
## bottom frac of the icon, so 1 is full coverage and 0 is gone.
func set_cooldown_fraction(frac: float) -> void:
	var remaining := clampf(frac, 0.0, 1.0)
	_wipe.visible = remaining > 0.0
	_wipe.set_anchor_and_offset(SIDE_TOP, 1.0 - remaining, 0.0)

## No-op on icons built without upgrade_overlay.
func set_upgrade_available(available: bool) -> void:
	var show_chevron := available and _upgrade_overlay
	if show_chevron == _chevron.visible:
		return
	_chevron.visible = show_chevron
	if show_chevron:
		_chevron_time = 0.0
		_pose_chevron()

func _process(delta: float) -> void:
	if not _chevron.visible:
		return
	_chevron_time += delta
	_pose_chevron()

## Loops the art frames and rises from the icon's bottom edge to its top edge
## on a repeating cycle, staying inside the icon.
func _pose_chevron() -> void:
	var frame_index := int(_chevron_time * CHEVRON_FRAMES.get_animation_speed(CHEVRON_ANIM)) \
		% CHEVRON_FRAMES.get_frame_count(CHEVRON_ANIM)
	_chevron.texture = CHEVRON_FRAMES.get_frame_texture(CHEVRON_ANIM, frame_index)
	var rise := fmod(_chevron_time, CHEVRON_RISE_SECONDS) / CHEVRON_RISE_SECONDS
	_chevron.position.y = (custom_minimum_size.y - _chevron.size.y) * (1.0 - rise)

func _base_texture(spell: Spell) -> Texture2D:
	if spell == null:
		return null
	if spell.icon != null:
		return spell.icon
	if spell.icon_frames != null and spell.icon_prefix != &"":
		var baked := spell.icon_upgraded and not _upgrade_overlay
		var anim: StringName = spell.icon_prefix + ("_upgraded" if baked else "_base")
		if spell.icon_frames.has_animation(anim):
			return spell.icon_frames.get_frame_texture(anim, 0)
	return null
