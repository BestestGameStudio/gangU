class_name UpgradeCard
extends Button
## #402 presentation only. The panel owns eligibility, path IDs and actions.
## Splash is deliberately a code-drawn placeholder, never claimed final art.
const CARD_WIDTH := 224.0
var name_label: Label
var description_label: Label
var action_label: Label
var splash: Control
var _content: VBoxContainer

class PlaceholderSplash extends Control:
	var tint := Color(0.95, 0.75, 0.25)
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UiStyle.row(UiStyle.B_DIM, 0), r)
		var c := size * 0.5
		var points := PackedVector2Array([c + Vector2(0, -19), c + Vector2(16, 0), c + Vector2(0, 19), c + Vector2(-16, 0)])
		draw_colored_polygon(points, Color(tint, 0.24))
		draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), tint, 2.0, true)

func _init() -> void:
	custom_minimum_size = Vector2(CARD_WIDTH, 200)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UiStyle.style_button(self, UiStyle.B_ACCENT, 10)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 5)
	margin.add_child(_content)
	splash = PlaceholderSplash.new()
	splash.name = "PlaceholderSplash"
	splash.custom_minimum_size = Vector2(0, 55)
	_content.add_child(splash)
	var placeholder_label := Label.new()
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
	for child in find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(upgrade_name: String, description: String, use_token: bool, tint: Color = UiStyle.B_ACCENT) -> void:
	name_label.text = upgrade_name
	description_label.text = description
	action_label.text = "Choose - use upgrade token" if use_token else "Choose upgrade"
	(splash as PlaceholderSplash).tint = tint
	splash.queue_redraw()
	tooltip_text = "%s\n%s\n%s" % [upgrade_name, description, action_label.text]
	call_deferred("_fit_content")

func _process(_delta: float) -> void:
	_fit_content()

func _fit_content() -> void:
	if not is_instance_valid(_content): return
	var width := maxf(size.x - 24.0, 0.0)
	if not is_equal_approx(_content.custom_minimum_size.x, width):
		_content.custom_minimum_size.x = width
	# Text wrapping can change minimum height without resizing the Button.
	# Propagate it to the HBox so ScrollContainer has real scrollable content.
	var text_height := 0.0
	for label: Label in [name_label, description_label, action_label]:
		var font := label.get_theme_font("font")
		text_height += font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, width, label.get_theme_font_size("font_size")).y
	var height := maxf(200.0, maxf(text_height + 55.0 + 15.0, _content.get_combined_minimum_size().y) + 24.0)
	if not is_equal_approx(custom_minimum_size.y, height):
		custom_minimum_size.y = height
