extends SceneTree
## #446 harness: the overworld dungeon gates are spread out across the
## expanded (#436) field (Daniel, 2026-11-09: "make the portals more spread
## out in the map" -> use the whole bigger overworld, hand-placed fixed
## positions, hub gate stays near the center).
##   (A) every gate sits at its hand-placed position; the hub gate and the
##       arrival point are unchanged.
##   (B) the spread is real: the dungeon gates' bounding box spans most of
##       the field and no two dungeon gates are closer than 1000 px.
##   (C) the code-drawn ground covers every gate, with room to spare
##       (inside 85% of the field ellipse), and every gate gets its pad.
##   (D) every entrance guard / patrol point sits near its own gate
##       (moved with it, same relative layout as before) and on the field.
##   (E) decor keeps off every guard post and patrol loop.

const EXPECTED := {
	"GateHub": Vector2(576, 640),
	"GateNormal": Vector2(-1100, 50),
	"GateRed": Vector2(2252, 50),
	"GateGenerated": Vector2(-700, 1050),
	"GateDefense": Vector2(1850, 1050),
	"GateBeast": Vector2(-700, -1200),
	"GateMaze": Vector2(576, -1650),
	"GateBoss": Vector2(1850, -1200),
}
const GUARD_GATE := {
	"GuardsNormal": "GateNormal",
	"GuardsRed": "GateRed",
	"GuardsGenerated": "GateGenerated",
	"GuardsBeast": "GateBeast",
	"GuardsBoss": "GateBoss",
}

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[446] ", label, " -> ", "PASS" if ok else "FAIL")

func _initialize() -> void:
	call_deferred("_run")

func _ellipse_r(p: Vector2) -> float:
	var d := p - OverworldGround.CENTER
	return Vector2(d.x / OverworldGround.RADII.x, d.y / OverworldGround.RADII.y).length()

func _run() -> void:
	var area: Node2D = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(area)
	await physics_frame
	var ground := area.get_node("Ground") as OverworldGround

	# (A) hand-placed positions
	for n in EXPECTED:
		var g := area.get_node_or_null(n) as Node2D
		_check(g != null and g.position == EXPECTED[n], "%s at %s" % [n, EXPECTED[n]])
	_check((area.get_node("PlayerSpawn") as Node2D).position == Vector2(576, 480), "arrival point unchanged")
	var hub_pos: Vector2 = EXPECTED["GateHub"]
	_check(_ellipse_r(hub_pos) < 0.4, "hub gate stays near the field center")

	# (B) spread
	var dungeon_gates: Array[Vector2] = []
	for n in EXPECTED:
		if n != "GateHub":
			dungeon_gates.append(EXPECTED[n])
	var box := Rect2(dungeon_gates[0], Vector2.ZERO)
	for p in dungeon_gates:
		box = box.expand(p)
	_check(box.size.x >= OverworldGround.RADII.x * 2.0 * 0.6, "gates span >= 60%% of the field width (%.0f px)" % box.size.x)
	_check(box.size.y >= OverworldGround.RADII.y * 2.0 * 0.6, "gates span >= 60%% of the field height (%.0f px)" % box.size.y)
	var min_d := INF
	for i in dungeon_gates.size():
		for j in range(i + 1, dungeon_gates.size()):
			min_d = minf(min_d, dungeon_gates[i].distance_to(dungeon_gates[j]))
	_check(min_d >= 1000.0, "no two dungeon gates closer than 1000 px (min %.0f)" % min_d)
	var far := 0
	for p in dungeon_gates:
		if p.distance_to(hub_pos) > 1200.0:
			far += 1
	_check(far == dungeon_gates.size(), "every dungeon gate is > 1200 px from the hub gate")

	# (C) ground coverage
	_check(ground.landmarks.size() == EXPECTED.size(), "ground has a pad for all %d gates" % EXPECTED.size())
	for n in EXPECTED:
		var p: Vector2 = EXPECTED[n]
		_check(ground.covers(p) and _ellipse_r(p) <= 0.85, "%s on the field with margin (r=%.2f)" % [n, _ellipse_r(p)])
		_check(ground.landmarks.has(p), "%s has its landing pad" % n)

	# (D) guards moved with their gates
	var holder := area.get_node("EntranceGuards")
	for gname in GUARD_GATE:
		var guards := holder.get_node(gname) as EntranceGuards
		var gate_pos: Vector2 = EXPECTED[GUARD_GATE[gname]]
		var ok := true
		var on_field := true
		for entry in guards.entries:
			var pts: Array = [entry["position"]]
			pts.append_array(entry.get("route", []))
			for q in pts:
				if (q as Vector2).distance_to(gate_pos) > 300.0:
					ok = false
				if not ground.covers(q):
					on_field = false
		_check(ok, "%s posts/patrols within 300 px of %s" % [gname, GUARD_GATE[gname]])
		_check(on_field, "%s points all on the field" % gname)

	# (E) no decor on any guard post or patrol loop (solid trees would stall
	# the patrols at their new spots).
	_check(ground.patrols.size() > 0, "ground read the guard beats (%d)" % ground.patrols.size())
	var off_beat := true
	for d in ground.decor:
		if ground.patrol_distance(d["at"]) <= OverworldGround.PATROL_CLEAR:
			off_beat = false
	_check(off_beat, "no tree or rock within %.0f px of a guard post / patrol loop" % OverworldGround.PATROL_CLEAR)

	print("[446] failures: ", failures)
	print("RESULT: ALL PASS" if failures == 0 else "RESULT: FAIL")
	quit(1 if failures > 0 else 0)
