class_name MapPanel
extends ModalPanel
## (#347) The map, toggled with M (Esc also closes). Shows a WorldMap's
## explored terrain for the current area, centered on the player when it
## opens, and lets the player draw on it and place their own markers.
##
## Minimal UX (#347 asks to keep it minimal):
##   - Tools: Draw (freehand ink), Marker (pick one of four symbols, click to
##     place), Erase (click/drag removes nearby marks). RMB erases with any
##     tool. Limits live on WorldMap (provisional caps).
##   - Does NOT pause (EquipPanel/Tab idiom). A ModalPanel, so map clicks
##     never cast spells.
## Everything shown comes from WorldMap; this panel never looks at gates,
## portals or enemies (details are player-marked only, #347 settled).
##
## (#366) Cleared dungeons are marked on the map (WorldMap.cleared_sites).
##   - "World" toggles the view between the current area and the area that
##     holds the marked dungeons (the overworld), so you can pick a dungeon
##     from anywhere.
##   - Click a marked dungeon to select it, then press Travel. The panel only
##     asks: it emits `travel_requested`, and main.gd rechecks eligibility
##     when the trip is committed. `travel_rule` (func(dungeon_id) -> bool,
##     supplied by main.gd = the #349 Hub-spoke policy) greys out the button
##     and is asked again on the click itself.

signal travel_requested(dungeon_id: StringName)

const ACTION := &"world_map"
const MAP_SIZE := Vector2(880.0, 470.0)
## MapCanvas' default zoom; #366 zooms out from it to fit marked dungeons.
const DEFAULT_SCALE := 0.375
## Screen-px border kept around marked dungeons (fits the name label).
const SITE_FIT_MARGIN_PX := 40.0

@export var world_map_path: NodePath

var world_map: WorldMap = null
var canvas: MapCanvas
## (#366) func(dungeon_id: StringName) -> bool. Unset = travel never offered.
var travel_rule: Callable = Callable()
var _tool_buttons: Array[Button] = []
var _symbol_buttons: Array[Button] = []
var _status: Label
var _last_area: StringName = &""
var _world_button: Button
var _selection: Label
var _travel_button: Button
## (#435) Where the player was last frame; a move snaps the view back to them.
var _last_player_pos := Vector2.INF

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
	_set_view(&"")
	canvas.cancel_interaction() # never resume a drag from a previous opening
	_set_shown(true)
	_refresh()

func close() -> void:
	# The hidden canvas never sees a release that happens while closed, so
	# drop the drag here (PR #355 review: ghost stroke on reopen).
	canvas.cancel_interaction()
	_set_shown(false)

func set_tool(t: MapCanvas.Tool) -> void:
	canvas.tool = t
	_refresh()

func set_symbol(sym: WorldMap.Symbol) -> void:
	canvas.symbol = sym
	canvas.tool = MapCanvas.Tool.MARKER
	_refresh()

## (#366) The area that holds the marked dungeons, if it is not the one the
## player is in; &"" when there is nowhere else to look.
func world_view_id() -> StringName:
	if world_map == null:
		return &""
	for id in world_map.areas_with_cleared_sites():
		if id != world_map.area_id:
			return id
	return &""

## (#366) Show area `id` (&"" = the current area) and drop any selection.
func _set_view(id: StringName) -> void:
	canvas.cancel_interaction()
	canvas.view_id = id
	canvas.selected_site = &""
	var here := id == &"" and is_instance_valid(world_map.player)
	if here:
		canvas.center = world_map.player.global_position
	else:
		canvas.center = world_map.view_center(canvas.view())
	_fit_sites(here)
	# (#435) Panning only where the area has overworld bounds, and only in the
	# player's own area view; the (re)centered view is kept inside them.
	canvas.pan_bounds = world_map.pan_bounds() if here else Rect2()
	canvas.pan_outline = world_map.pan_outline() if here else PackedVector2Array()
	canvas.center = canvas.clamp_center(canvas.center)
	_last_player_pos = world_map.player.global_position if here else Vector2.INF
	_refresh()

## (#366) The map has no panning, so zoom out (never in past DEFAULT_SCALE)
## until every marked dungeon, plus the player when shown, is on screen.
func _fit_sites(include_player: bool) -> void:
	canvas.map_scale = DEFAULT_SCALE
	var s := world_map.cleared_sites(canvas.view())
	if s.is_empty():
		return
	var box := Rect2(s.values()[0], Vector2.ZERO)
	for d: StringName in s:
		box = box.expand(s[d])
	if include_player:
		box = box.expand(world_map.player.global_position)
	var view_size := canvas.size if canvas.size != Vector2.ZERO else MAP_SIZE
	var avail := view_size - Vector2(2.0, 2.0) * SITE_FIT_MARGIN_PX
	var need := box.size
	var fit := DEFAULT_SCALE
	if need.x > 0.0:
		fit = minf(fit, avail.x / need.x)
	if need.y > 0.0:
		fit = minf(fit, avail.y / need.y)
	# Only re-center when the default view would cut something off.
	var half := view_size * 0.5 / DEFAULT_SCALE - Vector2.ONE * SITE_FIT_MARGIN_PX / DEFAULT_SCALE
	var view_rect := Rect2(canvas.center - half, half * 2.0)
	if view_rect.encloses(box):
		return
	canvas.map_scale = fit
	canvas.center = box.get_center()

func toggle_world_view() -> void:
	if canvas.view_id != &"":
		_set_view(&"")
	else:
		var w := world_view_id()
		if w != &"":
			_set_view(w)

func select_dungeon(dungeon_id: StringName) -> void:
	canvas.select_site(dungeon_id)

