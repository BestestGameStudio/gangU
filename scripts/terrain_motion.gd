class_name TerrainMotion
## Turns a mover's desired velocity into the velocity the terrain allows.
## Movement rules are registry data (speed_multiplier, friction, walkable,
## swimmable, movement category) read through the TerrainMap lookup seam;
## movers never branch on tile type. Velocity movement (WASD, dash) goes
## through resolve(); instant moves (pushes, spell movement) go through
## clamp_displacement() / Player.displace().

## On a low-friction cell, friction * GRIP is the acceleration (px/s^2)
## toward the target velocity. ICE (0.12) gives 432 px/s^2, so a 320 px/s
## mover takes about 0.74s to stop.
const GRIP: float = 3600.0

static func resolve(map: TerrainMap, position: Vector2, previous: Vector2, desired: Vector2, delta: float, can_swim: bool) -> Vector2:
	if map == null:
		return desired
	var here := map.world_to_cell(position)
	var velocity := desired
	# A mover standing on a cell it could not enter (spawned there, or the
	# map changed under it) walks out at full grip instead of being trapped.
	if map.can_enter_cell(here, can_swim):
		var target: Vector2 = desired * map.speed_multiplier_at_cell(here)
		var friction: float = map.friction_at_cell(here)
		velocity = target if friction >= 1.0 else previous.move_toward(target, friction * GRIP * delta)
	if _can_step(map, here, position + velocity * delta, can_swim):
		return velocity
	var along_x := Vector2(velocity.x, 0.0)
	if _can_step(map, here, position + along_x * delta, can_swim):
		return along_x
	var along_y := Vector2(0.0, velocity.y)
	if _can_step(map, here, position + along_y * delta, can_swim):
		return along_y
	return Vector2.ZERO

## #266: true iff a mover may stand in the cell at `world_pos`. FALLING
## cells are never enterable (for now), BLOCKING ones only by a swimmer
## when the tile is swimmable. A null map allows everything.
static func can_enter(map: TerrainMap, world_pos: Vector2, can_swim: bool) -> bool:
	return map == null or map.can_enter_cell(map.world_to_cell(world_pos), can_swim)

## #266: the terrain seam for every movement that is not a per-frame
## velocity (pushes/knockback, spell blinks/leaps, scripted shoves). Walks
## from `from` toward `to` and returns the furthest point reached before the
## first cell the mover may not enter, so a push or blink never lands in a
## wall, forest, mountain, pit or cliff, nor passes through one.
static func clamp_displacement(map: TerrainMap, from: Vector2, to: Vector2, can_swim: bool) -> Vector2:
	if map == null:
		return to
	var step := maxf(float(map.cell_size) * 0.25, 1.0)
	var steps := maxi(ceili(from.distance_to(to) / step), 1)
	var reached := from
	var cell := map.world_to_cell(from)
	for i in range(1, steps + 1):
		var p := from.lerp(to, float(i) / float(steps))
		var c := map.world_to_cell(p)
		if c != cell:
			if not can_enter(map, p, can_swim) or _cuts_corner(map, cell, c, can_swim):
				return reached
			cell = c
		reached = p
	return reached

static func _can_step(map: TerrainMap, a: Vector2i, to: Vector2, can_swim: bool) -> bool:
	var b := map.world_to_cell(to)
	if a == b:
		return true
	return map.can_enter_cell(b, can_swim) and not _cuts_corner(map, a, b, can_swim)

## #328: a move that changes both the column and the row of the mover's
## cell passes the shared corner of the two side cells, so it is only
## allowed when both of them are enterable. Without this a diagonal step
## slips between two diagonally touching walls, or clips the corner of a
## single wall, because only the destination cell was checked.
static func _cuts_corner(map: TerrainMap, a: Vector2i, b: Vector2i, can_swim: bool) -> bool:
	if a.x == b.x or a.y == b.y:
		return false
	return not map.can_enter_cell(Vector2i(b.x, a.y), can_swim) or not map.can_enter_cell(Vector2i(a.x, b.y), can_swim)
