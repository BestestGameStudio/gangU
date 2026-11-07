extends SceneTree
## #50 residual harness: HUD backing plate + gate label visibility.
## Drives the PRODUCTION main.tscn: plate must cover the real occupied HUD
## rect (content + viewport driven, rebuilt on change), and gate TypeLabels
## must never render under the plate or off-viewport while staying tied to
## their own gate. All screen rects computed via the live canvas transform.

var failures := 0
var main: Node
var hud: HUD
var frame := 0
var hub_plate_h := 0.0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[50b] ", name, " -> PASS")
	else:
		failures += 1
		print("[50b] ", name, " -> FAIL")

func _label_screen_rect(gate: Gate) -> Rect2:
	var canvas := root.get_canvas_transform()
	var lbl: Label = gate.get_node("TypeLabel")
	var tl: Vector2 = canvas * (gate.global_position + lbl.position)
	return Rect2(tl, lbl.size)

func _initialize() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	frame += 1
	if hud == null:
		hud = root.find_child("HUD", true, false) as HUD
		if frame > 60:
			print("[50b] HUD never mounted -> FAIL")
			quit(1)
		return false
	match frame:
		3:
			_check(hud != null, "HUD mounted")
			var plate: ColorRect = hud.get_node_or_null("BackingPlate")
			_check(plate != null, "BackingPlate exists")
			_check(plate != null and plate.mouse_filter == Control.MOUSE_FILTER_IGNORE, "plate click-through (mouse_filter IGNORE)")
			_check(plate != null and plate.visible, "plate visible")
		6:
			var plate_rect: Rect2 = hud.reserved_rect()
			_check(plate_rect.get_area() > 0.0, "reserved_rect non-empty")
			# Plate covers every visible Root descendant (slot rows bottom).
			var covered := true
			for c in hud.get_node("Root").find_children("*", "Control", true, false):
				if c.visible and not plate_rect.encloses(c.get_global_rect()):
					covered = false
			_check(covered, "plate covers all visible HUD rows (incl. 6 slot rows)")
			# Rebuild on content change: long text must widen the plate.
			var before := plate_rect.size.x
			hud.get_node("Root/HPLabel").text = "HP 100/100 VERYLONGTAIL xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
		9:
			var plate_rect: Rect2 = hud.reserved_rect()
			_check(plate_rect.size.x > 388.0, "plate rebuilt wider after long content (was 388 base)")
			hud.get_node("Root/HPLabel").text = "HP 100/100"
		12:
			# Hub spawn: GateNormal under plate zone -> label flipped clear;
			# GateRed clear -> label keeps default centered placement.
			var hub = main.current_area
			var gn: Gate = hub.get_node("GateNormal")
			var gr: Gate = hub.get_node("GateRed")
			var rr: Rect2 = hud.reserved_rect()
			var rn := _label_screen_rect(gn)
			var rred := _label_screen_rect(gr)
			_check(not rn.intersects(rr), "GateNormal label clear of plate at spawn")
			var vs: Vector2 = root.get_visible_rect().size
			_check(rn.position.x >= 0 and rn.position.y >= 0 and rn.end.x <= vs.x and rn.end.y <= vs.y,
				"GateNormal label inside viewport")
			_check(rn.get_center().distance_to((root.get_canvas_transform() * gn.global_position)) < 120.0,
				"GateNormal label stays tied to own gate")
			var default_tl: Vector2 = (root.get_canvas_transform() * gr.global_position) + Vector2(-26, -10)
			_check(rred.position.distance_to(default_tl) < 2.0, "GateRed label keeps default placement when clear")
		14:
			# Camera sweep: teleport player so GateNormal slides fully under
			# the plate band (would be unreadable pre-fix).
			main.get_node("Player").global_position = Vector2(876, 324)
		20:
			var hub = main.current_area
			var gn: Gate = hub.get_node("GateNormal")
			var rr: Rect2 = hud.reserved_rect()
			var rn := _label_screen_rect(gn)
			_check(not rn.intersects(rr), "GateNormal label clear of plate after camera sweep")
			var vs: Vector2 = root.get_visible_rect().size
			_check(rn.position.x >= 0 and rn.position.y >= 0 and rn.end.x <= vs.x and rn.end.y <= vs.y,
				"GateNormal label inside viewport after camera sweep")
			_check(rn.get_center().distance_to((root.get_canvas_transform() * gn.global_position)) < 160.0,
				"GateNormal label still tied to own gate after camera sweep")
		22:
			# Viewport change: portrait window must rebuild plate + placement.
			root.size = Vector2i(800, 1000)
		28:
			var rr: Rect2 = hud.reserved_rect()
			var covered := true
			for c in hud.get_node("Root").find_children("*", "Control", true, false):
				if c.visible and not rr.encloses(c.get_global_rect()):
					covered = false
			_check(covered, "plate still covers HUD rows after viewport change")
			var gn: Gate = main.current_area.get_node("GateNormal")
			var rn := _label_screen_rect(gn)
			var vs: Vector2 = root.get_visible_rect().size
			_check(rn.position.x >= 0 and rn.end.x <= vs.x, "GateNormal label inside viewport (portrait)")
		30:
			# Objective appearance grows the plate in DungeonA.
			hub_plate_h = hud.reserved_rect().size.y
			var g: Gate = main.current_area.get_node("GateNormal")
			g._on_body_entered(main.get_node("Player"))
		58:
			_check(main.current_area.name == "DungeonA", "entered DungeonA")
			var plate_h: float = hud.reserved_rect().size.y
			_check(plate_h > hub_plate_h, "plate grew with objective row in DungeonA (%.0f -> %.0f)" % [hub_plate_h, plate_h])
			var portal = main.current_area.get_node_or_null("ExitPortal")
			_check(portal != null, "exit portal mounted (regression)")
		61:
			print("[50b] ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
			quit(0 if failures == 0 else 1)
	return false
