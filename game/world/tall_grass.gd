class_name TallGrass
## #461 (Daniel): tall grass hides whoever stands in it. THE single sight
## rule every consumer asks (enemy targeting, enemy drawing for the player,
## summon targeting, homing shots):
##
##   - a target standing OUTSIDE tall grass is always visible (characters in
##     the grass see out of it freely, and nothing outside it is hidden);
##   - a target standing IN tall grass is visible only to a viewer that is
##     also in tall grass and within SIGHT_RADIUS of it.
##
## "In tall grass" is read through the TerrainMap lookup seam
## (TerrainMap.conceals_at), so a palette tile can conceal too. No map
## (flat areas, older fixtures) = nobody is ever hidden.

## Sight range between two characters that are both in tall grass. The issue
## asks for "a small radius"; 96 px (3 overworld cells) is an implementer
## default, not approved balance.
const SIGHT_RADIUS := 96.0

## True when the cell under `pos` hides a character standing there.
static func conceals_at(map: TerrainMap, pos: Vector2) -> bool:
	return map != null and is_instance_valid(map) and map.conceals_at(pos)

## Can a viewer at `viewer_pos` see a character at `target_pos`?
static func can_see(map: TerrainMap, viewer_pos: Vector2, target_pos: Vector2) -> bool:
	if not conceals_at(map, target_pos):
		return true
	return conceals_at(map, viewer_pos) and viewer_pos.distance_to(target_pos) <= SIGHT_RADIUS
