class_name UpgradeCard
extends Button
## #402 presentation only. The panel owns eligibility, path IDs and actions.
## Splash is deliberately a code-drawn placeholder, never claimed final art.
const CARD_WIDTH := 176.0
const CARD_HEIGHT := CARD_WIDTH * 64.0 / 48.0
var name_label: Label
var description_label: Label
var action_label: Label
var progress_bar: ProgressBar
var progress_label: Label
var lock_sign: Control
var splash: Control
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
var _grey_material: ShaderMaterial

class PlaceholderSplash extends Control:
	var tint := Color(0.95, 0.75, 0.25)
	var plain := false
	func _draw() -> void:
		if plain: return
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UiStyle.row(UiStyle.B_DIM, 0), r)
		var c := size * 0.5
		var points := PackedVector2Array([c + Vector2(0, -19), c + Vector2(16, 0), c + Vector2(0, 19), c + Vector2(-16, 0)])
		draw_colored_polygon(points, Color(tint, 0.24))
		draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), tint, 2.0, true)

## Vector padlock: no font-dependent emoji or missing-glyph square.
class LockSign extends Control:
	func _draw() -> void:
		var c := size * 0.5
		draw_style_box(UiStyle.row(Color(0.65, 0.67, 0.72), 4), Rect2(c + Vector2(-11, -2), Vector2(22, 18)))
		draw_arc(c + Vector2(0, -2), 8, PI, TAU, 16, Color(0.8, 0.82, 0.86), 3, true)
		draw_circle(c + Vector2(0, 5), 2, Color(0.85, 0.87, 0.9))

func _init() -> void:
	custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UiStyle.style_button(self, UiStyle.B_ACCENT, 10)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.name = "CardContentScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 5)
	scroll.add_child(_content)
	splash = PlaceholderSplash.new()
	splash.name = "PlaceholderSplash"
	splash.custom_minimum_size = Vector2(0, 32)
	_content.add_child(splash)
	var placeholder_label := Label.new()
	placeholder_label.name = "PlaceholderLabel"
	placeholder_label.text = "PLACEHOLDER ART"
	placeholder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder_label.add_theme_font_size_override("font_size", 10)
	placeholder_label.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	splash.add_child(placeholder_label)
	placeholder_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	placeholder_label.offset_top = -18
	name_label = Label.new()
	name_label.name = "UpgradeName"
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(name_label)
	description_label = Label.new()
	description_label.name = "Description"
	description_label.add_theme_font_size_override("font_size", 13)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(description_label)
	action_label = Label.new()
	action_label.name = "Action"
	action_label.add_theme_font_size_override("font_size", 12)
	action_label.add_theme_color_override("font_color", UiStyle.B_ACCENT)
	action_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(action_label)
	progress_bar = ProgressBar.new()
	progress_bar.name = "UnlockProgress"
	progress_bar.custom_minimum_size.y = 10
	progress_bar.show_percentage = false
	progress_bar.visible = false
	_content.add_child(progress_bar)
	progress_label = Label.new()
	progress_label.name = "UnlockProgressText"
	progress_label.add_theme_font_size_override("font_size", 12)
	progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress_label.visible = false
	_content.add_child(progress_label)
	# Qualification is always above the long description, so the lock/bar
	# stay visible without scrolling even when an upgrade has lengthy text.
	_content.move_child(description_label, _content.get_child_count() - 1)
	lock_sign = LockSign.new()
	lock_sign.name = "LockSign"
	lock_sign.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lock_sign.visible = false
	splash.add_child(lock_sign)
	for child: Control in find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var grey_shader := Shader.new()
	grey_shader.code = "shader_type canvas_item; void fragment() { vec4 c = texture(TEXTURE, UV); float g = dot(c.rgb, vec3(0.299, 0.587, 0.114)); COLOR = vec4(vec3(g * 0.6), c.a); }"
	_grey_material = ShaderMaterial.new()
	_grey_material.shader = grey_shader
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
	action_label.text = "Choose - use upgrade token" if use_token else "Choose upgrade"
	(splash as PlaceholderSplash).tint = tint
	splash.queue_redraw()
	tooltip_text = "%s\n%s\n%s" % [upgrade_name, description, action_label.text]
	call_deferred("_fit_content")

## #712: state is supplied by the progression provider, never inferred from
## button tint. Locked tiers expose only a grey frame, lock and cast progress.
func set_unlock_state(state: String, casts: int, threshold: int, prerequisite: String = "", source_name: String = "") -> void:
	disabled = state not in ["ready", "token"]
	mouse_default_cursor_shape = Control.CURSOR_ARROW if disabled else Control.CURSOR_POINTING_HAND
	_locked = state == "locked"
	lock_sign.visible = _locked
	name_label.visible = not _locked
	description_label.visible = not _locked
	action_label.visible = not _locked
	(splash as PlaceholderSplash).plain = _locked
	splash.custom_minimum_size.y = 100.0 if _locked else 32.0
	splash.queue_redraw()
	_refresh_frame()
	splash.get_node("PlaceholderLabel").visible = not lock_sign.visible
	progress_bar.visible = state in ["locked", "ready", "token"]
	progress_label.visible = progress_bar.visible
	progress_bar.max_value = maxi(threshold, 1)
	progress_bar.value = mini(casts, maxi(threshold, 0))
	progress_label.text = "%d / %d casts" % [mini(casts, maxi(threshold, 0)), threshold]
	if not _locked and not source_name.is_empty():
		progress_label.text += " - " + source_name
	match state:
		"locked": action_label.text = "Locked" if prerequisite.is_empty() else "Locked - previous tier first"
		"ready": action_label.text = "Choose upgrade"
		"token": action_label.text = "Choose - use upgrade token"
		"applied": action_label.text = "Applied"
		_: action_label.text = "No upgrade available"
	tooltip_text = "%s\n%s\n%s" % [name_label.text, description_label.text, action_label.text]
	if progress_label.visible:
		tooltip_text += "\n" + progress_label.text
	if _locked:
		tooltip_text = progress_label.text
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
	_frame.texture = TIER_FRAMES[0 if _locked else _border_tier]
	_frame.material = _grey_material if _locked else null
	_frame.visible = true
	_restyle_border(UiStyle.B_DIM)

func _process(_delta: float) -> void:
	_fit_content()

func _fit_content() -> void:
	if not is_instance_valid(_content): return
	var width := maxf(size.x - 40.0, 0.0)
	if not is_equal_approx(_content.custom_minimum_size.x, width):
		_content.custom_minimum_size.x = width
	# Frame art is 48x64. Card height never follows the description length;
	# long unlocked details scroll inside the frame instead of distorting it.
	custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
