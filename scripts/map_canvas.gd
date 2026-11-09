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

enum Tool { DRAW, MARKER, ERASE }

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

var _stroke := -1
var _erasing := false

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP

func screen_to_world(local: Vector2) -> Vector2:
	return center + (local - size * 0.5) / map_scale

func world_to_screen(world: Vector2) -> Vector2:
	return (world - center) * map_scale + size * 0.5

func _gui_input(event: InputEvent) -> void:
	if world_map == null:
		return
	var id := world_map.area_id
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var w := screen_to_world(mb.position)
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_erasing = mb.pressed
			if mb.pressed:
				world_map.erase_near(id, w, ERASE_RADIUS_PX / map_scale)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				match tool:
					Tool.DRAW:
						_stroke = world_map.begin_stroke(id, w)
					Tool.MARKER:
						world_map.add_marker(id, w, symbol)
					Tool.ERASE:
						_erasing = true
						world_map.erase_near(id, w, ERASE_RADIUS_PX / map_scale)
			else:
				_stroke = -1
				_erasing = false
			accept_event()
	elif event is InputEventMouseMotion:
		var w := screen_to_world((event as InputEventMouseMotion).position)
		if _stroke >= 0:
			var pts: Array = world_map.strokes(id)
			# Skip sub-pixel jitter so the per-stroke point cap lasts.
			if _stroke < pts.size() and (pts[_stroke] as PackedVector2Array)[-1].distance_to(w) * map_scale >= 3.0:
				world_map.extend_stroke(id, _stroke, w)
		elif _erasing:
			world_map.erase_near(id, w, ERASE_RADIUS_PX / map_scale)
		accept_event()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), FOG_COLOR)
	if world_map == null:
		return
	var id := world_map.area_id
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
	if is_instance_valid(world_map.player):
		var pp := world_to_screen(world_map.player.global_position)
		draw_circle(pp, 6.0, Color.BLACK)
		draw_circle(pp, 4.5, PLAYER_COLOR)

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
