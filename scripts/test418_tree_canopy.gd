extends SceneTree
## #418 harness: overworld trees visually obscure characters standing close
## by (Daniel, 2026-11-09: "Trees should visually obscure characters
## standing close by").
##   (A) the real overworld's Ground has a Canopy node that draws the tree
##       crowns at an absolute z above the player, enemies and summons.
##   (B) the floor itself (grass, roads, tree shadows) stays below them.
##   (C) damage numbers still draw above the canopy, so combat stays
##       readable under a tree.
##   (D) collision/decor are untouched: every tree is still unwalkable.

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[418] ", label, " -> ", "PASS" if ok else "FAIL")

## Effective draw z of a CanvasItem (sums relative z up the chain).
func _effective_z(n: Node) -> int:
	var z := 0
	while n != null and n is CanvasItem:
		var ci := n as CanvasItem
		z += ci.z_index
		if not ci.z_as_relative:
			return z
		n = n.get_parent()
	return z

func _initialize() -> void:
	var area: Node2D = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(area)
	await process_frame
	await process_frame
	var ground := area.get_node("Ground") as OverworldGround
	var map := area.get_node("Terrain") as TerrainMap

	var player: Player = load("res://scenes/player.tscn").instantiate()
	area.add_child(player)
	var enemy: Enemy = load("res://scenes/enemy.tscn").instantiate()
	area.add_child(enemy)
	var summon := Summon.new()
	area.add_child(summon)
	await process_frame

	# --- (A) canopy above characters ---
	var canopy := ground.canopy()
	_check(canopy != null and canopy.get_parent() == ground, "A: Ground owns a Canopy node")
	_check(canopy != null and canopy.visible, "A: canopy is visible")
	var cz := _effective_z(canopy)
	_check(cz == OverworldGround.CANOPY_Z, "A: canopy z is absolute (%d)" % cz)
	_check(cz > _effective_z(player), "A: canopy draws above the player (%d > %d)" % [cz, _effective_z(player)])
	_check(cz > _effective_z(enemy), "A: canopy draws above enemies")
	_check(cz > _effective_z(summon), "A: canopy draws above summons")

	# --- (B) floor stays below ---
	_check(_effective_z(ground) < _effective_z(player), "B: ground floor/shadows stay below characters")

	# --- (C) damage numbers above canopy ---
	var dn := DamageNumber.create(Vector2.ZERO, 7)
	area.add_child(dn)
	_check(_effective_z(dn) > cz, "C: damage numbers draw above the canopy")
	dn.queue_free()

	# --- (D) collision unchanged ---
	var trees := 0
	var blocked := true
	for d in ground.decor:
		if d["kind"] == "tree":
			trees += 1
			if map.is_walkable_at(d["at"]):
				blocked = false
	_check(trees > 0 and blocked, "D: all %d trees still unwalkable" % trees)

	summon.queue_free()
	area.queue_free()
	await process_frame
	print("[418] DONE failures=", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)
