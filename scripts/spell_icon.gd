class_name SpellIcon
extends TextureRect
## Fixed-size icon area for a spell in the UI. Shows Spell.icon when the
## spell has one; otherwise an empty UiStyle placeholder box of the same
## size, so rows never shift when an icon appears or disappears.
## #207: a spell can instead carry a shared SpriteFrames (Spell.icon_frames +
## icon_prefix). Upgrade-result spells (icon_upgraded) show the green-chevron
## "<prefix>_upgraded" frame; set_cooldown_fraction swaps in the gray
## "<prefix>_sweep" frame matching the remaining cooldown fraction, and 0
## restores the base frame.

var _placeholder: Panel
var _base: Texture2D
var _sweep: SpriteFrames
var _sweep_anim: StringName

func _init(side: float = UiStyle.ICON_SIZE) -> void:
	name = "SpellIcon"
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

func show_spell(spell: Spell) -> void:
	_base = _base_texture(spell)
	_sweep = null
	if spell != null and spell.icon_frames != null and spell.icon_prefix != &"":
		var anim: StringName = spell.icon_prefix + "_sweep"
		if spell.icon_frames.has_animation(anim):
			_sweep = spell.icon_frames
			_sweep_anim = anim
	texture = _base
	_placeholder.visible = texture == null

## frac = remaining cooldown / total cooldown in [0, 1]. 0 (or a spell with
## no sweep art) shows the base frame; otherwise the sweep frame whose gray
## coverage matches frac (higher frac = more covered).
func set_cooldown_fraction(frac: float) -> void:
	if frac <= 0.0 or _sweep == null:
		if texture != _base:
			texture = _base
		_placeholder.visible = texture == null
		return
	var count := _sweep.get_frame_count(_sweep_anim)
	var idx := clampi(int(ceil(frac * count)) - 1, 0, count - 1)
	texture = _sweep.get_frame_texture(_sweep_anim, idx)
	_placeholder.visible = false

func _base_texture(spell: Spell) -> Texture2D:
	if spell == null:
		return null
	if spell.icon != null:
		return spell.icon
	if spell.icon_frames != null and spell.icon_prefix != &"":
		var anim: StringName = spell.icon_prefix + ("_upgraded" if spell.icon_upgraded else "_base")
		if spell.icon_frames.has_animation(anim):
			return spell.icon_frames.get_frame_texture(anim, 0)
	return null
