class_name HubServices
extends Node2D
## Small outdoor service clearing on the shared overworld terrain.

const HALF := Vector2(240, 144)

func world_bounds() -> Rect2:
	return Rect2(global_position - HALF, HALF * 2.0)

func contains_player(point: Vector2) -> bool:
	return world_bounds().has_point(point)
