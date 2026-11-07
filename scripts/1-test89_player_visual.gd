extends SceneTree
## #89 acceptance driver (headless, production composition via main.tscn).
## Proves the player VISUAL restyle within its exact boundary:
##   r16       - CollisionShape2D still carries CircleShape2D radius 16.0
##               (collision byte-untouched by the restyle)
##   hull      - Body polygon is EXACTLY the angular dart hull with the nose
##               at +X, blue-family fill (b > r, b > g)
##   nose edge - NoseEdge accent child present at the nose, light blue
##   aim tint  - AimIndicator is blue-family (was orange-red), same triangle
##               at (22,0)
##   bar tint  - CooldownBarFill is blue-family, BG stays neutral
##   aim track - player rotation follows the cursor (nose = facing edge):
##               warped mouse positions produce the expected angles
##   hub boot  - production hub boots with the player present
##   dungeon   - real normal-gate entry: blue player among three orange
##               enemies (enemy bodies r > b, player b > r)
## The hull/tint legs FAIL on the old base (square Body, red AimIndicator,
## orange fill) - meaningful negative. Gate use follows the test9 direct
## _on_body_entered idiom - NOT real-input movement proof.

const EXPECTED_HULL: Array[Vector2] = [Vector2(20, 0), Vector2(-6, -13), Vector2(-14, -9), Vector2(-9, 0), Vector2(-14, 9), Vector2(-6, 13)]

var scene: Node
var p: CharacterBody2D
var phase := 0
var t := 0.0
var fails := 0

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene

func _check(label: String, ok: bool) -> void:
	if not ok:
		fails += 1
	print("[89] ", label, " -> ", "PASS" if ok else "FAIL")

func _blue_family(c: Color) -> bool:
	return c.b > c.r and c.b > c.g

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if scene.get_node_or_null("Player") != null and t > 0.3:
				p = scene.get_node("Player")
				_check("hub boot: player present in Hub", scene.current_area.name == "Hub")
				var cs: CollisionShape2D = p.get_node("CollisionShape2D")
				_check("r16: collision circle radius unchanged at 16.0",
					cs.shape is CircleShape2D and is_equal_approx(cs.shape.radius, 16.0))
				var body: Polygon2D = p.get_node("Body")
				var hull_ok: bool = body.polygon.size() == EXPECTED_HULL.size()
				for i in mini(body.polygon.size(), EXPECTED_HULL.size()):
					if body.polygon[i] != EXPECTED_HULL[i]:
						hull_ok = false
				_check("hull: Body is EXACTLY the angular dart (nose +X)", hull_ok)
				_check("hull: Body fill is blue-family", _blue_family(body.color))
				var nose: Polygon2D = p.get_node_or_null("NoseEdge")
				_check("nose edge: accent child present and light blue",
					nose != null and _blue_family(nose.color))
				var aim: Polygon2D = p.get_node("AimIndicator")
				_check("aim tint: AimIndicator blue-family, triangle at (22,0)",
					_blue_family(aim.color) and aim.position == Vector2(22, 0)
					and aim.polygon.size() == 3)
				var fill: Polygon2D = p.get_node("SpellCaster/CooldownBarFill")
				_check("bar tint: CooldownBarFill blue-family", _blue_family(fill.color))
				# Aim tracking: cursor right of player => angle ~0, above => ~-PI/2
				Input.warp_mouse(Vector2(900, 480))
				phase = 1; t = 0
		1:
			if t > 0.2:
				# Same world-cursor input player.gd aims at (camera transform
				# included): rotation must equal the angle to the actual cursor.
				var expected := p.global_position.direction_to(p.get_global_mouse_position()).angle()
				_check("aim track: nose faces cursor (cursor right)",
					absf(wrapf(p.rotation - expected, -PI, PI)) < 0.05)
				Input.warp_mouse(Vector2(576, 80))
				phase = 2; t = 0
		2:
			if t > 0.2:
				var expected := p.global_position.direction_to(p.get_global_mouse_position()).angle()
				_check("aim track: nose faces cursor (cursor top-center)",
					absf(wrapf(p.rotation - expected, -PI, PI)) < 0.05)
				var g: Gate = scene.current_area.get_node("GateNormal")
				g._on_body_entered(p)
				phase = 3; t = 0
		3:
			if t > 0.4:
				_check("dungeon boot: real normal-gate entry into DungeonA",
					scene.current_area.name == "DungeonA")
				var enemies := get_nodes_in_group("enemies")
				var orange_ok: bool = enemies.size() == 3
				for e in enemies:
					# Enemy visual is the Spikes Polygon2D on current main (#90);
					# ColorRect is the pre-#90 shape (old-base fallback). Either way
					# the enemy body must read orange (r>b) against the blue player.
					var vis: Node = e.get_node_or_null("Spikes")
					if vis == null:
						vis = e.get_node_or_null("ColorRect")
					if vis == null or not (vis.color.r > vis.color.b):
						orange_ok = false
				_check("contrast: 3 orange enemies (r>b) vs blue player (b>r)",
					orange_ok and _blue_family(p.get_node("Body").color))
				if fails == 0:
					print("[89] ALL PASS")
				print("[89] DONE fails=", fails)
				quit()
	return false
