extends SceneTree
## #173 harness: the Head boss (sheet attached to #173) in the new boss-gate
## arena DungeonC.
## Run: godot --headless --path . --script res://scripts/test173_head_boss.gd
##
## Legs:
##   (A) sheet + SpriteFrames: every animation present with the expected
##       frame count / loop flag; packed sheet 528x336; idle skin pixel reads
##       the sheet's pale flesh tone.
##   (B) head_boss.tscn: Enemy + definition (hp 320) + EnemyBehaviorHead,
##       3x nearest-filtered sprite, crimson telegraph + HP bar; idles on
##       mount; walk art faces LEFT (moving right mirrors it); a hit while
##       chasing plays hurt; death frees the Enemy and leaves a corpse that
##       plays "death".
##   (C) overworld (#346; was the hub): a gate (GateBoss, BOSS type, violet,
##       "BOSS") beside GateNormal / GateRed, targeting scenes/dungeon_c.tscn.
##   (D) PRODUCTION flow (main.tscn): GateBoss -> DungeonC spawns the Head
##       boss immediately (no mobs) wired to the Player; the exit portal is
##       LOCKED while it lives (entry ignored), unlocks when it dies, and
##       returns to the hub. Kills are synthetic apply_damage calls.
##   (E) attacks (REAL frames, collisions off like #99/#177): far -> volley
##       wind-up (cone + glow + windup_projectile) -> "projectile" fires
##       >= 5 crimson bolts; close -> pulse wind-up (ring) -> "aoe" ring hits.
##   (F) phase change at <= 50% HP: STUN ("stun" anim, no attacks) for
##       STUN_TIME, then enraged: two volley waves (>= 14 bolts) and a
##       double pulse.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[173] ", name, " -> PASS")
	else:
		failures += 1
		print("[173] ", name, " -> FAIL")

