class_name TerrainTile
extends Resource
## #266: one dungeon-defined terrain tile: its look and its movement
## category. Lives in a TerrainPalette.
##
## A NEW id (not in TerrainTypes.ALL) is a new tile type with plain ground
## properties (speed 1, full grip, not swimmable, not destroyable, no tags)
## plus the category below. An id that names a BUILT-IN type restyles it:
## the look and category come from here, the other properties (friction,
## destroyable, element tags...) stay the built-in's.

## Tile type id, e.g. &"pine_forest". Must be unique within a palette.
@export var id: StringName = &""
## WALKABLE (grass, snow), BLOCKING (walls, forests, mountains) or FALLING
## (pits, cliffs; for now nothing can enter them).
@export var movement: TerrainTypes.Movement = TerrainTypes.Movement.WALKABLE
## Flat swatch drawn when there is no texture.
@export var color: Color = Color(0.3, 0.3, 0.35, 1.0)
## Optional art; scaled to the map's cell size. Overrides `color`.
@export var texture: Texture2D = null
## Terrain art set (a TerrainArt.SETS id, e.g. &"obstacle_slate",
## &"chasm") that draws this tile. Empty, or an unknown id, keeps the
## flat `color` / `texture` swatch.
@export var art: StringName = &""
