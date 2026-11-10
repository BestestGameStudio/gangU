extends SceneTree
## #137 acceptance driver (headless, production composition via main.tscn).
## Proves the wizard AnimatedSprite2D integration within its exact boundary:
##   r16        - CollisionShape2D still carries CircleShape2D radius 16.0
##                (collision byte-untouched by the integration)
##   sprite     - WizardSprite AnimatedSprite2D present in the PLAYER subtree,
##                legacy Polygon2D Body hidden (DECOR LEGS: both FAIL on
##                pre-sprite main, where no WizardSprite exists and the Body
##                dart is visible - the meaningful negative)
##   frames     - SpriteFrames carries exactly idle_<dir>/walk_<dir> for
##                down/left/right/up: idle 1 frame, walk 4 frames, looped
##   facing     - real movement input drives facing: right/up/left walks
##                select walk_<dir>; releasing input keeps the LAST facing
##                via idle_<dir>; an exact right+up diagonal resolves
##                vertically (walk_up); at rest the facing is idle_down
##   upright    - sprite global_rotation stays 0 while the player node
##                rotates to aim (aim/cast contract unchanged)
##   contrast   - sprite silhouette: walk_down frame is opaque over its body
##                and its robe pixel reads blue-family (b>r, b>g); the three
##                dungeon enemies read green (g>b, #177 Mustache Warrior art)
##   aim tint   - AimIndicator is blue-family (was orange-red), same triangle
##                at (22,0)
##   no overhead bar - the SpellCaster draws nothing above the player for
##                cooldowns (the HUD slot rows own cooldown display)
##   aim track  - player rotation follows the cursor, warped mouse positions
##                produce the expected angles
##   hub boot   - production hub boots with the player present
##   dungeon    - real normal-gate entry: shared player arrives in DungeonA
## Gate use follows the test9 direct _on_body_entered idiom. Movement legs
## use real Input.action_press physics frames.

const DIRS: Array[StringName] = [&"down", &"left", &"right", &"up"]

var scene: Node
var p: CharacterBody2D
var sprite: AnimatedSprite2D
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

