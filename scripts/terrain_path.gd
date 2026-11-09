class_name TerrainPath
extends RefCounted
## #391: shared steer-around-terrain routing, extracted from
## SummonBehaviorGuard (#281) so summons AND enemies route around blocking
## terrain the same way (Daniel, 2026-11-09: "enemies can pathfind around
## trees"). Pure steering over the TerrainMap lookup seam
## (is_walkable_at / world_to_cell / cell_to_world - read-only); no state
## beyond one mover's current path, and no writes to the map.
##
## Contract (unchanged from the #281 summon implementation):
##   - A clear straight line steers direct (zero overhead, no path state).
##   - A blocked line triggers a bounded 4-dir A* over the walkability grid
##     (no diagonal corner cutting between blocked cells), replanned on a
##     short timer because the target moves.
##   - TerrainMotion.resolve always has the last word on the velocity, so a
##     blocked step is cancelled (never entered) even at corners.
##   - map == null (harnesses, areas with no Terrain node) returns the
##     desired velocity unchanged - exactly the pre-grid behavior.
##
## One instance per mover (the behavior instance idiom): path, waypoint and
## replan state are per-mover and never shared.

const REPLAN_INTERVAL: float = 0.25
const WAYPOINT_EPS: float = 8.0
const MAX_EXPANSIONS: int = 2000
const SEARCH_MARGIN: int = 16

var _path: Array[Vector2i] = []
var _path_index: int = 0
var _replan_timer: float = 0.0

## The resolved velocity toward `dest`. `desired` is the direct velocity the
## mover wants (used verbatim when no grid is wired or the line is clear);
## `speed` shapes waypoint segments when a detour is needed. Call once per
## physics step: the replan clock accumulates from delta here.
func steer(map: TerrainMap, pos: Vector2, previous: Vector2, desired: Vector2, dest: Vector2, speed: float, delta: float, can_swim: bool = false) -> Vector2:
	_replan_timer = maxf(0.0, _replan_timer - delta)
	if map == null:
		return desired
	if desired == Vector2.ZERO:
		return TerrainMotion.resolve(map, pos, previous, desired, delta, can_swim)
	if _line_walkable(map, pos, dest):
		_path = []
		_replan_timer = REPLAN_INTERVAL
		return TerrainMotion.resolve(map, pos, previous, desired, delta, can_swim)
	if _replan_timer <= 0.0 or _path.is_empty():
		_path = _find_path(map, pos, dest)
		_path_index = 0
		_replan_timer = REPLAN_INTERVAL
	if _path.is_empty():
		# No route found within the search bounds: keep the #165 slide
		# behavior (blocked step cancels) rather than freezing or clipping.
		return TerrainMotion.resolve(map, pos, previous, desired, delta, can_swim)
	var waypoint: Vector2 = map.cell_to_world(_path[_path_index])
	if pos.distance_to(waypoint) < WAYPOINT_EPS and _path_index < _path.size() - 1:
		_path_index += 1
		waypoint = map.cell_to_world(_path[_path_index])
	var wp_desired: Vector2 = (waypoint - pos).normalized() * speed
	var resolved := TerrainMotion.resolve(map, pos, previous, wp_desired, delta, can_swim)
	if resolved == Vector2.ZERO:
		# Wedged (corner or moving target shifted the map): replan next frame.
		_replan_timer = 0.0
	return resolved

## Straight-line walkability, sampled at half-cell steps so no unwalkable
## cell is skipped between samples.
func _line_walkable(map: TerrainMap, from: Vector2, to: Vector2) -> bool:
	var dist := from.distance_to(to)
	var steps := int(ceil(dist / (map.cell_size * 0.5))) + 1
	for i in steps + 1:
		if not map.is_walkable_at(from.lerp(to, float(i) / steps)):
			return false
	return true

## Bounded 4-dir A* over the walkability grid (4-dir: no diagonal corner
## cutting between blocked cells). Returns the cell path EXCLUDING the start
## cell, ending at the goal cell or the reachable walkable cell nearest to it
## (the target may hug a wall); empty when nothing reachable improves on the
## start cell.
func _find_path(map: TerrainMap, from: Vector2, to: Vector2) -> Array[Vector2i]:
	var start := map.world_to_cell(from)
	var goal := map.world_to_cell(to)
	if start == goal:
		return []
	var min_c := Vector2i(mini(start.x, goal.x) - SEARCH_MARGIN, mini(start.y, goal.y) - SEARCH_MARGIN)
	var max_c := Vector2i(maxi(start.x, goal.x) + SEARCH_MARGIN, maxi(start.y, goal.y) + SEARCH_MARGIN)
	var open: Array[Vector2i] = [start]
	var came := {}
	var g := {start: 0.0}
	var best := start
	var best_h := _h(start, goal)
	var expansions := 0
	while not open.is_empty() and expansions < MAX_EXPANSIONS:
		var current := _pop_lowest_f(open, g, goal)
		if map.is_walkable_at_cell(current) and _h(current, goal) < best_h:
			best = current
			best_h = _h(current, goal)
		if current == goal:
			best = current
			break
		expansions += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = current + d
			if next.x < min_c.x or next.y < min_c.y or next.x > max_c.x or next.y > max_c.y:
				continue
			if not map.is_walkable_at_cell(next):
				continue
			var ng: float = g[current] + 1.0 + _clearance_penalty(map, next, goal)
			if ng < g.get(next, INF):
				g[next] = ng
				came[next] = current
				if not open.has(next):
					open.append(next)
	if best == start:
		return []
	var rev: Array[Vector2i] = [best]
	var c := best
	while came.has(c):
		c = came[c]
		if c != start:
			rev.push_front(c)
	return rev

func _pop_lowest_f(open: Array[Vector2i], g: Dictionary, goal: Vector2i) -> Vector2i:
	var best_i := 0
	var best_f := INF
	for i in open.size():
		var f: float = g.get(open[i], INF) + _h(open[i], goal)
		if f < best_f:
			best_f = f
			best_i = i
	var cell := open[best_i]
	open.remove_at(best_i)
	return cell

func _h(a: Vector2i, b: Vector2i) -> float:
	return absf(a.x - b.x) + absf(a.y - b.y)

## Soft one-cell clearance around blocked cells: keeps waypoints (and the
## sprite) off wall corners so the mover never visibly brushes terrain. The
## goal cell is exempt - a target hugging a wall must stay reachable.
func _clearance_penalty(map: TerrainMap, cell: Vector2i, goal: Vector2i) -> float:
	if cell == goal:
		return 0.0
	var blocked := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not map.is_walkable_at_cell(cell + d):
			blocked += 1
	return 0.75 * blocked
