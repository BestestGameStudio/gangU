extends SceneTree
## #91 acceptance driver (headless, production composition via main.tscn).
## Proves the flat-geometric gate/exit-portal decor within its exact
## boundary - ColorRect TYPE + 52x72 offsets, TypeLabel/StateLabel type +
## geometry and both RectangleShape2D (52,72) collision shapes UNCHANGED:
##   structure  - gate.tscn and exit_portal.tscn keep every script-coupled
##                node exactly (scripts drive $ColorRect/$TypeLabel/
##                $StateLabel by name; test50b measures label geometry)
##   decor      - gate: oval portal (Rim Line2D + Body Polygon2D, full
##                look proven by test189); portal: ExitArrow flat Polygon2D
##                (light lavender, UP = exit) - exact points
##   families   - hub boot: rolled NORMAL gate tint blue on both gates
##                (#350 fixture: offering chance forced to 0.0 for this
##                driver so the roll is deterministic; the 50/50 roll and
##                per-run pinning are covered by test350)
##   portal     - real normal-gate entry into DungeonA: ExitPortal decor
##                present, unlocked purple tint, EXIT label text
## The decor legs FAIL on the old base (no decor nodes) - meaningful
## negative. Gate use follows the test9 direct _on_body_entered idiom -
## NOT real-input movement proof.

const LAVENDER := Color(0.85, 0.8, 0.95, 0.9)
const EXIT_ARROW: Array[Vector2] = [Vector2(0, -26), Vector2(14, -6), Vector2(6, -6), Vector2(6, 18), Vector2(-6, 18), Vector2(-6, -6), Vector2(-14, -6)]

var scene: Node
var p: CharacterBody2D
var phase := 0
var t := 0.0
var fails := 0
# #350 fixture: the forced offering must be HELD by the driver - a local
# dies after _initialize, the cache drops the resource, and the overworld
# later reloads it fresh from disk (production 0.5), undoing the force.
var _offering: GateOffering = null

func _initialize() -> void:
	# #350 fixture: force the shared offering to 0.0 so both gates
	# deterministically roll NORMAL through the production roll. Held for the
	# driver's whole lifetime: the overworld gates roll when the driver
	# enters the overworld, after _initialize returns. Restored on quit is
	# unnecessary - this process only runs this driver.
	_offering = load("res://resources/gate_offering.tres") as GateOffering
	_offering.red_chance = 0.0
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene

func _check(label: String, ok: bool) -> void:
	if not ok:
		fails += 1
	print("[91] ", label, " -> ", "PASS" if ok else "FAIL")

func _color_eq(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.001 and absf(a.g - b.g) < 0.001 and absf(a.b - b.b) < 0.001

func _poly_eq(actual: PackedVector2Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for i in actual.size():
		if actual[i] != expected[i]:
			return false
	return true

func _gate_structure(gate: Node, where: String) -> void:
	var tint: Node = gate.get_node_or_null("ColorRect")
	_check(where + ": ColorRect type + exact 52x72 offsets",
		tint is ColorRect and tint.offset_left == -26.0 and tint.offset_top == -36.0
		and tint.offset_right == 26.0 and tint.offset_bottom == 36.0)
	var lbl: Node = gate.get_node_or_null("TypeLabel")
	_check(where + ": TypeLabel type + geometry + font",
		lbl is Label and lbl.offset_left == -26.0 and lbl.offset_top == -10.0
		and lbl.offset_right == 26.0 and lbl.offset_bottom == 8.0
		and lbl.get_theme_font_size("font_size") == 10)
	var cs: CollisionShape2D = gate.get_node_or_null("CollisionShape2D")
	_check(where + ": collision RectangleShape2D (52,72) untouched",
		cs != null and cs.shape is RectangleShape2D and cs.shape.size == Vector2(52, 72))
	var rim: Node = gate.get_node_or_null("Rim")
	var body: Node = gate.get_node_or_null("Body")
	_check(where + ": oval portal decor (48-point rim, filled body)",
		rim is Line2D and rim.points.size() == 48 and body is Polygon2D and body.polygon.size() == 96)

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if scene.get_node_or_null("Player") != null and t > 0.4:
				p = scene.get_node("Player")
				_check("hub boot", scene.current_area.name == "Hub")
				scene.enter_overworld() # #346: dungeon entrances live in the overworld
				var normal: Node = scene.current_area.get_node_or_null("GateNormal")
				var red: Node = scene.current_area.get_node_or_null("GateRed")
				_check("overworld: both gates present", normal != null and red != null)
				_gate_structure(normal, "GateNormal")
				_gate_structure(red, "GateRed")
				_check("families: GateNormal rolled NORMAL tint blue (script-driven)",
					_color_eq(normal.get_node("ColorRect").color, Color(0.15, 0.6, 0.9)))
				_check("families: GateRed rolled NORMAL tint blue (forced-0.0 fixture)",
					_color_eq(red.get_node("ColorRect").color, Color(0.15, 0.6, 0.9)))
				var g: Gate = normal
				g._on_body_entered(p)
				phase = 1; t = 0
		1:
			if t > 0.4:
				_check("dungeon boot: real normal-gate entry into DungeonA",
					scene.current_area.name == "DungeonA")
				var portal: Node = scene.current_area.get_node_or_null("ExitPortal")
				_check("portal present", portal != null)
				if portal != null:
					var tint: Node = portal.get_node_or_null("ColorRect")
					_check("portal: ColorRect type + exact 52x72 offsets",
						tint is ColorRect and tint.offset_left == -26.0 and tint.offset_top == -36.0
						and tint.offset_right == 26.0 and tint.offset_bottom == 36.0)
					var lbl: Node = portal.get_node_or_null("StateLabel")
					_check("portal: StateLabel type + text EXIT",
						lbl is Label and lbl.text == "EXIT")
					var cs: CollisionShape2D = portal.get_node_or_null("CollisionShape2D")
					_check("portal: collision RectangleShape2D (52,72) untouched",
						cs != null and cs.shape is RectangleShape2D and cs.shape.size == Vector2(52, 72))
					var arrow: Node = portal.get_node_or_null("ExitArrow")
					_check("portal: ExitArrow UP arrow lavender",
						arrow is Polygon2D and _poly_eq(arrow.polygon, EXIT_ARROW)
						and _color_eq(arrow.color, LAVENDER))
					_check("portal: unlocked purple tint (script-driven)",
						_color_eq(tint.color, Color(0.5, 0.2, 0.8)))
				if fails == 0:
					print("[91] ALL PASS")
				print("[91] DONE fails=", fails)
				quit(1 if fails > 0 else 0)
	return false
