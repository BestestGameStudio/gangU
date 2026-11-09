extends SceneTree
## #54 acceptance driver (headless, local composition).
## PRODUCTION (main.tscn): exactly ONE revive item (green cross) per run,
## code-mounted in DungeonA only. Semantics proven here:
##   found    - item present on first DungeonA entry at (900,480)
##   carried  - player contact hands it to the persistent satchel
##              (revive_collected(carried)), item consumed from the world,
##              Main latches the per-run claimed flag
##   unclaimed re-entry - leaving without claiming keeps it available
##   claimed re-entry   - no respawn while carried
##   consume  - a lethal hit with carried>0 revives in place (hp=revive_hp,
##              same scene, NO run restart) instead of reloading
##   claimed+consumed re-entry - still no respawn within the same run
##   contact re-kill - a lethal hit with carried==0 restarts normally
##   new-run reset - after the full reload the item is available again
## Item contact and portal/gate use are driven via the same direct
## _on_body_entered calls test9 uses - NOT real-input movement proof.

var scene: Node
var p: Player
var satchel: ReviveSatchel
var phase := 0
var t := 0.0
var fails := 0

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	# Main._ready (which mounts RunManager/HUD/satchel/pool/...) has NOT run
	# yet at _initialize time - refs to mounted children are grabbed lazily
	# in phase 0 instead (Player exists in the tscn, but the satchel does not).

func _grab_refs() -> void:
	p = scene.get_node("Player")
	satchel = scene.get_node("ReviveSatchel")

func _enter_gate(gate_name: String) -> void:
	if scene.current_area.get_node_or_null(gate_name) == null:
		scene.enter_overworld() # #346: dungeon entrances live in the overworld
	var g: Gate = scene.current_area.get_node(gate_name)
	# #350 pin (test350 covers the roll): this driver's unclaimed-revive
	# retreats need DungeonA's unlocked portal, so the entered gate is
	# pinned NORMAL after its own _ready roll, before entry.
	g.gate_type = Gate.GateType.NORMAL
	g._on_body_entered(p)

func _retreat() -> void:
	var portal: ExitPortal = scene.current_area.get_node("ExitPortal")
	portal._on_body_entered(p)

func _item() -> ReviveItem:
	if scene.current_area == null:
		return null
	return scene.current_area.get_node_or_null("ReviveItem")

func _check(label: String, ok: bool) -> void:
	if not ok:
		fails += 1
	print("[R] ", label, " -> ", "PASS" if ok else "FAIL")

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if satchel == null and scene.get_node_or_null("ReviveSatchel") != null:
				_grab_refs()
			if t > 0.3 and satchel != null:
				_enter_gate("GateNormal")
				phase = 1; t = 0
		1:
			if t > 0.4:
				var it := _item()
				_check("found: one revive item in DungeonA at (900,480)",
					scene.current_area.name == "DungeonA" and it != null
					and it.position == Vector2(900, 480))
				_retreat() # leave UNclaimed
				phase = 2; t = 0
		2:
			if t > 0.4:
				_check("retreat to hub same run", scene.current_area.name == "Hub")
				_enter_gate("GateNormal")
				phase = 3; t = 0
		3:
			if t > 0.4:
				var it := _item()
				_check("unclaimed re-entry: item available again", it != null)
				it._on_body_entered(p) # claim
				_check("carried: satchel collected once", satchel.carried == 1)
				_check("claimed: per-run flag latched", scene._revive_claimed)
				phase = 4; t = 0
		4:
			if t > 0.4:
				_check("claim consumed the world item", _item() == null)
				_retreat()
				phase = 5; t = 0
		5:
			if t > 0.4:
				_enter_gate("GateNormal")
				phase = 6; t = 0
		6:
			if t > 0.4:
				_check("claimed re-entry: no respawn while carried",
					scene.current_area.name == "DungeonA" and _item() == null)
				p.apply_damage(999) # lethal with carried=1 -> revive path
				phase = 7; t = 0
		7:
			if t > 0.4:
				_check("consume: revived in place hp=50, same scene, carried=0",
					current_scene == scene and p.hp == 50 and satchel.carried == 0)
				_retreat()
				phase = 8; t = 0
		8:
			if t > 0.4:
				_enter_gate("GateNormal")
				phase = 9; t = 0
		9:
			if t > 0.4:
				_check("claimed+consumed re-entry: still no respawn this run",
					scene.current_area.name == "DungeonA" and _item() == null)
				p.apply_damage(999) # contact re-kill with carried=0 -> normal restart
				phase = 10; t = 0
		10:
			if current_scene != null and current_scene != scene and t > 0.4:
				var old := scene
				scene = current_scene
				_grab_refs()
				_check("contact re-kill: full restart to hub hp=100 carried=0",
					scene != old and scene.current_area.name == "Hub"
					and p.hp == 100 and satchel.carried == 0)
				_enter_gate("GateNormal")
				phase = 11; t = 0
		11:
			if t > 0.4:
				var it := _item()
				_check("new-run reset: item available again after reload",
					scene.current_area.name == "DungeonA" and it != null)
				it._on_body_entered(p)
				_check("new-run claim works", satchel.carried == 1)
				if fails == 0:
					print("[R] ALL PASS")
				print("[R] DONE")
				quit()
	return false
