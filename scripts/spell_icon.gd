class_name SpellIcon
extends TextureRect
## Fixed-size icon area for a spell in the UI. Shows Spell.icon when the
## spell has one; otherwise an empty UiStyle placeholder box of the same
## size, so rows never shift when an icon appears or disappears.

var _placeholder: Panel

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
	texture = spell.icon if spell != null else null
	_placeholder.visible = texture == null
