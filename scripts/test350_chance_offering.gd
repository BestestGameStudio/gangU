extends SceneTree
## #350 headless driver: a dungeon offering's NORMAL/RED type is decided by
## chance (no rank system), and the existing semantics follow the rolled type.
## #346: the offering gates live in the overworld, so each leg enters it via
## main.enter_overworld() before touching gates;
## NORMAL allows retreat, RED locks the player in until the objective clears.
## The production distribution is 50/50 (Colin, 2026-11-08), rolled once per
## run per gate and fixed until death. Legs:
##   roll   - GateOffering unit rolls (unset / 0 / 1 / seeded mix / BOSS)
##   prod   - production offering is 50/50; overworld gates roll a valid type
##   fixed  - a gate's rolled type survives an overworld re-entry within the
##            a death restart (fresh Main) starts an empty roll record
##   red    - every offering forced RED (test-only value): GateNormal rolls
##            RED, DungeonA mounts its portal LOCKED with the red look and
##            opens once its objective clears
##   normal - every offering forced NORMAL (test-only value): GateRed rolls
##            NORMAL, DungeonB mounts its portal UNLOCKED and retreat works
## Gate/portal use follows the test9/test204 direct _on_body_entered idiom;
## enemy kills use the apply_damage shortcut, not natural combat.

