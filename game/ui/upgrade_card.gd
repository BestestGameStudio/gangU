class_name UpgradeCard
extends Button
## #402 presentation only. The panel owns eligibility, path IDs and actions.
## No placeholder illustration: applied text uses the card interior.
const CARD_WIDTH := 176.0
const CARD_HEIGHT := CARD_WIDTH * 64.0 / 48.0
const CONTENT_INSET := 20
const SATISFIED_PROGRESS := Color("58d878")
const LOCK_TEXTURE: Texture2D = preload("res://assets/sprites/ui/upgrade-lock.png")
const OPEN_LOCK_TEXTURE: Texture2D = preload("res://assets/sprites/ui/upgrade-open-lock.png")
var name_label: Label
var description_label: Label
var action_label: Label
var progress_bar: ProgressBar
var progress_label: Label
var lock_sign: Control
var _concealed_spacer: Control
var _content: VBoxContainer
var border_color: Color = UiStyle.B_ACCENT

## #700: ornate card frame (assets/sprites/ui/card-frame-*.png, SpriteU
## format; provenance in assets/sprites/ui/SOURCE.md): aspect-preserved with a
## transparent interior, one colorway per upgrade tier (UiStyle.RANK_COLORS).
const TIER_FRAMES: Array[Texture2D] = [
	preload("res://assets/sprites/ui/card-frame-silver.png"),
	preload("res://assets/sprites/ui/card-frame-gold.png"),
	preload("res://assets/sprites/ui/card-frame-red.png"),
	preload("res://assets/sprites/ui/card-frame-purple.png"),
]
var _frame: TextureRect
var _border_tier := 0
var _locked := false
var _concealed := false
var _unavailable := false
var _grey_material: ShaderMaterial

func _init() -> void:
	custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UiStyle.style_button(self, UiStyle.B_ACCENT, 10)
	var margin := MarginContainer.new()
	margin.name = "CardMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", CONTENT_INSET)
	margin.add_theme_constant_override("margin_right", CONTENT_INSET)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.name = "CardContentScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 3)
	scroll.add_child(_content)
	_concealed_spacer = Control.new()
	_concealed_spacer.name = "ConcealedProgressSpacer"
	_content.add_child(_concealed_spacer)
	name_label = Label.new()
	name_label.name = "UpgradeName"
	name_label.add_theme_font_size_override("font_size", 32)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(name_label)
	description_label = Label.new()
	description_label.name = "Description"
	description_label.add_theme_font_size_override("font_size", 16)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.add_theme_constant_override("line_spacing", -2)
	description_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(description_label)
	action_label = Label.new()
	action_label.name = "Action"
	action_label.add_theme_font_size_override("font_size", 16)
	action_label.add_theme_color_override("font_color", UiStyle.B_ACCENT)
	action_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(action_label)
	progress_bar = ProgressBar.new()
	progress_bar.name = "UnlockProgress"
	progress_bar.custom_minimum_size.y = 10
	progress_bar.show_percentage = false
	var progress_fill := StyleBoxFlat.new()
	progress_fill.bg_color = UiStyle.B_DIM
	progress_bar.add_theme_stylebox_override("fill", progress_fill)
	progress_bar.visible = false
	var progress_margin := MarginContainer.new()
	progress_margin.add_theme_constant_override("margin_left", 12)
	progress_margin.add_theme_constant_override("margin_right", 12)
	_content.add_child(progress_margin)
	progress_margin.add_child(progress_bar)
	progress_label = Label.new()
	progress_label.name = "UnlockProgressText"
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_label.add_theme_font_size_override("font_size", 16)
	progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress_label.visible = false
	_content.add_child(progress_label)
	# Qualification is always above the long description, so the lock/bar
	# stay visible without scrolling even when an upgrade has lengthy text.
	_content.move_child(description_label, _content.get_child_count() - 1)
	var lock_texture := TextureRect.new()
	lock_texture.texture = LOCK_TEXTURE
	lock_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lock_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lock_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	lock_sign = lock_texture
	lock_sign.name = "LockSign"
	lock_sign.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lock_sign.offset_left = -24
	lock_sign.offset_top = -92
	lock_sign.offset_right = 24
	lock_sign.offset_bottom = -36
	lock_sign.visible = false
	add_child(lock_sign)
	for child: Control in find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var grey_shader := Shader.new()
	grey_shader.code = "shader_type canvas_item; void fragment() { vec4 c = texture(TEXTURE, UV); float g = dot(c.rgb, vec3(0.299, 0.587, 0.114)); COLOR = vec4(vec3(g * 0.6), c.a); }"
	_grey_material = ShaderMaterial.new()
	_grey_material.shader = grey_shader
	# Text ignores input, but the nested scroll must still accept wheel/drag.
	# PASS lets clicks continue to this upgrade Button.
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_STOP
	_frame = TextureRect.new()
	_frame.name = "TierFrame"
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # pixel art: no softening
	_frame.visible = false
	add_child(_frame)