func _physics(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	await _leg_frames()
	await _leg_scene()
	await _leg_hub()
	await _leg_production()
	await _leg_attacks()
	await _leg_phase()
	print("[173] DONE failures=", failures)
	quit(failures)

# (A) -----------------------------------------------------------------------
func _leg_frames() -> void:
	var tex: Texture2D = load("res://assets/sprites/head_boss.png")
	_check(tex != null and tex.get_width() == 528 and tex.get_height() == 336,
		"(A) packed sheet loads at 528x336")
	var sf: SpriteFrames = load("res://resources/sprites/head_boss_frames.tres")
	_check(sf != null, "(A) SpriteFrames loads")
	if sf == null:
		return
	var want := {
		&"idle": [6, true], &"walk": [7, true], &"attack": [4, false],
		&"windup_projectile": [4, false], &"projectile": [4, false],
		&"windup_aoe": [4, false], &"aoe": [4, false], &"hurt": [4, false],
		&"stun": [4, true], &"death": [11, false],
	}
	for anim in want:
		var ok: bool = sf.has_animation(anim) \
			and sf.get_frame_count(anim) == want[anim][0] \
			and sf.get_animation_loop(anim) == want[anim][1]
		_check(ok, "(A) %s: %d frames, loop=%s" % [anim, want[anim][0], want[anim][1]])
	# Idle frame 0, a forehead pixel: pale flesh (r high, r > g > 100).
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var c := img.get_pixel(24, 26)
	_check(c.a > 0.9 and c.r > 0.75 and c.r > c.g and c.g > 0.5, "(A) idle forehead reads flesh tone (%s)" % c)

# (B) -----------------------------------------------------------------------
func _leg_scene() -> void:
	var scene: PackedScene = load("res://scenes/head_boss.tscn")
	_check(scene != null, "(B) head_boss.tscn loads")
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
	_check(b.max_hp == 320 and b.hp == 320, "(B) definition applied (hp 320, PLACEHOLDER)")
	_check(b._behavior is EnemyBehaviorHead, "(B) head behavior slotted via the #99 seam")
	_check(b.sprite != null and b.sprite.scale == Vector2(3, 3) \
		and b.sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "(B) 3x nearest-filtered sprite")
	var tele := b.get_node_or_null("Telegraph") as BossTelegraph
	_check(tele != null and tele.warn_color.r > 0.9 and tele.warn_color.g < 0.4, "(B) crimson telegraph node")
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
## #346: the dungeon entrances moved from the hub to the overworld; the
## leg's variable keeps its old name, the scene is the overworld.
func _leg_hub() -> void:
	var hub: Node = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(hub)
	await process_frame
	var gates: Array = []
	for c in hub.get_children():
		if c is Gate and (c as Gate).gate_type != Gate.GateType.TRAVEL:
			gates.append(c)
	_check(gates.size() == 7, "(C) overworld has seven dungeon entrances (got %d; Beast, Defense and Maze entrances integrated)" % gates.size())
	_check(hub.get_node_or_null("GateGenerated") is Gate, "(C) GateGenerated present (#185)")
	var maze_gate := hub.get_node_or_null("GateMaze") as Gate
	_check(maze_gate != null and maze_gate in gates and maze_gate.target_dungeon != null
		and maze_gate.target_dungeon.resource_path == "res://scenes/dungeon_maze.tscn",
		"(C) the seventh entrance is GateMaze -> dungeon_maze.tscn (#367)")
	var g := hub.get_node_or_null("GateBoss") as Gate
	_check(g != null and g.gate_type == Gate.GateType.BOSS, "(C) GateBoss is a BOSS gate")
	if g != null:
		_check(g.target_dungeon != null and g.target_dungeon.resource_path == "res://scenes/dungeon_c.tscn",
			"(C) GateBoss targets DungeonC")
		_check((g.get_node("TypeLabel") as Label).text == "BOSS", "(C) gate label reads BOSS")
		var tint: Color = (g.get_node("ColorRect") as ColorRect).color
		_check(tint == Gate.BOSS_TINT and tint != Gate.RED_TINT and tint != Gate.NORMAL_TINT, "(C) distinct violet tint")
	_check(hub.get_node_or_null("GateNormal") is Gate and hub.get_node_or_null("GateRed") is Gate, "(C) GateNormal / GateRed unchanged")
	hub.queue_free()
	await process_frame

# (D) -----------------------------------------------------------------------
func _leg_production() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var p: Player = scene.get_node("Player")
	scene.area_loader.enter_overworld() # #346
	var gate := scene.area_loader.current_area.get_node_or_null("GateBoss") as Gate
	_check(gate != null, "(D) production overworld mounts GateBoss")
	if gate == null:
		return
	gate._on_body_entered(p)
	await _physics(6)
	var area: Node = scene.area_loader.current_area
	_check(area.name == "DungeonC", "(D) GateBoss enters DungeonC (area=%s)" % area.name)
	var bosses := get_nodes_in_group(&"boss")
	var boss: Enemy = bosses[0] if bosses.size() == 1 else null
	_check(boss != null and boss.get_parent() == area and boss._behavior is EnemyBehaviorHead,
		"(D) the Head boss spawns on entry (bosses=%d)" % bosses.size())
	var mobs := 0
	for e in get_nodes_in_group(&"enemies"):
		if e != boss:
			mobs += 1
	_check(mobs == 0, "(D) boss arena only: no mobs (got %d)" % mobs)
	_check(boss != null and boss._player == p, "(D) boss wired to the production Player")
	var obj := area.get_node_or_null("DungeonObjective") as DungeonObjective
	_check(obj != null and obj.objective_type == DungeonObjective.ObjectiveType.ELIMINATION \
		and obj.progress() == Vector2i(0, 1), "(D) ELIMINATION objective, target = the boss")
	var portal := area.get_node_or_null("ExitPortal") as ExitPortal
	_check(portal != null and portal.locked, "(D) exit portal LOCKED while the boss lives")
	if portal == null or boss == null:
		scene.queue_free()
		return
	portal._on_body_entered(p)
	await _physics(4)
	_check(scene.area_loader.current_area == area, "(D) locked portal entry ignored")
	boss.apply_damage(9999) # synthetic kill
	await _physics(4)
	_check(obj.is_cleared() and not portal.locked, "(D) boss death clears the arena and unlocks the portal")
	portal._on_body_entered(p)
	await _physics(4)
	_check(scene.area_loader.current_area.name == "Overworld", "(D) unlocked portal returns to the overworld entrance (#378)")
	scene.queue_free()
	current_scene = null
	await process_frame

# (E) -----------------------------------------------------------------------
func _arena(player_offset: Vector2) -> Array:
	var world := Node2D.new()
	root.add_child(world)
	var p: Player = load("res://scenes/player.tscn").instantiate()
	p.position = Vector2(500, 300) + player_offset
	p.collision_layer = 0
	p.collision_mask = 0
	world.add_child(p)
	var b: Enemy = load("res://scenes/head_boss.tscn").instantiate()
	b.position = Vector2(500, 300)
	b.collision_layer = 0
	b.collision_mask = 0
	world.add_child(b)
	return [world, p, b]

func _close(a: Array) -> void:
	(a[0] as Node).queue_free()
	await process_frame

func _count_bolts(world: Node) -> int:
	var n := 0
	for c in world.get_children():
		if c is Projectile and (c as Projectile).spell == EnemyBehaviorHead.BOLT_SPELL:
			n += 1
	return n

## Runs one attack cycle; returns what was observed.
func _observe(a: Array, frames: int) -> Dictionary:
	var world: Node2D = a[0]
	var p: Player = a[1]
	var b: Enemy = a[2]
	var beh := b._behavior as EnemyBehaviorHead
	var tele := b.get_node("Telegraph") as BossTelegraph
	var seen := {"cone": false, "ring": false, "glow": false, "windup_anim": &"", "attack_anim": &"",
		"live_ring": false, "bolts": 0, "pulses": 0, "hp": p.hp, "states": []}
	for i in frames:
		await physics_frame
		if not (beh.state in seen["states"]):
			seen["states"].append(beh.state)
		if beh.state == EnemyBehaviorHead.State.WINDUP:
			seen["cone"] = seen["cone"] or tele.mode == BossTelegraph.Mode.CONE
			seen["ring"] = seen["ring"] or tele.mode == BossTelegraph.Mode.RING
			seen["glow"] = seen["glow"] or b.sprite.self_modulate != Color.WHITE
			seen["windup_anim"] = b.sprite.animation
		if beh.state == EnemyBehaviorHead.State.VOLLEY or beh.state == EnemyBehaviorHead.State.PULSE:
			seen["attack_anim"] = b.sprite.animation
		if beh.state == EnemyBehaviorHead.State.PULSE and tele.mode == BossTelegraph.Mode.RING and tele._active:
			seen["live_ring"] = true
		seen["bolts"] = maxi(seen["bolts"], _count_bolts(world))
		seen["pulses"] = maxi(seen["pulses"], beh._pulses)
		if beh.state == EnemyBehaviorHead.State.RECOVER:
			await physics_frame
			seen["bolts"] = maxi(seen["bolts"], _count_bolts(world))
			break
	seen["hp"] = p.hp
	return seen

func _leg_attacks() -> void:
	# Volley: far range, boss held in place so the range pick is exact.
	var a := _arena(Vector2(320, 0))
	await process_frame
	(a[2] as Enemy).speed = 0.0
	var s := await _observe(a, 240)
	_check(s["cone"] and s["glow"], "(E) volley wind-up: cone telegraph + glow")
	_check(s["windup_anim"] == &"windup_projectile", "(E) volley wind-up plays windup_projectile")
	_check(s["attack_anim"] == &"projectile", "(E) volley plays the projectile scream")
	_check(s["bolts"] >= EnemyBehaviorHead.VOLLEY_SHOTS, "(E) volley fires >= %d bolts (got %d)" % [EnemyBehaviorHead.VOLLEY_SHOTS, s["bolts"]])
	_check(EnemyBehaviorHead.State.CHASE in s["states"] and EnemyBehaviorHead.State.RECOVER in s["states"],
		"(E) CHASE -> WINDUP -> VOLLEY -> RECOVER")
	await _close(a)

	# Pulse: close range.
	a = _arena(Vector2(70, 0))
	await process_frame
	(a[2] as Enemy).speed = 0.0
	(a[2] as Enemy).contact_range = 0.0 # isolate the pulse damage
	s = await _observe(a, 240)
	_check(s["ring"] and s["windup_anim"] == &"windup_aoe", "(E) pulse wind-up: ring telegraph + windup_aoe")
	_check(s["attack_anim"] == &"aoe" and s["live_ring"], "(E) pulse plays aoe with the in-engine ring")
	_check(s["hp"] == 100 - EnemyBehaviorHead.PULSE_DAMAGE, "(E) one pulse hit (hp %d)" % s["hp"])
	await _close(a)

# (F) -----------------------------------------------------------------------
func _leg_phase() -> void:
	var a := _arena(Vector2(320, 0))
	var b: Enemy = a[2]
	await process_frame
	b.speed = 0.0
	var beh := b._behavior as EnemyBehaviorHead
	_check(not beh.phase_two and not beh.is_enraged(b), "(F) starts in phase one")
	b.apply_damage(b.max_hp / 2) # exactly 50%
	await _physics(2)
	_check(beh.phase_two and beh.state == EnemyBehaviorHead.State.STUN, "(F) <= 50% HP: phase change -> STUN")
	_check(b.sprite.animation == &"stun" and b.sprite.is_playing(), "(F) stun animation plays")
	await _physics(int(EnemyBehaviorHead.STUN_TIME * 60.0) - 10)
	_check(beh.state == EnemyBehaviorHead.State.STUN and _count_bolts(a[0]) == 0, "(F) no attacks while stunned")
	await _physics(20)
	_check(beh.state == EnemyBehaviorHead.State.CHASE, "(F) recovers to CHASE after the stun")
	var s := await _observe(a, 240)
	var want: int = 2 * EnemyBehaviorHead.VOLLEY_SHOTS_ENRAGED
	_check(s["bolts"] >= want, "(F) enraged volley: two waves, >= %d bolts (got %d)" % [want, s["bolts"]])
	_check(b.get_node("HealthBar")._ratio <= 0.5, "(F) HP bar in its enraged range")
	await _close(a)

	a = _arena(Vector2(70, 0))
	b = a[2]
	await process_frame
	b.speed = 0.0
	b.contact_range = 0.0
	b.apply_damage(b.max_hp / 2 + 1)
	beh = b._behavior as EnemyBehaviorHead
	await _physics(int(EnemyBehaviorHead.STUN_TIME * 60.0) + 10)
	s = await _observe(a, 240)
	_check(s["pulses"] == 2, "(F) enraged pulse releases two rings (got %d)" % s["pulses"])
	_check(s["hp"] == 100 - 2 * EnemyBehaviorHead.PULSE_DAMAGE, "(F) both rings hit inside the radius (hp %d)" % s["hp"])
	_check(EnemyBehaviorHead.STUN_TIME > 0.0 and beh.phase_two, "(F) stun happens once")
	await _close(a)
