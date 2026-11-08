extends SceneTree
## #263 harness: Mana Shot and Fire Ball projectiles are bigger, slower and
## carry an obvious glow + trail. Visual knobs never touch collision: the hit
## shape still equals spell.radius. Spells without the new fields look and
## behave exactly as before. Run headless:
##   godot --headless -s scripts/test263_projectile_visibility.gd

var _checks := 0
var _failures := 0

func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if ok:
		print("PASS: %s" % msg)
	else:
		_failures += 1
		print("FAIL: %s" % msg)

func _spawn(spell: Spell) -> Projectile:
	var p: Projectile = load("res://scenes/projectile.tscn").instantiate()
	p.setup(spell, Vector2.RIGHT, null)
	root.add_child(p)
	return p

func _initialize() -> void:
	print("test263: projectile visibility (#263)")
	var mana: Spell = load("res://resources/spells/mana_shot.tres")
	var fire: Spell = load("res://resources/spells/fire_ball.tres")

	# --- tuning: slower than the old values (mana 1100, fire 900) -----------
	_check(mana.projectile_speed < 1100.0, "mana shot slower than 1100 (now %s)" % mana.projectile_speed)
	_check(fire.projectile_speed < 900.0, "fire ball slower than 900 (now %s)" % fire.projectile_speed)
	_check(mana.range / mana.projectile_speed >= 0.9, "mana shot flight time >= 0.9s (was ~0.58s)")
	_check(fire.range / fire.projectile_speed >= 0.75, "fire ball flight time >= 0.75s (was ~0.47s)")
	_check(mana.glow and mana.trail_length > 0, "mana shot has glow + trail")
	_check(fire.glow and fire.trail_length > 0, "fire ball has glow + trail")

	var warmup := _spawn(fire)
	await process_frame
	warmup.queue_free()

	# --- bigger on screen; collision unchanged by visual_scale --------------
	var old_px := {"Mana Shot": 3.0 / 16.0, "Fire Ball": 9.0 / 16.0}
	for sp in [mana, fire]:
		var p := _spawn(sp)
		var spr := p.get_node_or_null("Sprite") as AnimatedSprite2D
		_check(spr != null, "%s has its art sprite" % sp.spell_name)
		if spr != null:
			_check(spr.scale.x >= old_px[sp.spell_name] * 1.75,
				"%s sprite >= 1.75x its old size (%.3f vs %.3f)" % [sp.spell_name, spr.scale.x, old_px[sp.spell_name]])
		var shape := p.get_node("CollisionShape2D").shape as CircleShape2D
		_check(is_equal_approx(shape.radius, sp.radius), "%s collision radius == spell.radius" % sp.spell_name)
		_check(p.get_node_or_null("Glow") is Polygon2D, "%s has a Glow halo" % sp.spell_name)
		var trail := p.get_node_or_null("Trail") as Line2D
		_check(trail != null, "%s has a Trail" % sp.spell_name)
		var s0: float = spr.scale.x if spr != null else 0.0
		var glow0: float = (p.get_node("Glow") as Node2D).scale.x
		for i in 8:
			await physics_frame
		if not is_instance_valid(p):
			_check(false, "%s alive after 8 physics frames" % sp.spell_name)
			continue
		_check(trail != null and trail.get_point_count() >= 2 and trail.get_point_count() <= sp.trail_length,
			"%s trail grows and stays capped (%d pts)" % [sp.spell_name, trail.get_point_count() if trail else -1])
		_check(trail != null and trail.top_level, "%s trail is world-space (top_level)" % sp.spell_name)
		_check(spr != null and not is_equal_approx(spr.scale.x, s0), "%s sprite pulses in flight" % sp.spell_name)
		_check(not is_equal_approx((p.get_node("Glow") as Node2D).scale.x, glow0), "%s glow pulses in flight" % sp.spell_name)
		p.queue_free()

	# --- untouched spells keep the old look -----------------------------------
	var bolt: Spell = load("res://resources/spells/placeholder_bolt.tres")
	_check(is_equal_approx(bolt.visual_scale, 1.0) and not bolt.glow and bolt.trail_length == 0,
		"placeholder bolt keeps default visuals")
	var pb := _spawn(bolt)
	_check(pb.get_node_or_null("Glow") == null and pb.get_node_or_null("Trail") == null,
		"placeholder bolt spawns no Glow/Trail")
	var spb := pb.get_node_or_null("Sprite") as AnimatedSprite2D
	_check(spb != null and is_equal_approx(spb.scale.x, bolt.radius / 16.0), "placeholder bolt sprite still radius/16")
	pb.queue_free()
	var orb := _spawn(load("res://resources/spells/warlord_orb.tres"))
	_check(orb.get_node_or_null("Glow") == null and orb.get_node_or_null("Trail") == null,
		"warlord orb spawns no Glow/Trail")
	orb.queue_free()

	print("test263 done: %d checks, %d failures" % [_checks, _failures])
	if _failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if _failures > 0 else 0)
