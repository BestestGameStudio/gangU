class_name SpellDirectoryPanel
extends CanvasLayer
## (#218) Read-only spell directory panel. Hidden by default; the hub
## directory location opens it on walk-up and closes it on walk-away (the
## ShopPanel idiom). Lists EVERY spell in the caster's current-run unlock
## set (SpellCaster.get_unlocked(), #60) as icon + name rows, refreshed
## live through the spell_unlocked signal. READ-ONLY by design: no buy,
## no equip changes, no unlock grants - it only displays what the player
## already unlocked this run.
##
## UI is code-built; the look comes from UiStyle. While visible the panel
## joins "modal_ui" so the caster skips casting on panel clicks (the
## EquipPanel/ShopPanel idiom). Found via the "spell_directory_panel"
## group.

const ROW_PAD := 6.0

var _caster: SpellCaster
var _count_label: Label
var _rows: VBoxContainer

func _ready() -> void:
	add_to_group("spell_directory_panel")
	layer = 3
	_build_skeleton()
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		_caster = player.get_node_or_null("SpellCaster") as SpellCaster
	if _caster != null and not _caster.spell_unlocked.is_connected(_on_spell_unlocked):
		_caster.spell_unlocked.connect(_on_spell_unlocked)
	visible = false

func open(for_caster: SpellCaster = null) -> void:
	if for_caster != null and for_caster != _caster:
		if _caster != null and _caster.spell_unlocked.is_connected(_on_spell_unlocked):
			_caster.spell_unlocked.disconnect(_on_spell_unlocked)
		_caster = for_caster
		if not _caster.spell_unlocked.is_connected(_on_spell_unlocked):
			_caster.spell_unlocked.connect(_on_spell_unlocked)
	_render()
	visible = true
	add_to_group("modal_ui") # caster cast-guard hook (EquipPanel idiom)

func close() -> void:
	visible = false
	remove_from_group("modal_ui")

func _build_skeleton() -> void:
	var backdrop := Panel.new()
	backdrop.name = "Backdrop"
	backdrop.add_theme_stylebox_override("panel", UiStyle.panel())
	backdrop.anchor_left = 0.5
	backdrop.anchor_top = 0.5
	backdrop.anchor_right = 0.5
	backdrop.anchor_bottom = 0.5
	backdrop.offset_left = -200.0
	backdrop.offset_top = -180.0
	backdrop.offset_right = 200.0
	backdrop.offset_bottom = 180.0
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
	title.text = "SPELL DIRECTORY"
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	_count_label = Label.new()
	_count_label.name = "CountLabel"
	_count_label.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_count_label)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", 6)
	vbox.add_child(_rows)
	var hint := Label.new()
	hint.text = "Walk away to close"
	hint.add_theme_color_override("font_color", UiStyle.TEXT_DIM * Color(1, 1, 1, 0.6))
	hint.add_theme_font_size_override("font_size", 11)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

## One icon + name row per unlocked spell, in unlock order. Empty runs get
## a dim placeholder line instead of a blank panel.
func _render() -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var unlocked: Array[Spell] = []
	if _caster != null:
		unlocked = _caster.get_unlocked()
	_count_label.text = "%d spell(s) unlocked this run" % unlocked.size()
	if unlocked.is_empty():
		var empty := Label.new()
		empty.name = "EmptyLabel"
		empty.text = "No spells unlocked yet"
		empty.add_theme_color_override("font_color", UiStyle.TEXT_DIM * Color(1, 1, 1, 0.7))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rows.add_child(empty)
		return
	for spell in unlocked:
		_rows.add_child(_make_row(spell))

func _make_row(spell: Spell) -> Control:
	var row := PanelContainer.new()
	row.name = "Row"
	row.add_theme_stylebox_override("panel", UiStyle.row(UiStyle.B_DIM, ROW_PAD))
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)
	var icon := SpellIcon.new()
	icon.show_spell(spell)
	hbox.add_child(icon)
	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = spell.spell_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_label)
	return row

func _on_spell_unlocked(_spell: Spell) -> void:
	if visible:
		_render()
