extends SceneTree
## #174 harness: the Beast boss (sheet attached to #174).
## Run: godot --headless --path . --script res://scripts/test174_beast_boss.gd
##
## The boss is not placed in an area yet (which room it lives in is a human
## decision), so there are no hub / production-flow legs here.
##
## Legs:
##   (A) sheet + SpriteFrames: every animation present with the expected
##       frame count / loop flag; packed sheet 528x336; an idle body pixel
##       reads the sheet's green.
##   (B) beast_boss.tscn: Enemy + definition (hp 340) + EnemyBehaviorBeast,
##       2.5x nearest-filtered sprite, green telegraph + HP bar; idles on
##       mount; art faces LEFT (moving right mirrors it); a hit while chasing
##       plays hurt; death frees the Enemy and leaves a corpse playing "death".
##   (C) attacks (REAL frames, collisions off like #99/#173): far -> lunge
##       wind-up (line telegraph + glow + windup_bite) -> "bite" dash closes
##       the gap and hits once; close -> scream wind-up (ring + windup_aoe) ->
##       "aoe" ring hits once.
##   (D) phase change at <= 50% HP: STUN ("stun", no attacks) for STUN_TIME,
##       then enraged: the lunge chains into a second lunge, and the scream
##       uses the wider ring.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[174] ", name, " -> PASS")
	else:
		failures += 1
		print("[174] ", name, " -> FAIL")

