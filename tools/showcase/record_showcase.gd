extends SceneTree
## RECORDING-ONLY showcase driver (not a test, not loaded by the game).
## Boots main.tscn, walks the hero from the hub through GATE_NAME into
## AREA_NAME, fights the boss on autopilot and walks out of the exit portal.
## Usage: see .claude/skills/showcase-video/SKILL.md, in short:
##   godot --path . --write-movie out.avi --fixed-fps 60 \
##         --script res://tools/showcase/record_showcase.gd
## First written for #173 (Head boss, DungeonC). Everything boss-specific is
## looked up by name at runtime (no class_name references), so this file
## parses on branches where that boss does not exist yet.

# --- Targets: edit these per showcase ----------------------------------------
## Gate node to walk into (overworld since #346; hub on older main), and the
## area it leads to. GateBoss / DungeonC
## exist from #173 (PR #213) on; on older main use GateRed / DungeonB.
const GATE_NAME := "GateBoss"
const AREA_NAME := "DungeonC"
## Walkable box inside the area (player targets are clamped into it).
const ARENA := Rect2(340, 130, 472, 490)
## Hub waypoint walked to before heading for the gate (keeps the path clear).
const HUB_WAYPOINT := Vector2(650, 380)
## Boss HP for the recording (short, but long enough to show every attack).
const SHOWCASE_BOSS_HP := 200
## Seconds of plain fighting when the boss is not the Head (generic mode).
const GENERIC_FIGHT_SEC := 14.0

const FPS := 60.0

var scene: Node
var p: Player
var caster: Node2D
var cam: Camera2D
var focus: Node2D
var boss: Enemy = null
var beh = null ## the boss's behavior instance (duck-typed)
var move_target = null ## Vector2 or null
var aim_at_boss := false
var auto_cast := false
## RECORDING-ONLY: boss HP is held >= this so each attack beat gets screen
## time before the next phase / the kill. Lowered beat by beat below.
var hp_floor := 0
var frame := 0

func say(s: String) -> void:
	print("[rec %5.2fs] %s" % [frame / FPS, s])

## Enum value by name from the boss behavior script (e.g. "State", "PULSE"),
## or -1 when the behavior has no such enum (generic mode).
func _enum(enum_name: String, key: String) -> int:
	if beh == null or beh.get_script() == null:
		return -1
	var e = beh.get_script().get_script_constant_map().get(enum_name)
	return e.get(key, -1) if e is Dictionary else -1

func _in_state(key: String) -> bool:
	var v := _enum("State", key)
	return v >= 0 and beh.get("state") == v

func _attack_is(key: String) -> bool:
	var v := _enum("Attack", key)
	return v >= 0 and beh.get("attack") == v

func _press(dir: Vector2) -> void:
	for pair in [[&"move_right", dir.x], [&"move_left", -dir.x], [&"move_down", dir.y], [&"move_up", -dir.y]]:
		if pair[1] > 0.0:
			Input.action_press(pair[0], pair[1])
		else:
			Input.action_release(pair[0])

## Casts the equipped spell at `target` the same way SpellCaster does, but
## aimed by the script instead of the OS mouse.
func _cast_toward(target: Vector2) -> void:
	var spell: Spell = caster.equipped_spell
	if spell == null or caster.cooldown_remaining(spell) > 0.0:
		return
	var dir: Vector2 = caster.global_position.direction_to(target)
	for d in SpellFanout.directions(dir, spell.projectile_count, spell.spread_degrees):
		var pr: Projectile = caster.projectile_scene.instantiate()
		pr.setup(spell, d, p)
		current_scene.add_child(pr)
		pr.global_position = caster.global_position
	caster._cooldowns[spell] = spell.cooldown
	caster.cooldown_started.emit(spell, spell.cooldown)
	caster.spell_cast.emit(spell)
	preload("res://scripts/combat_effects.gd").muzzle(current_scene, caster.global_position, dir.angle(), spell.projectile_color)

func _in_area() -> bool:
	return scene.current_area != null and scene.current_area.name == AREA_NAME

func _clamp_arena(v: Vector2) -> Vector2:
	return v.clamp(ARENA.position, ARENA.end)

func _boss_alive() -> bool:
	return boss != null and is_instance_valid(boss)