func setup(upgrade_name: String, description: String, use_token: bool, tint: Color = UiStyle.B_ACCENT) -> void:
	name_label.text = upgrade_name
	description_label.text = description
	action_label.text = ""
	tooltip_text = "%s\n%s\n%s" % [upgrade_name, description, action_label.text]
	call_deferred("_fit_content")

## #712: state is supplied by the progression provider, never inferred from
## button tint. Locked tiers expose only a grey frame, lock and cast progress.
func set_unlock_state(state: String, casts: int, threshold: int, prerequisite: String = "", source_name: String = "", objective: String = "") -> void:
	disabled = state not in ["ready", "token"]
	mouse_default_cursor_shape = Control.CURSOR_ARROW if disabled else Control.CURSOR_POINTING_HAND
	_locked = state == "locked"
	_concealed = state in ["locked", "ready", "token"]
	(lock_sign as TextureRect).texture = OPEN_LOCK_TEXTURE if state in ["ready", "token"] else LOCK_TEXTURE
	_content.add_theme_constant_override("separation", 5 if _concealed else 3)
	_unavailable = state == "unavailable"
	_content.visible = not _unavailable
	lock_sign.visible = _concealed
	name_label.visible = not _concealed
	description_label.visible = not _concealed
	action_label.visible = false
	_concealed_spacer.visible = _concealed
	_concealed_spacer.custom_minimum_size.y = CARD_HEIGHT * 0.5 - 22.0
	(get_node("CardMargin") as MarginContainer).add_theme_constant_override("margin_top", 12 if _concealed else 32)
	_refresh_frame()
	progress_bar.visible = _concealed
	progress_label.visible = progress_bar.visible
	var progress_fill := progress_bar.get_theme_stylebox("fill") as StyleBoxFlat
	progress_fill.bg_color = SATISFIED_PROGRESS if state == "ready" and casts >= threshold else UiStyle.B_DIM
	progress_bar.max_value = maxi(threshold, 1)
	progress_bar.value = mini(casts, maxi(threshold, 0))
	var count_text := "%d / %d" % [mini(casts, maxi(threshold, 0)), threshold]
	progress_label.text = objective + "\n" + count_text if not objective.is_empty() else count_text + " casts"
	match state:
		"locked": action_label.text = "Locked" if prerequisite.is_empty() else "Locked - previous tier first"
		"ready": action_label.text = ""
		"token": action_label.text = ""
		"applied": action_label.text = ""
		_: action_label.text = "No upgrade available"
	tooltip_text = "%s\n%s\n%s" % [name_label.text, description_label.text, action_label.text]
	if progress_label.visible:
		tooltip_text += "\n" + progress_label.text
	if _concealed:
		tooltip_text = progress_label.text
	if _unavailable:
		tooltip_text = ""
	call_deferred("_fit_content")

## #451: restyle the card border (Daniel: the color of the tier the card
## upgrades into, from UiStyle.RANK_COLORS). Default stays B_ACCENT.
func _restyle_border(color: Color) -> void:
	border_color = color
	UiStyle.style_button(self, color, 10)

## #700/#715: show the aspect-preserved ornate card frame in the tier colorway instead of
## the flat code-drawn border. tier indexes TIER_FRAMES / RANK_COLORS.
func set_border_tier(tier: int) -> void:
	if _frame == null:
		return
	_border_tier = clampi(tier, 0, TIER_FRAMES.size() - 1)
	_refresh_frame()

func _refresh_frame() -> void:
	if _frame == null: return
	_frame.texture = TIER_FRAMES[0 if _concealed or _unavailable else _border_tier]
	_frame.material = _grey_material if _concealed or _unavailable else null
	_frame.visible = true
	_restyle_border(UiStyle.B_DIM)
	if _unavailable:
		# Empty tiers are inert black cards, including hover/focus styles.
		for style_name in ["normal", "hover", "pressed", "disabled", "focus"]:
			var style := get_theme_stylebox(style_name).duplicate() as StyleBoxFlat
			style.bg_color = Color.BLACK
			add_theme_stylebox_override(style_name, style)

func _process(_delta: float) -> void:
	_fit_content()

func _fit_content() -> void:
	if not is_instance_valid(_content): return
	var width := maxf(size.x - 2.0 * CONTENT_INSET, 0.0)
	if not is_equal_approx(_content.custom_minimum_size.x, width):
		_content.custom_minimum_size.x = width
	# Fixed geometry; native16px copy uses the space freed by removed art.
	custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)

## Bound long upgrade hover text rather than allowing Godot's default
## unwrapped tooltip to spill across the other cards and off the panel.
func _make_custom_tooltip(for_text: String) -> Object:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel())
	var label := Label.new()
	label.custom_minimum_size.x = 288
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16)
	label.text = for_text
	panel.add_child(label)
	return panel
