class_name StatGrid
extends VBoxContainer
## #376 TFT-style stat grid for the Tab menu (Daniel, 2026-11-09: "player
## stats should show display in a grid and only show the icon and value.
## Hovering over the icon can show details"). A header plus a grid of cells;
## each cell shows ONLY a StatIcon and the value. The stat's name and its
## details (formula, caps, modifier sources) live in the cell's hover
## tooltip, styled like the panel.
##
## Feed it with set_entries(title, entries); entries come from StatSheet:
##   {id: StringName, value: String, title: String, details: String}
## Cells are reused when the id list is unchanged, so live updates while the
## Tab menu is open never tear down a cell the mouse is hovering.

## #416: the grid sits above the upgrade cards in a column sized for three
## cards, so it uses that width (5 cells, with slack for long values).
const COLUMNS := 5
const CELL_WIDTH := 112.0
const ICON_SIZE := 26.0
const VALUE_FONT := 20
const TITLE_FONT := 22

var _description: Label
var _header: Label
var _grid: GridContainer
var _ids: Array[StringName] = []

## One grid cell: icon + value. Hovering shows the stat's details.
class StatCell extends PanelContainer:
	var stat_id: StringName
	var icon: StatIcon
	var value_label: Label
	var title := ""
	var details := ""
	## The hover card Godot is currently showing for this cell (null when
	## none). Godot builds the card once per hover and never asks again, so
	## set_entry rewrites it in place: an open card never shows stale values.
	var _tip: Control = null

	func _init(p_id: StringName) -> void:
		stat_id = p_id
		name = "Stat_%s" % p_id
		custom_minimum_size = Vector2(CELL_WIDTH, 0)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_HELP
		add_theme_stylebox_override("panel", UiStyle.row(UiStyle.B_DIM, 4.0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		icon = StatIcon.new(p_id, ICON_SIZE)
		row.add_child(icon)
		value_label = Label.new()
		value_label.add_theme_font_size_override("font_size", VALUE_FONT)
		value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(value_label)
		mouse_entered.connect(func() -> void: add_theme_stylebox_override("panel", UiStyle.row(UiStyle.B_SELECTED, 4.0, -1.0, true)))
		mouse_exited.connect(func() -> void: add_theme_stylebox_override("panel", UiStyle.row(UiStyle.B_DIM, 4.0)))

	func set_entry(e: Dictionary) -> void:
		var v: String = e.get("value", "")
		var t: String = e.get("title", "")
		var d: String = e.get("details", "")
		value_label.text = v
		title = t
		details = d
		# Plain tooltip_text both enables Godot's hover tooltip and keeps the
		# details readable by accessibility/tests; the look comes from below.
		tooltip_text = title + "\n" + details
		var tip := open_tooltip()
		if tip != null:
			StatGrid.fill_tooltip(tip, title, value_label.text, details)

	func _make_custom_tooltip(_for_text: String) -> Object:
		_tip = StatGrid.make_tooltip(title, value_label.text, details)
		return _tip

	## The card on screen right now, or null once Godot has closed and freed it.
	func open_tooltip() -> Control:
		if _tip != null and not is_instance_valid(_tip):
			_tip = null
		if _tip != null and _tip.is_queued_for_deletion():
			return null
		return _tip

## The hover card: stat name + value on top, details below. Public so the
## harness (and screenshots) can build the exact card the tooltip shows.
static func make_tooltip(p_title: String, p_value: String, p_details: String) -> Control:
	var panel := PanelContainer.new()
	panel.name = "StatTooltip"
	panel.add_theme_stylebox_override("panel", UiStyle.panel())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var head := Label.new()
	head.name = "Title"
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", UiStyle.B_ACCENT)
	box.add_child(head)
	var body := Label.new()
	body.name = "Details"
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	box.add_child(body)
	fill_tooltip(panel, p_title, p_value, p_details)
	return panel

## Writes the texts into a card from make_tooltip (new or already open). If
## the text grows, the tooltip popup is resized to fit it.
static func fill_tooltip(panel: Control, p_title: String, p_value: String, p_details: String) -> void:
	(panel.find_child("Title", true, false) as Label).text = "%s  %s" % [p_title, p_value]
	(panel.find_child("Details", true, false) as Label).text = p_details
	var popup := panel.get_parent() as Window
	if popup != null:
		popup.reset_size()

func _init() -> void:
	name = "StatsBox"
	add_theme_constant_override("separation", 6)
	_header = Label.new()
	_header.name = "Header"
	_header.add_theme_font_size_override("font_size", TITLE_FONT)
	add_child(_header)
	_description = Label.new()
	_description.name = "Description"
	_description.custom_minimum_size.x = 320.0
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.add_theme_font_size_override("font_size", 16)
	_description.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	_description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_description.hide()
	add_child(_description)
	_grid = GridContainer.new()
	_grid.name = "Grid"
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	add_child(_grid)

func set_entries(p_title: String, entries: Array) -> void:
	_header.text = p_title
	var ids: Array[StringName] = []
	for e: Dictionary in entries:
		ids.append(e["id"])
	if ids != _ids:
		for c in _grid.get_children():
			_grid.remove_child(c)
			c.queue_free()
		for id in ids:
			_grid.add_child(StatCell.new(id))
		_ids = ids
	for i in entries.size():
		var entry: Dictionary = entries[i]
		(_grid.get_child(i) as StatCell).set_entry(entry)

## Description belongs to the selected spell, never a stat cell or tooltip.
## Calling this repeatedly leaves live/hovered stat cells untouched.
func set_description(text: String) -> void:
	_description.text = text
	_description.visible = not text.is_empty()

func description() -> String:
	return _description.text

func title() -> String:
	return _header.text

func cell(id: StringName) -> StatCell:
	return _grid.get_node_or_null("Stat_%s" % id) as StatCell

func cell_ids() -> Array[StringName]:
	return _ids.duplicate()

func value_of(id: StringName) -> String:
	var c := cell(id)
	return c.value_label.text if c != null else ""

func details_of(id: StringName) -> String:
	var c := cell(id)
	return c.details if c != null else ""