## Nearest live enemy (mobs before a boss spawns), or null.
func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	for e in get_nodes_in_group("enemies"):
		if is_instance_valid(e) and (best == null or p.global_position.distance_to(e.global_position) < p.global_position.distance_to(best.global_position)):
			best = e
	return best

func _tick() -> void:
	frame += 1
	if move_target != null:
		if _in_area():
			move_target = _clamp_arena(move_target)
		var to: Vector2 = (move_target as Vector2) - p.global_position
		_press(Vector2.ZERO if to.length() < 6.0 else to.normalized() * clampf(to.length() / 40.0, 0.35, 1.0))
	else:
		_press(Vector2.ZERO)
	# RECORDING-ONLY: keep the hero alive (a death would reload the run).
	if p.hp < 40:
		p.heal(60)
	var live_boss := _boss_alive()
	if live_boss and boss.hp < hp_floor:
		boss.hp = hp_floor # RECORDING-ONLY beat pacing, see hp_floor
	var target: Node2D = boss if live_boss else (_nearest_enemy() if aim_at_boss else null)
	focus.global_position = p.global_position.lerp(target.global_position, 0.4) if target != null else p.global_position
	var aim: Vector2 = target.global_position if (aim_at_boss and target != null) else p.global_position + Vector2.UP
	var ad := p.global_position.direction_to(aim)
	if ad.length_squared() > 0.0:
		p.rotation = ad.angle()
	if p.sprite != null:
		p.sprite.global_rotation = 0.0
	if auto_cast and target != null and p.global_position.distance_to(target.global_position) < 400.0:
		_cast_toward(target.global_position)

## A spot `dist` from the boss, inside the arena, nearest the player.
func _kite_point(dist: float) -> Vector2:
	var best := p.global_position
	var best_d := INF
	for i in 24:
		var c: Vector2 = boss.global_position + Vector2.RIGHT.rotated(TAU * i / 24.0) * dist
		if c != _clamp_arena(c):
			continue
		var d := c.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = c
	return best

func _wait(sec: float) -> void:
	for i in int(sec * FPS):
		await physics_frame
		_tick()

func _wait_until(cond: Callable, limit_sec: float) -> bool:
	for i in int(limit_sec * FPS):
		await physics_frame
		_tick()
		if cond.call():
			return true
	say("TIMEOUT waiting")
	return false

## Walk to ~105 px from the boss until it winds up a PULSE (up to 3 tries).
func _bait_pulse() -> bool:
	for attempt in 3:
		var t0 := frame
		while frame - t0 < FPS * 4:
			if _boss_alive():
				move_target = boss.global_position + (p.global_position - boss.global_position).normalized() * 105.0
			await physics_frame
			_tick()
			if _in_state("WINDUP") and _attack_is("PULSE"):
				return true
		await _wait_until(func(): return _in_state("CHASE"), 3.0)
	return false

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")
	p.set_process(false) # aim is driven here instead of from the OS mouse
	caster = p.get_node("SpellCaster")
	cam = scene.get_node("FollowCamera")
	focus = Node2D.new()
	scene.add_child(focus)
	focus.global_position = p.global_position
	cam.target = focus
	cam.follow_speed = 3.5
	p.speed = 190.0 # RECORDING-ONLY: calmer walk for the camera

	# --- Beat 1: hub, walk into the gate -----------------------------------
	say("hub")
	await _wait(1.3)
	var gate: Node2D = scene.current_area.get_node_or_null(GATE_NAME)
	if gate == null and scene.has_method("enter_overworld"):
		# #346: dungeon entrances live in the overworld. Start the walk just
		# south of the entrance (the waypoint below is hub-relative).
		scene.enter_overworld()
		gate = scene.current_area.get_node_or_null(GATE_NAME)
		if gate != null:
			p.global_position = gate.global_position + Vector2(0, 140)
			focus.global_position = p.global_position
			cam.global_position = p.global_position
	if gate == null:
		push_error("record_showcase: hub has no gate '%s' (edit GATE_NAME)" % GATE_NAME)
		quit(1)
		return
	if scene.current_area.name == &"Hub":
		move_target = HUB_WAYPOINT
		await _wait(0.8)
	move_target = gate.global_position
	if not await _wait_until(_in_area, 4.0):
		gate._on_body_entered(p)
		await _wait_until(_in_area, 1.0)
	move_target = null
	say("entered %s" % AREA_NAME)

	# --- Beat 2: fight until a boss shows up (mobs first, if any) -----------
	aim_at_boss = true
	auto_cast = true
	if not await _wait_until(func(): return get_nodes_in_group("boss").size() > 0, 30.0):
		push_error("record_showcase: no node joined group 'boss' in %s" % AREA_NAME)
		quit(1)
		return
	boss = get_nodes_in_group("boss")[0]
	beh = boss.get("_behavior")
	boss.max_hp = SHOWCASE_BOSS_HP # RECORDING-ONLY
	boss.hp = SHOWCASE_BOSS_HP
	cam.global_position = p.global_position.lerp(boss.global_position, 0.4)
	cam.zoom = Vector2(1.25, 1.25)
	p.speed = 210.0

	if _enum("Attack", "PULSE") >= 0:
		await _head_beats()
	else:
		await _generic_beats()

	# --- Finish it and walk out ---------------------------------------------
	hp_floor = 0
	if not await _wait_until(func(): return not _boss_alive(), 6.0) and _boss_alive():
		boss.apply_damage(99999)
	auto_cast = false
	aim_at_boss = false
	say("boss dead")
	move_target = null
	await _wait(2.2)
	var portal: Node2D = scene.current_area.get_node_or_null("ExitPortal")
	if portal != null:
		move_target = portal.global_position + Vector2(0, 60)
		await _wait(1.6)
		move_target = portal.global_position
		await _wait_until(func(): return scene.current_area.name == "Overworld", 3.0) # #378: exit lands at the entrance
	move_target = null
	cam.zoom = Vector2(1, 1)
	await _wait(1.2)
	say("done")
	quit()

