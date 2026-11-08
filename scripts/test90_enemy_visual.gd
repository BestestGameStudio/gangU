extends SceneTree
## #90 (Graphics B) harness: enemy visual identity - shape-first threat
## readability, visual nodes only in scenes/enemy.tscn. Collision, scripts,
## combat unchanged.
## #177 supersedes the #90 orange Polygon2D silhouette with the Mustache
## Warrior pixel-art sprite (issue #177 art); legs (b)/(c) now assert that
## art instead of the retired polygon.
##
## Legs:
##   (a) collision unchanged: CollisionShape2D circle radius == 13.0.
##   (b) animated sprite: an AnimatedSprite2D "Sprite" with idle/walk
##       animations, nearest filtering, footprint near the r13 body.
##   (c) green warrior family: an opaque idle-frame pixel reads green
##       (g > r, g > b) - distinct from the blue wizard player.
##   (d) square language removed: NO ColorRect child (distinct from the
##       player's square and pickup squares).
##   (e) script attachment unchanged: still res://scripts/enemy.gd.
##   (f) mounts clean: instantiates, _ready runs, hp == 30.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[90] ", name, " -> PASS")
	else:
		failures += 1
		print("[90] ", name, " -> FAIL")

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	_check(scene != null, "(0) enemy.tscn loads")
	if scene == null:
		print("[90] DONE failures=", failures)
		quit(failures)
		return
	var e: Node2D = scene.instantiate() as Node2D
	root.add_child(e)

	# (a) collision unchanged.
	var cs: CollisionShape2D = e.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var radius: float = -1.0
	if cs != null and cs.shape is CircleShape2D:
		radius = (cs.shape as CircleShape2D).radius
	_check(is_equal_approx(radius, 13.0), "(a) collision circle radius unchanged (13.0, got %.2f)" % radius)

	# (b) animated sprite (#177 Mustache Warrior).
	var spr := e.get_node_or_null("Sprite") as AnimatedSprite2D
	var frames_ok := spr != null and spr.sprite_frames != null \
		and spr.sprite_frames.has_animation(&"idle") and spr.sprite_frames.has_animation(&"walk")
	_check(frames_ok, "(b) AnimatedSprite2D 'Sprite' with idle/walk animations")
	_check(spr != null and spr.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "(b) nearest filter (crisp pixel art)")
	var feet_ok := false
	if spr != null:
		# Cell is 64x48, centered, feet on row 44 -> feet sit at y = pos.y + 20.
		var feet_y: float = spr.position.y + 20.0 * spr.scale.y
		feet_ok = absf(feet_y - 13.0) <= 3.0
	_check(feet_ok, "(b) sprite feet sit on the r13 body footprint")

	# (c) green warrior family, sampled from the first idle frame's opaque pixels.
	var col_ok := false
	if frames_ok:
		var tex := spr.sprite_frames.get_frame_texture(&"idle", 0) as AtlasTexture
		if tex != null:
			var img := tex.atlas.get_image()
			var r := tex.region
			var sum := Vector3.ZERO
			var n := 0
			for y in range(int(r.position.y), int(r.end.y)):
				for x in range(int(r.position.x), int(r.end.x)):
					var c: Color = img.get_pixel(x, y)
					if c.a > 0.5:
						sum += Vector3(c.r, c.g, c.b)
						n += 1
			if n > 120:
				var avg := sum / float(n)
				col_ok = avg.y > avg.x and avg.y > avg.z
	_check(col_ok, "(c) green warrior family (avg g > r, g > b)")

	# (d) square language removed.
	var has_colorrect := false
	for c in e.get_children():
		if c is ColorRect:
			has_colorrect = true
	_check(not has_colorrect, "(d) no ColorRect child (square language removed)")

	# (e) script attachment unchanged.
	var s: Script = e.get_script()
	_check(s != null and s.resource_path == "res://scripts/enemy.gd", "(e) script still res://scripts/enemy.gd")

	# (f) mounts clean (_ready defers to the first frame in a SceneTree harness).
	await process_frame
	_check(e.get("hp") == 30, "(f) mounts clean, hp 30 after ready")

	print("[90] DONE failures=", failures)
	quit(failures)
