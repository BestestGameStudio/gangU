class_name MapPanel
extends CanvasLayer
## (#347) The map, toggled with M (Esc also closes). Shows a WorldMap's
## explored terrain for the current area, centered on the player when it
## opens, and lets the player draw on it and place their own markers.
##
## Minimal UX (#347 asks to keep it minimal):
##   - Tools: Draw (freehand ink), Marker (pick one of four symbols, click to
##     place), Erase (click/drag removes nearby marks). RMB erases with any
##     tool. Limits live on WorldMap (provisional caps).
##   - Does NOT pause (EquipPanel/Tab idiom). While open it joins "modal_ui"
##     so map clicks never cast spells.
## Everything shown comes from WorldMap; this panel never looks at gates,
## portals or enemies (details are player-marked only, #347 settled).

const ACTION := &"world_map"
const MAP_SIZE := Vector2(880.0, 470.0)

@export var world_map_path: NodePath

var world_map: WorldMap = null
var canvas: MapCanvas
var _tool_buttons: Array[Button] = []
var _symbol_buttons: Array[Button] = []
var _status: Label

func _ready() -> void:
	layer = 9
	visible = false
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_M
		InputMap.action_add_event(ACTION, ev)
	if world_map_path != NodePath(""):
		world_map = get_node_or_null(world_map_path) as WorldMap
	if world_map == null:
		push_warning("MapPanel: world_map_path unset or unresolved; panel inert.")
	_build_ui()
	if world_map != null:
		world_map.changed.connect(_on_changed)

func _input(event: InputEvent) -> void:
	if world_map == null:
		return
	if event.is_action_pressed(ACTION) and not event.is_echo():
		get_viewport().set_input_as_handled()
		if visible:
			close()
		else:
			open()
	elif visible and event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()

func open() -> void:
	if world_map == null:
		return
	if is_instance_valid(world_map.player):
		canvas.center = world_map.player.global_position
	visible = true
	add_to_group("modal_ui")
	_refresh()

func close() -> void:
	visible = false
	remove_from_group("modal_ui")

func set_tool(t: MapCanvas.Tool) -> void:
	canvas.tool = t
	_refresh()

func set_symbol(sym: WorldMap.Symbol) -> void:
	canvas.symbol = sym
	canvas.tool = MapCanvas.Tool.MARKER
	_refresh()

func _process(_delta: float) -> void:
	if visible:
		canvas.queue_redraw() # player dot moves while the map is open

func _on_changed(_id: StringName) -> void:
	if visible:
		_refresh()

func _refresh() -> void:
	for i in _tool_buttons.size():
		UiStyle.style_button(_tool_buttons[i], UiStyle.B_ACCENT if canvas.tool == i else UiStyle.B_DIM, 6.0, -1.0, canvas.tool == i)
	for i in _symbol_buttons.size():
		var on := canvas.tool == MapCanvas.Tool.MARKER and canvas.symbol == i
		UiStyle.style_button(_symbol_buttons[i], UiStyle.B_ACCENT if on else UiStyle.B_DIM, 4.0, -1.0, on)
	var id := world_map.area_id if world_map != null else &""
	if world_map != null:
		_status.text = "%s   markers %d/%d   drawings %d/%d" % [
			String(id), world_map.markers(id).size(), WorldMap.MAX_MARKERS,
			world_map.strokes(id).size(), WorldMap.MAX_STROKES]
	canvas.queue_redraw()

func _build_ui() -> void:
	var backdrop := Panel.new()
	backdrop.name = "Backdrop"
	backdrop.add_theme_stylebox_override("panel", UiStyle.panel())
	backdrop.set_anchors_preset(Control.PRESET_CENTER)
	var half := (MAP_SIZE + Vector2(28.0, 84.0)) * 0.5
	backdrop.offset_left = -half.x
	backdrop.offset_right = half.x
	backdrop.offset_top = -half.y
	backdrop.offset_bottom = half.y
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	backdrop.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	vbox.add_child(top)
	var title := Label.new()
	title.text = "MAP"
	title.add_theme_font_size_override("font_size", 20)
	top.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(16, 0)
	top.add_child(spacer)
	for i in 3:
		var b := Button.new()
		b.name = "Tool%d" % i
		b.text = ["Draw", "Marker", "Erase"][i]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(set_tool.bind(i))
		top.add_child(b)
		_tool_buttons.append(b)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(12, 0)
	top.add_child(gap)
	for i in WorldMap.SYMBOL_NAMES.size():
		var b := Button.new()
		b.name = "Symbol%d" % i
		b.custom_minimum_size = Vector2(34, 30)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "Marker " + WorldMap.SYMBOL_NAMES[i]
		b.pressed.connect(set_symbol.bind(i))
		var icon := _SymbolIcon.new()
		icon.sym = i
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(icon)
		top.add_child(b)
		_symbol_buttons.append(b)

	canvas = MapCanvas.new()
	canvas.name = "Canvas"
	canvas.custom_minimum_size = MAP_SIZE
	canvas.world_map = world_map
	vbox.add_child(canvas)

	var bottom := HBoxContainer.new()
	vbox.add_child(bottom)
	_status = Label.new()
	_status.name = "Status"
	_status.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	_status.add_theme_font_size_override("font_size", 12)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_status)
	var hint := Label.new()
	hint.text = "LMB: use tool   RMB: erase   M / Esc: close"
	hint.add_theme_color_override("font_color", UiStyle.TEXT_DIM * Color(1, 1, 1, 0.6))
	hint.add_theme_font_size_override("font_size", 12)
	bottom.add_child(hint)

class _SymbolIcon extends Control:
	var sym := 0
	func _draw() -> void:
		MapCanvas.draw_symbol(self, size * 0.5, sym, 7.0, MapCanvas.MARKER_COLOR)
