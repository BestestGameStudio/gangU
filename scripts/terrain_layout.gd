class_name TerrainLayout
extends Resource
## Layout archetype a dungeon definition selects for TerrainGen.generate:
## how much of the map is open space, and how many routes join spawn to exit.

enum Enclosure { OPEN, ENCLOSED }
enum Route { LINEAR, FORKED }

@export var enclosure: Enclosure = Enclosure.OPEN
@export var route: Route = Route.LINEAR
