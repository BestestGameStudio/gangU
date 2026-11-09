class_name MapCanvas
extends Control
## (#347) The drawable surface inside MapPanel. Renders WorldMap data for
## the current area centered on `center` (world px) at `map_scale`, and turns
## mouse input into marks: LMB applies the active tool (draw / marker /
## erase), RMB always erases. Marks are stored in world coordinates, so they
## stay put whatever the view scale.
##
## Shown: explored cells (terrain colour from the area's TerrainMap, or the
## GROUND colour on flat areas), fog over everything else, the player's own
## position, and the player's own marks. NOT shown: gates, portals, enemies
## or any other area detail (#347 settled - players mark those themselves).
## EXCEPTION (#366): CLEARED dungeons are drawn at their entrance (gold
## badge + check + name). LMB on one selects it for fast travel
## (`site_selected`) instead of using the tool.
##
## `view_id` (#366) picks which area is shown: empty = the player's current
## area. The player dot only shows in the current area.

signal site_selected(dungeon_id: StringName)

enum Tool { DRAW, MARKER, ERASE }

const SITE_COLOR := Color(1.0, 0.82, 0.3, 1.0)
const SITE_SELECTED_COLOR := Color(0.45, 1.0, 0.55, 1.0)
const SITE_RADIUS := 11.0
## Click reach for selecting a site, in SCREEN px.
const SITE_PICK_PX := 18.0

const FOG_COLOR := Color(0.03, 0.03, 0.05, 1.0)
const FALLBACK_GROUND := Color(0.16, 0.24, 0.18, 1.0)
const GRID_COLOR := Color(1.0, 1.0, 1.0, 0.05)
const PLAYER_COLOR := Color(0.4, 0.85, 1.0, 1.0)
const INK_COLOR := Color(0.98, 0.86, 0.4, 1.0)
const MARKER_COLOR := Color(1.0, 0.42, 0.36, 1.0)
const MARKER_SIZE := 9.0
const INK_WIDTH := 2.5
## Erase reach in SCREEN px (converted to world on use).
const ERASE_RADIUS_PX := 12.0

var world_map: WorldMap = null
var center: Vector2 = Vector2.ZERO
var map_scale: float = 0.375
var tool: Tool = Tool.DRAW
var symbol: WorldMap.Symbol = WorldMap.Symbol.CROSS
## (#366) Area shown; &"" follows the player's current area.
var view_id: StringName = &""
## (#366) Cleared dungeon picked on the map, or &"".
var selected_site: StringName = &""

## The area being drawn and edited.
func view() -> StringName:
	if view_id != &"":
		return view_id
	return world_map.area_id if world_map != null else &""

## (#366) Cleared site within SITE_PICK_PX of a canvas-local point, or &"".
func site_at(local: Vector2) -> StringName:
	if world_map == null:
		return &""
	var best := &""
	var best_d := SITE_PICK_PX
	var s := world_map.cleared_sites(view())
	for d: StringName in s:
		var dist := world_to_screen(s[d]).distance_to(local)
		if dist <= best_d:
			best = d
			best_d = dist
	return best

func select_site(dungeon_id: StringName) -> void:
	selected_site = dungeon_id
	site_selected.emit(dungeon_id)
	queue_redraw()

## Transient drag state. A drag belongs to ONE button in ONE area: `_drag_button`
## is the button that started it (NONE = idle), `_drag_area` the area it began
## in. Motion only continues a drag while that exact button is still held, so
## a release the canvas never saw (map closed mid-drag) can't leave a ghost
## stroke/erase that hover later extends (PR #355 review).
var _stroke := -1
var _erasing := false
var _drag_button: MouseButton = MOUSE_BUTTON_NONE
var _drag_area: StringName = &""

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	visibility_changed.connect(cancel_interaction)

## Drops any in-progress stroke/erase. Called on open/close, area change,
## hide, and whenever the held buttons no longer match the drag.
func cancel_interaction() -> void:
	_stroke = -1
	_erasing = false
	_drag_button = MOUSE_BUTTON_NONE
	_drag_area = &""

func is_interacting() -> bool:
	return _drag_button != MOUSE_BUTTON_NONE

func _start_drag(button: MouseButton) -> void:
	_drag_button = button
	_drag_area = view()

func screen_to_world(local: Vector2) -> Vector2:
	return center + (local - size * 0.5) / map_scale

func world_to_screen(world: Vector2) -> Vector2:
	return (world - center) * map_scale + size * 0.5

