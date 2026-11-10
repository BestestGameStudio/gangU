class_name TerrainBlock
## #216: placement rules for the spell-created terrain block. Pure queries
## and one write through the TerrainMap seam (set_cell); no state. The block
## itself is an ordinary destroyable tile (#169), so destroy_at breaks it and
## walkability/rendering update the same way they do for any destroyable tile.
##
## PLACEHOLDER rules (the issue leaves placement open; owner to confirm):
## - target: the cell under the aim point, pulled back along the aim line to
##   at most `max_range` pixels from the caster;
## - one cell, placed only on a currently walkable cell;
## - refused on any cell a body is standing in (caster, enemies, summons),
##   so nobody gets sealed inside the block;
## - permanent until destroyed.

## The cell the block would land in for an aim at `aim_point`.
static func target_cell(map: TerrainMap, origin: Vector2, aim_point: Vector2, max_range: float) -> Vector2i:
	var offset := aim_point - origin
	if max_range > 0.0 and offset.length() > max_range:
		offset = offset.normalized() * max_range
	return map.world_to_cell(origin + offset)

## True when `type` may be placed at `cell`: a registered destroyable type,
## a walkable target cell, and no blocker standing inside it.
static func can_place(map: TerrainMap, cell: Vector2i, type: StringName, blockers: Array[Vector2]) -> bool:
	if map == null or not TerrainTypes.is_valid(type) or not TerrainTypes.is_destroyable(type):
		return false
	if not map.is_walkable_at_cell(cell):
		return false
	for pos in blockers:
		if map.world_to_cell(pos) == cell:
			return false
	return true

## Places the block. Returns the placed cell, or null when refused.
static func place(map: TerrainMap, origin: Vector2, aim_point: Vector2, max_range: float, type: StringName, blockers: Array[Vector2]) -> Variant:
	if map == null:
		return null
	var cell := target_cell(map, origin, aim_point, max_range)
	if not can_place(map, cell, type, blockers):
		return null
	if not map.set_cell(cell, type):
		return null
	return cell

## Positions of every body that must not be sealed inside a block: the
## caster's owner plus all enemies and summons in the tree.
static func blockers_in(tree: SceneTree, caster_owner: Node2D) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if caster_owner != null:
		out.append(caster_owner.global_position)
	for group in [&"enemies", &"summons", PhysicsLayers.PLAYER_GROUP]:
		for n in tree.get_nodes_in_group(group):
			if n is Node2D and n != caster_owner:
				out.append((n as Node2D).global_position)
	return out