func _frame_color(tex: Texture2D, uv: Vector2i) -> Color:
	var img := tex.get_image()
	return img.get_pixel(clampi(uv.x, 0, img.get_width() - 1), clampi(uv.y, 0, img.get_height() - 1))

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if scene.get_node_or_null("Player") != null and t > 0.3:
				p = scene.get_node("Player")
				_check("hub boot: player present in Hub", scene.area_loader.current_area.name == "Hub")
				var cs: CollisionShape2D = p.get_node("CollisionShape2D")
				_check("r16: collision circle radius unchanged at 16.0",
					cs.shape is CircleShape2D and is_equal_approx(cs.shape.radius, 16.0))
				sprite = p.get_node_or_null("WizardSprite")
				_check("sprite: WizardSprite AnimatedSprite2D present in PLAYER subtree",
					sprite != null and sprite is AnimatedSprite2D)
				var body: Polygon2D = p.get_node("Body")
				_check("sprite: legacy Body dart hidden once sprite exists", not body.visible)
				var nose: Polygon2D = p.get_node("NoseEdge")
				_check("sprite: NoseEdge dart accent hidden once sprite exists", not nose.visible)
				if sprite == null:
					print("[89] DONE fails=", fails)
					quit(1 if fails > 0 else 0)
					return true
				var sf := sprite.sprite_frames
				var frames_ok: bool = sf != null and sf.get_animation_names().size() == 8
				if frames_ok:
					for d in DIRS:
						var idle := StringName("idle_" + String(d))
						var walk := StringName("walk_" + String(d))
						if not sf.has_animation(idle) or sf.get_frame_count(idle) != 1:
							frames_ok = false
						if not sf.has_animation(walk) or sf.get_frame_count(walk) != 4:
							frames_ok = false
				_check("frames: idle_<dir>/walk_<dir> x4, idle 1 frame, walk 4", frames_ok)
				_check("facing: at rest plays idle_down",
					sprite.animation == &"idle_down" and sprite.is_playing())
				var aim: Polygon2D = p.get_node("AimIndicator")
				_check("aim tint: AimIndicator blue-family, triangle at (22,0)",
					_blue_family(aim.color) and aim.position == Vector2(22, 0)
					and aim.polygon.size() == 3)
				var caster := p.get_node("SpellCaster")
				_check("no overhead bar: SpellCaster draws no cooldown bar",
					caster.get_node_or_null("CooldownBarBG") == null
					and caster.get_node_or_null("CooldownBarFill") == null
					and caster.find_children("*", "CanvasItem").is_empty())
				Input.action_press("move_right")
				phase = 1; t = 0
		1:
			if t > 0.3:
				_check("facing: moving right plays walk_right", sprite.animation == &"walk_right")
				Input.action_release("move_right")
				phase = 2; t = 0
		2:
			if t > 0.3:
				_check("facing: last facing retained while idle (idle_right)",
					sprite.animation == &"idle_right" and p.velocity == Vector2.ZERO)
				Input.action_press("move_up")
				phase = 3; t = 0
		3:
			if t > 0.3:
				_check("facing: moving up plays walk_up", sprite.animation == &"walk_up")
				Input.action_press("move_right")  # exact diagonal: x == y
				phase = 4; t = 0
		4:
			if t > 0.3:
				_check("facing: exact right+up diagonal resolves vertically (walk_up)",
					sprite.animation == &"walk_up")
				Input.action_release("move_up")
				Input.action_release("move_right")
				Input.action_press("move_left")
				phase = 5; t = 0
		5:
			if t > 0.3:
				_check("facing: moving left plays walk_left", sprite.animation == &"walk_left")
				Input.action_release("move_left")
				# Aim rotation contract: cursor right of player => angle ~0,
				# sprite art itself stays upright.
				Input.warp_mouse(Vector2(900, 480))
				phase = 6; t = 0
		6:
			if t > 0.2:
				# Same world-cursor input player.gd aims at (camera transform
				# included): rotation must equal the angle to the actual cursor.
				var expected := p.global_position.direction_to(p.get_global_mouse_position()).angle()
				_check("aim track: rotation faces cursor (cursor right)",
					absf(wrapf(p.rotation - expected, -PI, PI)) < 0.05)
				_check("upright: sprite global_rotation is 0 under aim rotation",
					absf(sprite.global_rotation) < 0.001)
				Input.warp_mouse(Vector2(576, 80))
				phase = 7; t = 0
		7:
			if t > 0.2:
				var expected := p.global_position.direction_to(p.get_global_mouse_position()).angle()
				_check("aim track: rotation faces cursor (cursor top-center)",
					absf(wrapf(p.rotation - expected, -PI, PI)) < 0.05)
				_check("upright: sprite still upright after re-aim",
					absf(sprite.global_rotation) < 0.001)
				scene.area_loader.enter_overworld() # #346: dungeon entrances live in the overworld
				var g: Gate = scene.area_loader.current_area.get_node("GateNormal")
				g._on_body_entered(p)
				phase = 8; t = 0
		8:
			if t > 0.4:
				_check("dungeon boot: real normal-gate entry into DungeonA",
					scene.area_loader.current_area.name == "DungeonA")
				_check("dungeon: shared player still carries the wizard sprite",
					p.get_node_or_null("WizardSprite") == sprite)
				var walk_down := sprite.sprite_frames.get_frame_texture(&"walk_down", 0)
				var img := walk_down.get_image()
				var opaque := 0
				for y in img.get_height():
					for x in img.get_width():
						if img.get_pixel(x, y).a > 0.5:
							opaque += 1
				_check("contrast: walk_down silhouette opaque over its body",
					opaque > 300)
				_check("contrast: sprite robe pixel is blue-family (b>r, b>g)",
					_blue_family(_frame_color(walk_down, Vector2i(14, 34))))
				# #392: DungeonA also holds slimes (their own sheet); this leg is the Mustache Warrior art.
				var enemies := get_nodes_in_group("enemies").filter(func(n): return n.scene_file_path == "res://scenes/enemy.tscn")
				var green_ok: bool = enemies.size() == 3
				for e in enemies:
					# #177: the enemy visual is the green Mustache Warrior
					# AnimatedSprite2D ("Sprite"); it must read green (g > b)
					# against the blue player robe.
					var vis := e.get_node_or_null("Sprite") as AnimatedSprite2D
					if vis == null or vis.sprite_frames == null:
						green_ok = false
						continue
					var etex := vis.sprite_frames.get_frame_texture(&"idle", 0) as AtlasTexture
					if etex == null:
						green_ok = false
						continue
					var ec: Color = etex.atlas.get_image().get_pixelv(
						Vector2i(etex.region.position) + Vector2i(32, 30))
					if not (ec.a > 0.5 and ec.g > ec.b):
						green_ok = false
				_check("contrast: 3 green warrior enemies (g>b) vs blue wizard robe", green_ok)
				if fails == 0:
					print("[89] ALL PASS")
				print("[89] DONE fails=", fails)
				quit(1 if fails > 0 else 0)
	return false