func _physics(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	await _leg_frames()
	await _leg_scene()
	await _leg_attacks()
	await _leg_phase()
	print("[174] DONE failures=", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(failures)

# (A) -----------------------------------------------------------------------
func _leg_frames() -> void:
	var tex: Texture2D = load("res://assets/sprites/beast_boss.png")
	_check(tex != null and tex.get_width() == 528 and tex.get_height() == 336,
		"(A) packed sheet loads at 528x336")
	var sf: SpriteFrames = load("res://resources/sprites/beast_boss_frames.tres")
	_check(sf != null, "(A) SpriteFrames loads")
	if sf == null or tex == null:
		return
	var want := {
		&"idle": [6, true], &"walk": [7, true], &"attack": [4, false],
		&"windup_bite": [4, false], &"bite": [4, false],
		&"windup_aoe": [3, false], &"aoe": [5, false], &"hurt": [4, false],
		&"stun": [4, true], &"death": [11, false],
	}
	for anim in want:
		var ok: bool = sf.has_animation(anim) \
			and sf.get_frame_count(anim) == want[anim][0] \
			and sf.get_animation_loop(anim) == want[anim][1]
		_check(ok, "(A) %s: %d frames, loop=%s" % [anim, want[anim][0], want[anim][1]])
	# Idle frame 0: count opaque green pixels (g dominant) in the cell.
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var green := 0
	var opaque := 0
	for y in 48:
		for x in 48:
			var c := img.get_pixel(x, y)
			if c.a > 0.9:
				opaque += 1
				if c.g > c.r and c.g > c.b:
					green += 1
	_check(opaque > 150 and green * 2 > opaque, "(A) idle frame is mostly green (%d/%d)" % [green, opaque])

# (B) -----------------------------------------------------------------------
func _leg_scene() -> void:
	var scene: PackedScene = load("res://scenes/beast_boss.tscn")
	_check(scene != null, "(B) beast_boss.tscn loads")
	if scene == null:
		return
	var world := Node2D.new()
	root.add_child(world)
	var b := scene.instantiate() as Enemy
	_check(b != null, "(B) root is an Enemy")
	if b == null:
		world.queue_free()
		return
	b.position = Vector2(300, 300)
	world.add_child(b)
	await process_frame
	_check(b.max_hp == 340 and b.hp == 340, "(B) definition applied (hp 340, PLACEHOLDER)")
	_check(b._behavior is EnemyBehaviorBeast, "(B) beast behavior slotted via the #99 seam")
	_check(b.sprite != null and b.sprite.scale == Vector2(2.5, 2.5) \
		and b.sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "(B) 2.5x nearest-filtered sprite")
	var tele := b.get_node_or_null("Telegraph") as BossTelegraph
	_check(tele != null and tele.warn_color.g > 0.9 and tele.warn_color.b < 0.4, "(B) acid-green telegraph node")
	_check(b.get_node_or_null("HealthBar") is BossHealthBar, "(B) health bar node")
	_check(b.sprite != null and b.sprite.animation == &"idle" and b.sprite.is_playing(), "(B) idles on mount (no player)")
	if b.sprite == null:
		world.queue_free()
		return
	b.sprite.face(1.0)
	_check(b.sprite.flip_h, "(B) art faces left: facing right mirrors it")
	b.sprite.face(-1.0)
	_check(not b.sprite.flip_h, "(B) facing left keeps the art as drawn")
	b.apply_damage(5)
	_check(b.sprite.animation == &"hurt", "(B) a hit while chasing plays hurt")
	b.apply_damage(9999)
	await process_frame
	await process_frame
	_check(not is_instance_valid(b), "(B) boss frees itself on death (contract unchanged)")
	var corpse: AnimatedSprite2D = null
	for c in get_nodes_in_group(&"enemy_corpses"):
		if c.get_parent() == world:
			corpse = c
	_check(corpse != null and corpse.animation == &"death" and corpse.is_playing(), "(B) corpse plays the 11-frame death")
	world.queue_free()
	await process_frame

# (C) -----------------------------------------------------------------------
func _arena(player_offset: Vector2) -> Array:
	var world := Node2D.new()
	root.add_child(world)
	var p: Player = load("res://scenes/player.tscn").instantiate()
	p.position = Vector2(500, 300) + player_offset
	p.collision_layer = 0
	p.collision_mask = 0
	world.add_child(p)
	var b: Enemy = load("res://scenes/beast_boss.tscn").instantiate()
	b.position = Vector2(500, 300)
	b.collision_layer = 0
	b.collision_mask = 0
	world.add_child(b)
	return [world, p, b]

func _close(a: Array) -> void:
	(a[0] as Node).queue_free()
	await process_frame

## Runs one attack cycle; returns what was observed.
func _observe(a: Array, frames: int) -> Dictionary:
	var p: Player = a[1]
	var b: Enemy = a[2]
	var beh := b._behavior as EnemyBehaviorBeast
	var tele := b.get_node("Telegraph") as BossTelegraph
	var start: Vector2 = b.global_position
	var seen := {"line": false, "ring": false, "glow": false, "windup_anim": &"", "attack_anim": &"",
		"live_ring": false, "lunges": 0, "moved": 0.0, "radius": 0.0, "hp": p.hp, "states": []}
	for i in frames:
		await physics_frame
		if not (beh.state in seen["states"]):
			seen["states"].append(beh.state)
		if beh.state == EnemyBehaviorBeast.State.WINDUP:
			seen["line"] = seen["line"] or tele.mode == BossTelegraph.Mode.LINE
			seen["ring"] = seen["ring"] or tele.mode == BossTelegraph.Mode.RING
			seen["glow"] = seen["glow"] or b.sprite.self_modulate != Color.WHITE
			if seen["windup_anim"] == &"":
				seen["windup_anim"] = b.sprite.animation
		if beh.state == EnemyBehaviorBeast.State.LUNGE or beh.state == EnemyBehaviorBeast.State.SCREAM:
			seen["attack_anim"] = b.sprite.animation
		if beh.state == EnemyBehaviorBeast.State.SCREAM and tele.mode == BossTelegraph.Mode.RING and tele._active:
			seen["live_ring"] = true
			seen["radius"] = tele._radius
		seen["lunges"] = maxi(seen["lunges"], beh._lunges)
		seen["moved"] = maxf(seen["moved"], b.global_position.distance_to(start))
		if beh.state == EnemyBehaviorBeast.State.RECOVER:
			break
	seen["hp"] = p.hp
	return seen

func _leg_attacks() -> void:
	# Lunge: far range, boss walk speed 0 so only the dash moves it.
	var a := _arena(Vector2(220, 0))
	await process_frame
	(a[2] as Enemy).speed = 0.0
	(a[2] as Enemy).contact_range = 0.0 # isolate the lunge damage
	var s := await _observe(a, 240)
	_check(s["line"] and s["glow"], "(C) lunge wind-up: line telegraph + glow")
	_check(s["windup_anim"] == &"windup_bite", "(C) lunge wind-up plays windup_bite")
	_check(s["attack_anim"] == &"bite", "(C) lunge plays bite")
	_check(s["moved"] > 150.0, "(C) the lunge dashes toward the player (moved %.0f)" % s["moved"])
	_check(s["hp"] == 100 - EnemyBehaviorBeast.LUNGE_DAMAGE, "(C) the bite hits once (hp %d)" % s["hp"])
	_check(EnemyBehaviorBeast.State.CHASE in s["states"] and EnemyBehaviorBeast.State.RECOVER in s["states"],
		"(C) CHASE -> WINDUP -> LUNGE -> RECOVER")
	await _close(a)

	# Scream: close range.
	a = _arena(Vector2(70, 0))
	await process_frame
	(a[2] as Enemy).speed = 0.0
	(a[2] as Enemy).contact_range = 0.0
	s = await _observe(a, 240)
	_check(s["ring"] and s["windup_anim"] == &"windup_aoe", "(C) scream wind-up: ring telegraph + windup_aoe")
	_check(s["attack_anim"] == &"aoe" and s["live_ring"], "(C) scream plays aoe with the in-engine ring")
	_check(s["hp"] == 100 - EnemyBehaviorBeast.SCREAM_DAMAGE, "(C) one scream hit (hp %d)" % s["hp"])
	await _close(a)

# (D) -----------------------------------------------------------------------
func _leg_phase() -> void:
	var a := _arena(Vector2(260, 0))
	var b: Enemy = a[2]
	await process_frame
	b.speed = 0.0
	b.contact_range = 0.0
	var beh := b._behavior as EnemyBehaviorBeast
	_check(not beh.phase_two and not beh.is_enraged(b), "(D) starts in phase one")
	b.apply_damage(b.max_hp / 2) # exactly 50%
	await _physics(2)
	_check(beh.phase_two and beh.state == EnemyBehaviorBeast.State.STUN, "(D) <= 50% HP: phase change -> STUN")
	_check(b.sprite.animation == &"stun" and b.sprite.is_playing(), "(D) stun animation plays")
	await _physics(int(EnemyBehaviorBeast.STUN_TIME * 60.0) - 10)
	_check(beh.state == EnemyBehaviorBeast.State.STUN and (a[1] as Player).hp == 100, "(D) no attacks while stunned")
	await _physics(20)
	_check(beh.state == EnemyBehaviorBeast.State.CHASE, "(D) recovers to CHASE after the stun")
	var s := await _observe(a, 300)
	_check(s["lunges"] == 2, "(D) enraged lunge chains into a second lunge (got %d)" % s["lunges"])
	_check(b.get_node("HealthBar")._ratio <= 0.5, "(D) HP bar in its enraged range")
	await _close(a)

	a = _arena(Vector2(70, 0))
	b = a[2]
	await process_frame
	b.speed = 0.0
	b.contact_range = 0.0
	b.apply_damage(b.max_hp / 2 + 1)
	beh = b._behavior as EnemyBehaviorBeast
	await _physics(int(EnemyBehaviorBeast.STUN_TIME * 60.0) + 10)
	s = await _observe(a, 240)
	_check(is_equal_approx(s["radius"], EnemyBehaviorBeast.SCREAM_RADIUS_ENRAGED), "(D) enraged scream uses the wider ring (%.0f)" % s["radius"])
	_check(s["hp"] == 100 - EnemyBehaviorBeast.SCREAM_DAMAGE, "(D) enraged scream hits once (hp %d)" % s["hp"])
	await _close(a)
