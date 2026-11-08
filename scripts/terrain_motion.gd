class_name TerrainMotion
## Turns a mover's desired velocity into the velocity the terrain allows.
## Movement rules are registry data (speed_multiplier, friction, walkable,
## swimmable) read through the TerrainMap lookup seam; movers never branch
## on tile type.

## On a low-friction cell, friction * GRIP is the acceleration (px/s^2)
## toward the target velocity. ICE (0.12) gives 432 px/s^2, so a 320 px/s
## mover takes about 0.74s to stop.
const GRIP: float = 3600.0

static func resolve(map: TerrainMap, position: Vector2, previous: Vector2, desired: Vector2, delta: float, can_swim: bool) -> Vector2:
	if map == null:
		return desired
	var here := map.properties_at(position)
	var velocity := desired
	# A mover standing on a cell it could not enter (spawned there, or the
	# map changed under it) walks out at full grip instead of being trapped.
	if _enterable(here, can_swim):
		var target: Vector2 = desired * float(here["speed_multiplier"])
		var friction: float = here["friction"]
		velocity = target if friction >= 1.0 else previous.move_toward(target, friction * GRIP * delta)
	for candidate: Vector2 in [velocity, Vector2(velocity.x, 0.0), Vector2(0.0, velocity.y)]:
		if _can_step(map, position, position + candidate * delta, can_swim):
			return candidate
	return Vector2.ZERO

static func _enterable(props: Dictionary, can_swim: bool) -> bool:
	return props["walkable"] or (props["swimmable"] and can_swim)

static func _can_step(map: TerrainMap, from: Vector2, to: Vector2, can_swim: bool) -> bool:
	if map.world_to_cell(from) == map.world_to_cell(to):
		return true
	return _enterable(map.properties_at(to), can_swim)