func can_travel_selected() -> bool:
	return canvas.selected_site != &"" and travel_rule.is_valid() and bool(travel_rule.call(canvas.selected_site))

## Travel button. Closes the map, then asks main.gd to make the trip.
func request_travel() -> void:
	var id := canvas.selected_site
	if not can_travel_selected():
		return
	close()
	travel_requested.emit(id)

func _on_site_selected(_id: StringName) -> void:
	_refresh()

func _process(_delta: float) -> void:
	if visible:
		# (#435) A player move snaps a panned view back onto the player.
		if canvas.pan_bounds.size.x > 0.0 and is_instance_valid(world_map.player):
			var pp := world_map.player.global_position
			if not _last_player_pos.is_equal_approx(pp):
				_last_player_pos = pp
				if canvas.is_panning():
					canvas.cancel_interaction()
				canvas.center = canvas.clamp_center(pp)
		canvas.queue_redraw() # player dot moves while the map is open

func _on_changed(_id: StringName) -> void:
	# Area swapped (possibly mid-drag): the drag belonged to the old area.
	if world_map.area_id != _last_area:
		_last_area = world_map.area_id
		canvas.cancel_interaction()
		if visible:
			_set_view(&"") # #366: a travel/area swap resets view and selection
	if visible:
		_refresh()

func _refresh() -> void:
	for i in _tool_buttons.size():
		UiStyle.style_button(_tool_buttons[i], UiStyle.B_ACCENT if canvas.tool == i else UiStyle.B_DIM, 6.0, -1.0, canvas.tool == i)
	for i in _symbol_buttons.size():
		var on := canvas.tool == MapCanvas.Tool.MARKER and canvas.symbol == i
		UiStyle.style_button(_symbol_buttons[i], UiStyle.B_ACCENT if on else UiStyle.B_DIM, 4.0, -1.0, on)
	var id := canvas.view()
	if world_map != null:
		_status.text = "%s   markers %d/%d   drawings %d/%d" % [
			String(id), world_map.markers(id).size(), WorldMap.MAX_MARKERS,
			world_map.strokes(id).size(), WorldMap.MAX_STROKES]
	# #366: world-view toggle + selection / travel row.
	var away := canvas.view_id != &""
	_world_button.visible = away or world_view_id() != &""
	_world_button.text = "Here" if away else "World"
	UiStyle.style_button(_world_button, UiStyle.B_ACCENT if away else UiStyle.B_DIM, 6.0, -1.0, away)
	var sel := canvas.selected_site
	if sel == &"":
		var n := world_map.cleared_sites(id).size() if world_map != null else 0
		_selection.text = "Click a cleared dungeon (gold ✓) to travel" if n > 0 else ""
	else:
		var label := FastTravelRoutes.label_for(sel)
		_selection.text = ("Cleared: %s" % label) if can_travel_selected() else ("Cleared: %s (map travel leaves from the Hub)" % label)
	_travel_button.visible = sel != &""
	_travel_button.disabled = not can_travel_selected()
	UiStyle.style_button(_travel_button, UiStyle.B_ACCENT if not _travel_button.disabled else UiStyle.B_DIM, 6.0)
	canvas.queue_redraw()

func _build_ui() -> void:
	var backdrop := Panel.new()
	backdrop.name = "Backdrop"
	backdrop.add_theme_stylebox_override("panel", UiStyle.panel())
	backdrop.set_anchors_preset(Control.PRESET_CENTER)
	var half := (MAP_SIZE + Vector2(28.0, 124.0)) * 0.5
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
	var gap2 := Control.new()
	gap2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap2)
	_world_button = Button.new()
	_world_button.name = "WorldView"
	_world_button.text = "World"
	_world_button.tooltip_text = "Toggle between this area and the area with your cleared dungeons"
	_world_button.focus_mode = Control.FOCUS_NONE
	_world_button.pressed.connect(toggle_world_view)
	top.add_child(_world_button)

	canvas = MapCanvas.new()
	canvas.name = "Canvas"
	canvas.custom_minimum_size = MAP_SIZE
	canvas.world_map = world_map
	canvas.site_selected.connect(_on_site_selected)
	vbox.add_child(canvas)

	var travel_row := HBoxContainer.new()
	travel_row.add_theme_constant_override("separation", 10)
	vbox.add_child(travel_row)
	_selection = Label.new()
	_selection.name = "Selection"
	_selection.add_theme_color_override("font_color", MapCanvas.SITE_COLOR)
	_selection.add_theme_font_size_override("font_size", 14)
	_selection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	travel_row.add_child(_selection)
	_travel_button = Button.new()
	_travel_button.name = "Travel"
	_travel_button.text = "Travel"
	_travel_button.focus_mode = Control.FOCUS_NONE
	_travel_button.visible = false
	_travel_button.pressed.connect(request_travel)
	travel_row.add_child(_travel_button)

	var bottom := HBoxContainer.new()
	vbox.add_child(bottom)
	_status = Label.new()
	_status.name = "Status"
	_status.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	_status.add_theme_font_size_override("font_size", 12)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_status)
	var hint := Label.new()
	hint.text = "LMB: use tool   RMB: erase   MMB / Space+LMB: pan   M / Esc: close"
	hint.add_theme_color_override("font_color", UiStyle.TEXT_DIM * Color(1, 1, 1, 0.6))
	hint.add_theme_font_size_override("font_size", 12)
	bottom.add_child(hint)

class _SymbolIcon extends Control:
	var sym := 0
	func _draw() -> void:
		MapCanvas.draw_symbol(self, size * 0.5, sym, 7.0, MapCanvas.MARKER_COLOR)
