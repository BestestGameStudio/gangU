class_name BestiaryPanel
extends CanvasLayer
## (#325) Read-only hub bestiary panel. Hidden by default; the hub
## BestiaryStation opens it on walk-up and closes it on walk-away (the
## SpellDirectoryPanel idiom). Lists every enemy type in Bestiary's
## cross-run record: encountered types show their idle sprite, name and
## encounter count; catalogued types not met yet show a dark silhouette and
## "???". Code-built UI in the shared UiStyle look; joins "modal_ui" while
## visible so the caster skips casting on panel clicks.

const ROW_PAD := 6.0
const ICON_SIZE := 40.0
const BOSS_COLOR := Color(0.88, 0.32, 0.28, 1.0)
const UNSEEN_MODULATE := Color(0.0, 0.0, 0.0, 0.85)

var _count_label: Label
var _rows: VBoxContainer
var _revision := -1

func _ready() -> void:
	add_to_group("bestiary_panel")
	layer = 3
	_build_skeleton()
	visible = false

func open() -> void:
	_render()
	visible = true
	add_to_group("modal_ui")

func close() -> void:
	visible = false
	remove_from_group("modal_ui")

## Re-render if an encounter was recorded while the panel is open.
func _process(_delta: float) -> void:
	if visible and _revision != Bestiary.revision:
		_render()

func _build_skeleton() -> void:
	var backdrop := Panel.new()
	backdrop.name = "Backdrop"
	backdrop.add_theme_stylebox_override("panel", UiStyle.panel())
	backdrop.anchor_left = 0.5
	backdrop.anchor_top = 0.5
	backdrop.anchor_right = 0.5
	backdrop.anchor_bottom = 0.5
	backdrop.offset_left = -220.0
	backdrop.offset_top = -200.0
	backdrop.offset_right = 220.0
	backdrop.offset_bottom = 200.0
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	backdrop.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	var title := Label.new()
	title.text = "BESTIARY"
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	_count_label = Label.new()
	_count_label.name = "CountLabel"
	_count_label.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_count_label)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", 6)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	var hint := Label.new()
	hint.text = "Walk away to close"
	hint.add_theme_color_override("font_color", UiStyle.TEXT_DIM * Color(1, 1, 1, 0.6))
	hint.add_theme_font_size_override("font_size", 11)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

func _render() -> void:
	_revision = Bestiary.revision
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var ids := Bestiary.listed_ids()
	_count_label.text = "%d / %d enemies encountered" % [Bestiary.seen_count(), ids.size()]
	for id in ids:
		_rows.add_child(_make_row(id))

func _make_row(id: StringName) -> Control:
	var seen := Bestiary.has_seen(id)
	var entry := Bestiary.catalog_entry(id)
	var row := PanelContainer.new()
	row.name = "Row_%s" % id
	row.set_meta("bestiary_id", id)
	row.add_theme_stylebox_override("panel", UiStyle.row(UiStyle.B_ASSIGNED if seen else UiStyle.B_DIM, ROW_PAD))
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)
	var icon_box := Panel.new()
	icon_box.name = "IconBox"
	icon_box.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon_box.add_theme_stylebox_override("panel", UiStyle.icon_placeholder())
	hbox.add_child(icon_box)
	var tex := _icon_texture(entry)
	if tex != null:
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.texture = tex
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		if not seen:
			icon.modulate = UNSEEN_MODULATE
		icon_box.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 0)
	hbox.add_child(text)
	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = Bestiary.display_name(id) if seen else "???"
	if not seen:
		name_label.add_theme_color_override("font_color", UiStyle.TEXT_DIM * Color(1, 1, 1, 0.7))
	text.add_child(name_label)
	var detail := Label.new()
	detail.name = "DetailLabel"
	detail.add_theme_font_size_override("font_size", 11)
	detail.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	var count := Bestiary.encounter_count(id)
	detail.text = ("Encountered %d time%s" % [count, "" if count == 1 else "s"]) if seen else "Not encountered yet"
	text.add_child(detail)
	if seen and entry.get("boss", false):
		var tag := Label.new()
		tag.name = "BossTag"
		tag.text = "BOSS"
		tag.add_theme_font_size_override("font_size", 12)
		tag.add_theme_color_override("font_color", BOSS_COLOR)
		hbox.add_child(tag)
	return row

## First idle frame from the catalog's SpriteFrames (null when unknown).
func _icon_texture(entry: Dictionary) -> Texture2D:
	var path: String = entry.get("frames", "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var frames := load(path) as SpriteFrames
	if frames == null:
		return null
	var anim: StringName = &"idle" if frames.has_animation(&"idle") else StringName(frames.get_animation_names()[0])
	if frames.get_frame_count(anim) == 0:
		return null
	return frames.get_frame_texture(anim, 0)
