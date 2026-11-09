extends SceneTree
## #210 harness: supplied sprite art flies on the Fire Ball / Mana Shot /
## Placeholder Bolt projectiles (#289 moved them to spell_upgrades_frames.tres;
## see test289 for that sheet's contract). Visuals only:
## radius, movement, hits and despawn must stay exactly as before, unmapped
## spells keep the code-drawn visuals, and the #177 visual_override hook
## still wins. Run headless:
##   godot --headless --script scripts/test210_spell_projectiles.gd

var _checks := 0
var _failures := 0

func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if ok:
		print("PASS: %s" % msg)
	else:
		_failures += 1
		print("FAIL: %s" % msg)

func _spawn(spell_path: String) -> Projectile:
	var p: Projectile = load("res://scenes/projectile.tscn").instantiate()
	var sp: Spell = load(spell_path)
	p.setup(sp, Vector2.RIGHT, null)
	root.add_child(p)
	return p

func _initialize() -> void:
	print("test210: supplied spell projectile sprites (#210)")

	# --- resource contract -------------------------------------------------
	var frames: SpriteFrames = load("res://resources/sprites/spell_projectiles_frames.tres")
	_check(frames != null, "spell_projectiles_frames.tres loads as SpriteFrames")
	for anim in [&"flame", &"mana", &"bolt"]:
		_check(frames.has_animation(anim), "SpriteFrames has animation '%s'" % anim)
		if frames.has_animation(anim):
			_check(frames.get_frame_count(anim) == 8, "'%s' has 8 frames" % anim)
			_check(frames.get_animation_loop(anim), "'%s' loops" % anim)
			var tex: Texture2D = frames.get_frame_texture(anim, 0)
			_check(tex != null and tex.get_width() == 64 and tex.get_height() == 48,
				"'%s' frame0 is a 64x48 cell" % anim)

	# The first node added to the root has its _ready deferred until the tree
	# settles; warm it up so every spawned projectile below is fully ready.
	var warmup := _spawn("res://resources/spells/fire_ball.tres")
	await process_frame
	warmup.queue_free()

	# --- mapped spells fly the sprite ---------------------------------------
	var cases := {
		"res://resources/spells/fire_ball.tres": &"fire_ball_start",
		"res://resources/spells/mana_shot.tres": &"mana_shot_start",
		"res://resources/spells/placeholder_bolt.tres": &"placeholder_bolt_start",
	}
	for spell_path in cases:
		var p := _spawn(spell_path)
		var sprite := p.get_node_or_null("Sprite") as AnimatedSprite2D
		_check(sprite != null, "%s projectile has a Sprite child" % spell_path.get_file())
		if sprite != null:
			_check(sprite.animation == cases[spell_path] and sprite.is_playing(),
				"%s plays '%s'" % [spell_path.get_file(), cases[spell_path]])
			_check(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
				"%s sprite uses nearest filter (pixel art)" % spell_path.get_file())
		_check(not p.get_node("Dart").visible and not p.get_node("Visual").visible,
			"%s code-drawn Dart/Visual hidden" % spell_path.get_file())
		var shape := p.get_node("CollisionShape2D").shape as CircleShape2D
		_check(is_equal_approx(shape.radius, p.spell.radius),
			"%s collision radius == spell.radius (%s)" % [spell_path.get_file(), p.spell.radius])
		var before: Vector2 = p.global_position
		await physics_frame
		await physics_frame
		if not is_instance_valid(p):
			_check(false, "%s projectile still alive after 2 physics frames" % spell_path.get_file())
		else:
			_check(p.global_position.x > before.x, "%s projectile still moves +X" % spell_path.get_file())
			p.queue_free()

	# --- unmapped spell keeps code-drawn visuals ----------------------------
	var orb := _spawn("res://resources/spells/warlord_orb.tres")
	_check(orb.get_node_or_null("Sprite") == null, "unmapped spell (Warlord Orb) has no Sprite child")
	_check(orb.get_node("Dart").visible and orb.get_node("Visual").visible,
		"unmapped spell keeps visible Dart/Visual")
	orb.queue_free()

	# --- #177 visual_override still wins -------------------------------------
	var o := _spawn("res://resources/spells/fire_ball.tres")
	o.get_parent().remove_child(o)
	o.free()
	var p2: Projectile = load("res://scenes/projectile.tscn").instantiate()
	p2.visual_override = Node2D.new()
	p2.setup(load("res://resources/spells/fire_ball.tres"), Vector2.RIGHT, null)
	root.add_child(p2)
	_check(p2.get_node_or_null("Sprite") == null, "visual_override: no Sprite child added")
	_check(p2.get_node_or_null("VisualOverride") != null, "visual_override: VisualOverride child present")
	p2.queue_free()

	print("test210 done: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