func _gui_input(event: InputEvent) -> void:
	if world_map == null:
		return
	var id := view()
	# A drag that began in another area is stale (area swapped mid-drag).
	if is_interacting() and _drag_area != id:
		cancel_interaction()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT:
			return
		var w := screen_to_world(mb.position)
		accept_event()
		if not mb.pressed:
			# Only the button that owns the drag ends it.
			if mb.button_index == _drag_button:
				cancel_interaction()
			return
		# A new press always replaces whatever drag was running.
		cancel_interaction()
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_start_drag(MOUSE_BUTTON_RIGHT)
			_erasing = true
			world_map.erase_near(id, w, ERASE_RADIUS_PX / map_scale)
			return
		# (#366) LMB on a cleared dungeon selects it, whatever the tool.
		var site := site_at(mb.position)
		if site != &"":
			select_site(site)
			return
		match tool:
			Tool.DRAW:
				_stroke = world_map.begin_stroke(id, w)
				if _stroke >= 0:
					_start_drag(MOUSE_BUTTON_LEFT)
			Tool.MARKER:
				world_map.add_marker(id, w, symbol)
			Tool.ERASE:
				_start_drag(MOUSE_BUTTON_LEFT)
				_erasing = true
				world_map.erase_near(id, w, ERASE_RADIUS_PX / map_scale)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		accept_event()
		if not is_interacting():
			return # hover never draws or erases
		var held_mask := MOUSE_BUTTON_MASK_LEFT if _drag_button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
		if (mm.button_mask & held_mask) == 0:
			cancel_interaction() # the release happened somewhere we never saw
			return
		var w := screen_to_world(mm.position)
		if _stroke >= 0:
			var pts: Array = world_map.strokes(id)
			# Skip sub-pixel jitter so the per-stroke point cap lasts.
			if _stroke < pts.size() and (pts[_stroke] as PackedVector2Array)[-1].distance_to(w) * map_scale >= 3.0:
				world_map.extend_stroke(id, _stroke, w)
		elif _erasing:
			world_map.erase_near(id, w, ERASE_RADIUS_PX / map_scale)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), FOG_COLOR)
	if world_map == null:
		return
	var id := view()
	var cell_px := WorldMap.CELL_SIZE * map_scale
	var c0 := WorldMap.world_to_cell(screen_to_world(Vector2.ZERO))
	var c1 := WorldMap.world_to_cell(screen_to_world(size))
	for y in range(c0.y, c1.y + 1):
		for x in range(c0.x, c1.x + 1):
			var cell := Vector2i(x, y)
			if not world_map.is_explored(id, cell):
				continue
			var tl := world_to_screen(Vector2(cell) * WorldMap.CELL_SIZE)
			var r := Rect2(tl, Vector2(cell_px, cell_px))
			draw_rect(r, _terrain_color(cell))
			draw_rect(r, GRID_COLOR, false, 1.0)
	for s: PackedVector2Array in world_map.strokes(id):
		var pts := PackedVector2Array()
		for p in s:
			pts.append(world_to_screen(p))
		if pts.size() == 1:
			draw_circle(pts[0], INK_WIDTH, INK_COLOR)
		else:
			draw_polyline(pts, INK_COLOR, INK_WIDTH, true)
	for m: Dictionary in world_map.markers(id):
		draw_symbol(self, world_to_screen(m["pos"]), m["symbol"], MARKER_SIZE, MARKER_COLOR)
	var sites := world_map.cleared_sites(id)
	for d: StringName in sites:
		_draw_site(world_to_screen(sites[d]), d, d == selected_site)
	if id == world_map.area_id and is_instance_valid(world_map.player):
		var pp := world_to_screen(world_map.player.global_position)
		draw_circle(pp, 6.0, Color.BLACK)
		draw_circle(pp, 4.5, PLAYER_COLOR)

## (#366) Cleared-dungeon badge: gold disc with a check mark and the name.
## Selected = green with a ring.
func _draw_site(p: Vector2, dungeon_id: StringName, selected: bool) -> void:
	var col := SITE_SELECTED_COLOR if selected else SITE_COLOR
	if selected:
		draw_arc(p, SITE_RADIUS + 5.0, 0.0, TAU, 32, col, 2.0)
	draw_circle(p, SITE_RADIUS + 1.5, Color.BLACK)
	draw_circle(p, SITE_RADIUS, col)
	var check := PackedVector2Array([p + Vector2(-5.5, 0.5), p + Vector2(-1.5, 4.5), p + Vector2(5.5, -4.0)])
	draw_polyline(check, Color(0.08, 0.08, 0.1), 3.0)
	var font := ThemeDB.fallback_font
	var label := FastTravelRoutes.label_for(dungeon_id)
	if label == "":
		label = String(dungeon_id)
	var fs := 13
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := p + Vector2(-w * 0.5, SITE_RADIUS + 16.0)
	draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color.BLACK)
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _terrain_color(cell: Vector2i) -> Color:
	var t := world_map.terrain
	if t == null or not is_instance_valid(t):
		return FALLBACK_GROUND
	var type := t.tile_type_at(WorldMap.cell_center(cell))
	var tile: TerrainTile = t.palette.tile(type) if t.palette != null else null
	return tile.color if tile != null else TerrainSeason.color(t.season, type)

## Shared by the canvas and the tool buttons' icons.
static func draw_symbol(ci: CanvasItem, p: Vector2, sym: int, s: float, col: Color) -> void:
	var outline := Color(0, 0, 0, 0.85)
	match sym:
		WorldMap.Symbol.CROSS:
			for w_col in [[4.5, outline], [2.5, col]]:
				ci.draw_line(p + Vector2(-s, -s), p + Vector2(s, s), w_col[1], w_col[0])
				ci.draw_line(p + Vector2(-s, s), p + Vector2(s, -s), w_col[1], w_col[0])
		WorldMap.Symbol.CIRCLE:
			ci.draw_arc(p, s, 0.0, TAU, 24, outline, 4.5)
			ci.draw_arc(p, s, 0.0, TAU, 24, col, 2.5)
		WorldMap.Symbol.TRIANGLE:
			var tri := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, s * 0.8), p + Vector2(-s, s * 0.8), p + Vector2(0, -s)])
			ci.draw_polyline(tri, outline, 4.5)
			ci.draw_polyline(tri, col, 2.5)
		WorldMap.Symbol.STAR:
			var pts := PackedVector2Array()
			for i in 10:
				var r := s * 1.3 if i % 2 == 0 else s * 0.55
				var a := -PI / 2.0 + i * PI / 5.0
				pts.append(p + Vector2(cos(a), sin(a)) * r)
			ci.draw_colored_polygon(pts, col)
			pts.append(pts[0])
			ci.draw_polyline(pts, outline, 1.5)