const OFFERING_PATH := "res://resources/gate_offering.tres"
var _fails := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	print("[350] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _boot() -> Node:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	return main

func _shutdown(main: Node) -> void:
	main.queue_free()
	await _frames(3)

## #346: dungeon gates (and their #350 offerings) live in the overworld.
func _enter_overworld(main: Node) -> Node:
	main.enter_overworld()
	await _frames(4)
	return main.current_area

func _run() -> void:
	_roll_leg()
	var offering := load(OFFERING_PATH) as GateOffering
	_check("prod: offering resource loads", offering != null)
	if offering == null:
		_finish()
		return
	_check("prod: 50/50 distribution set (Colin, 2026-11-08)", offering.is_set() and is_equal_approx(offering.red_chance, 0.5))
	await _prod_leg(offering)
	await _fixed_leg()
	offering.red_chance = 1.0
	await _red_leg()
	offering.red_chance = 0.0
	await _normal_leg()
	offering.red_chance = GateOffering.UNSET
	_finish()

func _roll_leg() -> void:
	var o := GateOffering.new()
	_check("roll: unset keeps authored NORMAL", o.roll(Gate.GateType.NORMAL) == Gate.GateType.NORMAL)
	_check("roll: unset keeps authored RED", o.roll(Gate.GateType.RED) == Gate.GateType.RED)
	o.red_chance = 1.0
	_check("roll: chance 1 always RED", o.roll(Gate.GateType.NORMAL) == Gate.GateType.RED)
	o.red_chance = 0.0
	_check("roll: chance 0 always NORMAL", o.roll(Gate.GateType.RED) == Gate.GateType.NORMAL)
	# Test-only mix: proves both outcomes come from the roll, not a fixed pick.
	o.red_chance = 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 350
	var reds := 0
	for i in 200:
		if o.roll(Gate.GateType.NORMAL, rng) == Gate.GateType.RED:
			reds += 1
	_check("roll: seeded mix yields both NORMAL and RED (reds=%d/200)" % reds, reds > 0 and reds < 200)
	var only := [Gate.GateType.NORMAL, Gate.GateType.RED]
	_check("roll: only NORMAL or RED ever rolled", o.roll(Gate.GateType.NORMAL, rng) in only)
	var boss: Gate = (load("res://scenes/gate.tscn") as PackedScene).instantiate()
	boss.gate_type = Gate.GateType.BOSS
	var forced := GateOffering.new()
	forced.red_chance = 1.0
	boss.offering = forced
	root.add_child(boss)
	_check("roll: BOSS gate never rolls", boss.gate_type == Gate.GateType.BOSS and (boss.get_node("TypeLabel") as Label).text == "BOSS")
	boss.free()

func _prod_leg(offering: GateOffering) -> void:
	var main := await _boot()
	var ow: Node = await _enter_overworld(main)
	var gn := ow.get_node_or_null("GateNormal") as Gate
	var gr := ow.get_node_or_null("GateRed") as Gate
	_check("prod: both overworld dungeon gates carry the shared offering", gn != null and gr != null and gn.offering == offering and gr.offering == offering)
	var valid := [Gate.GateType.NORMAL, Gate.GateType.RED]
	_check("prod: both gates rolled a valid NORMAL/RED type",
		gn != null and gr != null and gn.gate_type in valid and gr.gate_type in valid)
	_check("prod: rolls recorded per gate on Main", gn != null and gr != null
		and main._offering_rolls.get(&"GateNormal") == gn.gate_type
		and main._offering_rolls.get(&"GateRed") == gr.gate_type)
	var gb := ow.get_node_or_null("GateBoss") as Gate
	var gg := ow.get_node_or_null("GateGenerated") as Gate
	_check("prod: boss and generated gates are not chance offerings", gb != null and gb.offering == null and gg != null and gg.offering == null)
	await _shutdown(main)

func _fixed_leg() -> void:
	var main := await _boot()
	var ow: Node = await _enter_overworld(main)
	var gn := ow.get_node_or_null("GateNormal") as Gate
	_check("fixed: GateNormal present", gn != null)
	if gn == null:
		await _shutdown(main)
		return
	var rolled: int = gn.gate_type
	var ow2: Node = await _enter_overworld(main)
	var gn2 := ow2.get_node_or_null("GateNormal") as Gate
	_check("fixed: overworld re-entry within the run keeps the rolled type", gn2 != null and gn2 != gn and gn2.gate_type == rolled)
	await _shutdown(main)
	# A death restart rebuilds Main from scratch, so the new run must boot
	# with its own freshly rolled record, never the previous run's types.
	var main2 := await _boot()
	var ow3: Node = await _enter_overworld(main2)
	var gr2 := ow3.get_node_or_null("GateRed") as Gate
	_check("fixed: death restart (fresh Main) re-rolls into its own record",
		gr2 != null and main2._offering_rolls.get(&"GateRed") == gr2.gate_type
		and main2._offering_rolls.size() <= 2)
	await _shutdown(main2)

func _red_leg() -> void:
	var main := await _boot()
	await _enter_overworld(main)
	var p: Player = main.get_node("Player")
	var gate := main.current_area.get_node_or_null("GateNormal") as Gate
	_check("red: GateNormal rolled RED", gate != null and gate.gate_type == Gate.GateType.RED)
	_check("red: label/tint show RED", gate != null and (gate.get_node("TypeLabel") as Label).text == "RED"
		and (gate.get_node("ColorRect") as ColorRect).color == Gate.RED_TINT)
	_check("red: GateRed rolled RED too", (main.current_area.get_node("GateRed") as Gate).gate_type == Gate.GateType.RED)
	gate._on_body_entered(p)
	await _frames(6)
	var area: Node = main.current_area
	_check("red: entered DungeonA", area.name == &"DungeonA")
	var portal := area.get_node_or_null("ExitPortal") as ExitPortal
	_check("red: DungeonA portal LOCKED (lock-in until objective)", portal != null and portal.locked)
	_check("red: DungeonA portal carries the red look", portal != null and portal.red_portal_look)
	if portal == null:
		await _shutdown(main)
		return
	var left := [false]
	portal.entered.connect(func(_x): left[0] = true)
	portal._on_body_entered(p)
	await _frames(4)
	_check("red: retreat blocked while locked", not left[0] and main.current_area == area)
	for e in get_nodes_in_group("enemies"):
		e.apply_damage(999999)
	await _frames(10)
	_check("red: objective clear unlocks the portal", not portal.locked)
	portal._on_body_entered(p)
	await _frames(6)
	_check("red: exit returns to the overworld entrance after clearing (#378)", left[0] and main.current_area.name == &"Overworld")
	await _shutdown(main)

func _normal_leg() -> void:
	var main := await _boot()
	await _enter_overworld(main)
	var p: Player = main.get_node("Player")
	var gate := main.current_area.get_node_or_null("GateRed") as Gate
	_check("normal: GateRed rolled NORMAL", gate != null and gate.gate_type == Gate.GateType.NORMAL)
	_check("normal: label shows NORMAL", gate != null and (gate.get_node("TypeLabel") as Label).text == "NORMAL")
	gate._on_body_entered(p)
	await _frames(6)
	var area: Node = main.current_area
	_check("normal: entered DungeonB", area.name == &"DungeonB")
	var portal := area.get_node_or_null("ExitPortal") as ExitPortal
	_check("normal: DungeonB portal UNLOCKED (retreat allowed)", portal != null and not portal.locked)
	_check("normal: no red portal look", portal != null and not portal.red_portal_look)
	if portal != null:
		portal._on_body_entered(p)
		await _frames(6)
		_check("normal: retreat to the overworld entrance before clearing (#378)", main.current_area.name == &"Overworld")
	await _shutdown(main)

func _finish() -> void:
	print("[350] RESULT: ", "ALL PASS" if _fails == 0 else "FAIL", " failures=", _fails)
	quit(0 if _fails == 0 else 1)
