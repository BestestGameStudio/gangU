class_name WolfCaves
extends Node
## #474 (Daniel, 2026-11-09: "caves spawn near the edges of the
## overworld"): the overworld's wolf-den container, same idiom as the
## EntranceGuards container. On _ready it reads the OverworldGround sibling
## (already laid out: Ground precedes this node in the scene, and its
## _ready builds the field), picks CAVE_COUNT deterministic spots near the
## field's edge - inside the outline, off the roads, clear of gates,
## guard beats, spawn and standing decor - and instances a WolfCave at
## each. Everything else (spawning, hunting, retreat) is the cave's.
##
## Harnesses that mount a bare WolfCave scene directly never load this
## container; it exists only for production scene placement.

const CAVE_SCENE := preload("res://game/enemies/spawners/wolf_cave.tscn")

const CAVE_COUNT := 3
## Ring fraction where placement starts, walking inward until clear.
const EDGE_FRACTION := 0.86
## A cave keeps this far from standing decor (trees/rocks).
const DECOR_CLEAR := 90.0

func _ready() -> void:
	var area := get_parent()
	var ground := area.get_node_or_null("Ground") as OverworldGround
	if ground == null:
		push_warning("WolfCaves: no OverworldGround sibling; no caves placed.")
		return
	for i in CAVE_COUNT:
		var at := _pick_spot(ground, i)
		if at == Vector2.INF:
			continue
		var cave: WolfCave = CAVE_SCENE.instantiate()
		cave.name = "WolfCave%d" % (i + 1)
		cave.area_path = NodePath("../..")
		# Cave -> wolf -> player: the wolf is parented to the area, so the
		# production Main/<Area>/<Wolf> -> Main/Player path holds.
		cave.player_path = NodePath("../../Player")
		add_child(cave)
		cave.position = at

## Deterministic edge spot for cave i: a hashed angle around the field,
## walked inward from the edge ring until the spot is inside the outline
## and clear of roads, gates, patrol beats, the arrival point and decor.
func _pick_spot(ground: OverworldGround, i: int) -> Vector2:
	var ang := TAU * float(i) / float(CAVE_COUNT) + (OverworldGround._hash01(i, 7, 51) - 0.5) * 0.9
	var dir := Vector2.from_angle(ang)
	for step in 24:
		var f := EDGE_FRACTION - step * 0.015
		if f < 0.45:
			break
		var at: Vector2 = OverworldGround.CENTER + Vector2(dir.x * OverworldGround.RADII.x, dir.y * OverworldGround.RADII.y) * f
		var desert := ground.get_parent().get_node_or_null("DesertStatueArena") as DesertStatueArena
		if desert != null and desert.contains_footprint(at, DECOR_CLEAR):
			continue
		if not ground.covers(at):
			continue
		if ground.road_distance(at) <= OverworldGround.ROAD_CLEAR:
			continue
		if ground.patrol_distance(at) <= OverworldGround.PATROL_CLEAR:
			continue
		if at.distance_to(ground.spawn) < OverworldGround.GATE_CLEAR:
			continue
		var blocked := false
		for l in ground.landmarks:
			if at.distance_to(l) < OverworldGround.GATE_CLEAR:
				blocked = true
				break
		if blocked:
			continue
		for d in ground.decor:
			if at.distance_to(d["at"]) < DECOR_CLEAR:
				blocked = true
				break
		if blocked:
			continue
		return at
	return Vector2.INF