## Any boss: kite at mid range and shoot, HP held at 30 so it lives long
## enough to cycle its attacks, then the caller lets it die.
func _generic_beats() -> void:
	hp_floor = 30
	var t0 := frame
	while frame - t0 < FPS * GENERIC_FIGHT_SEC and _boss_alive():
		move_target = _kite_point(230.0)
		await physics_frame
		_tick()

## #173 Head boss choreography (EnemyBehaviorHead: VOLLEY far, PULSE close,
## STUN at 50% HP, then enraged versions of both).
func _head_beats() -> void:
	hp_floor = 101 # phase 1: hold above 50% until the pulse has been shown
	await _wait(0.5)
	# Far: volley. Strafe across during the locked tail to dodge.
	await _wait_until(func(): return _in_state("WINDUP"), 4.0)
	await _wait(0.4)
	move_target = p.global_position + (p.global_position - boss.global_position).normalized().orthogonal() * 110.0
	await _wait_until(func(): return _in_state("RECOVER"), 3.0)
	say("volley p1 done")
	# Close: walk in for the ring pulse, then back off just outside the ring.
	await _wait(0.3)
	var baited: bool = await _bait_pulse()
	say("pulse windup p1: %s" % baited)
	move_target = boss.global_position + (p.global_position - boss.global_position).normalized() * 135.0
	await _wait_until(func(): return _in_state("RECOVER"), 3.0)
	# Retreat and let damage through -> 50% stun.
	move_target = _kite_point(230.0)
	hp_floor = 1
	await _wait_until(func(): return beh.get("phase_two"), 8.0)
	if not beh.get("phase_two"):
		boss.apply_damage(boss.hp - boss.max_hp / 2)
	say("STUN")
	hp_floor = 30 # phase 2: show enraged volley + pulse before dying
	await _wait_until(func(): return not _in_state("STUN"), 3.0)
	# Enraged volley (far).
	var t2 := frame
	while frame - t2 < FPS * 3 and not _in_state("WINDUP"):
		move_target = _kite_point(250.0)
		await physics_frame
		_tick()
	if _attack_is("VOLLEY"):
		await _wait(0.35)
		var side := (p.global_position - boss.global_position).normalized().orthogonal() * 140.0
		if _clamp_arena(p.global_position + side) != p.global_position + side:
			side = -side
		move_target = p.global_position + side
	await _wait_until(func(): return _in_state("RECOVER"), 3.0)
	# Enraged pulse (close).
	await _bait_pulse()
	move_target = _kite_point(210.0)
	await _wait_until(func(): return _in_state("RECOVER"), 3.0)
	say("p2 pulse done")
