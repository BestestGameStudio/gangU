extends SceneTree
## #99 (Foundation E2) harness: behavior seam - the current chase/contact
## behavior extracted into swappable per-enemy behavior instances, slotted
## via EnemyDefinition.behavior.
##
## Legs (REAL physics frames first, then DIRECT-drive timer legs):
##   (0)  seam exists (behavior script loads) - FAILS on base bf71099
##        (no seam), PASS here. Early-quits when absent.
##   (0b) missing player: enemy idles (velocity ZERO, no movement). REAL.
##   (1a) scene definition with no behavior -> default chase/contact instance.
##   (1b) definition with slot unset -> default chase/contact instance.
##   (1c) slot honored: marker subclass prototype in slot -> instance has marker.
##   (1d) non-EnemyBehavior slot -> error, no behavior, no contact. REAL.
##   (2)  movement parity, fixed placement: velocity (110,0), position
##        advanced exactly 110px in 60 fixed frames. REAL.
##   (3)  stop within 8px, velocity ZERO, frozen position. REAL.
##   (7)  player-death idle: hp 0 -> velocity ZERO, position frozen. REAL.
##   (4)  contact timing/counts: 250 DIRECT-driven fixed frames -> exactly
##        6 contacts, gaps 46..51 frames (cooldown 0.8s = 48 frames),
##        hp 100 -> 40.
##   (5)  MANDATORY staggered two-enemy independence: DIRECT-driving e1
##        mid-cooldown never advances e2's timer (contact on its own
##        clock), and e1's residual clock is intact after driving e2.
##   (6)  mutation teeth: force-SHARED behavior instance -> the same
##        staggered check FAILS (contact ~30 frames early).
##
## Mechanics notes:
## - Fixture: every spawned body gets collision_layer/mask = 0. The
##   behavior contract asserted here (chase velocity, 8px stop, contact
##   range/cooldown timers) is range- and timer-based, not collision-
##   based, and the real shapes (enemy r=13, player r=16) overlap below
##   29px, which fires move_and_slide recovery impulses that teleport
##   bodies and poison later RID reuse (verified). Collisions off keeps
##   fixed placements exact; game scenes are untouched.
## - MOVEMENT legs (0b/1d/2/3/7) use REAL physics frames (await
##   physics_frame, fixed 1/60 ticks): move_and_slide only integrates
##   motion inside a real physics step.
## - TIMER legs (4/5/6) use DIRECT _physics_process(1/60) calls, labeled
##   direct-drive, not real input frames: two enemies must be stepped
##   independently to prove timer independence - real frames step both
##   at once. These legs assert timers/hp only, never positions.
## - Nodes are not freed mid-run (freed-body RID reuse in the physics
##   space is the contamination vector); legs use distinct placements.
## - Spawn normalization: a newly added CharacterBody2D can get ONE
##   uncontrolled physics tick during its ready frame even with physics
##   processing disabled (verified: hp/timer moved before any drive).
##   So every leg re-pins positions after spawn, and timer legs re-pin
##   player hp and the behavior's _contact_timer before driving.

const DT := 1.0 / 60.0

var failures := 0
var _enemy_scene: PackedScene
var _player_scene: PackedScene

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[99] ", name, " -> PASS")
	else:
		failures += 1
		print("[99] ", name, " -> FAIL")

func _mk_pair(ename: String, epos: Vector2, pname: String, ppos: Vector2, def: Resource = null) -> Array:
	var p: Player = _player_scene.instantiate() as Player
	p.name = pname
	p.collision_layer = 0
	p.collision_mask = 0
	root.add_child(p)
	p.global_position = ppos
	p.set_physics_process(false)
	var e: Enemy = _enemy_scene.instantiate() as Enemy
	e.name = ename
	e.collision_layer = 0
	e.collision_mask = 0
	if def != null:
		e.set("definition", def)
	e.player_path = NodePath("../" + pname)
	e.set_physics_process(false)
	root.add_child(e)
	e.global_position = epos
	return [e, p]

func _spawned_pair(ename: String, epos: Vector2, pname: String, ppos: Vector2, def: Resource = null) -> Array:
	var pair := _mk_pair(ename, epos, pname, ppos, def)
	await process_frame # _ready defers to the first frame in a SceneTree harness
	# Re-pin after the possible uncontrolled spawn tick (see header notes).
	(pair[0] as Node2D).global_position = epos
	(pair[1] as Node2D).global_position = ppos
	return pair

func _reset_contact_state(e: Enemy, p: Player) -> void:
	p.hp = 100 # direct fixture reset (silent; contract setter not needed)
	(e.get("_behavior") as RefCounted).set("_contact_timer", 0.0)

func _drive(e: Enemy, frames: int) -> void:
	for i in frames:
		e._physics_process(DT)

func _drive_real(e: Enemy, frames: int, pin: Vector2) -> void:
	e.set_physics_process(true)
	await physics_frame # settle tick: enabling can race one physics step
	e.global_position = pin # re-pin: the settle tick may have moved us
	for i in frames:
		await physics_frame
	e.set_physics_process(false)

func _first_drop_frame_direct(e: Enemy, p: Player, max_frames: int) -> int:
	var last_hp: int = p.hp
	for i in range(1, max_frames + 1):
		e._physics_process(DT)
		if p.hp < last_hp:
			return i
	return -1

func _is_default_instance(b: Variant) -> bool:
	if b == null:
		return false
	var s: Script = (b as RefCounted).get_script()
	return s != null and s.resource_path.ends_with("enemy_behavior_chase_contact.gd")

func _initialize() -> void:
	var behavior_script: Script = load("res://scripts/enemy_behavior_chase_contact.gd")
	_check(behavior_script != null, "(0) behavior seam script exists (FAILS on base bf71099)")
	_enemy_scene = load("res://scenes/enemy.tscn")
	_player_scene = load("res://scenes/player.tscn")
	var def_script: Script = load("res://scripts/enemy_definition.gd")
	_check(_enemy_scene != null and _player_scene != null and def_script != null, "(0) enemy/player scenes + definition script load")
	if behavior_script == null or _enemy_scene == null or _player_scene == null or def_script == null:
		print("[99] DONE failures=", failures)
		quit(failures)
		return

	# ==== REAL-frame legs first ====

	# (0b) missing player: idle, no movement, no crash.
	var e0: Enemy = _enemy_scene.instantiate() as Enemy
	e0.collision_layer = 0
	e0.collision_mask = 0
	e0.set_physics_process(false)
	root.add_child(e0)
	e0.global_position = Vector2.ZERO
	await process_frame # _ready defers to the first frame in a SceneTree harness
	e0.global_position = Vector2.ZERO # re-pin after possible spawn tick
	await _drive_real(e0, 5, Vector2.ZERO)
	_check(e0.velocity == Vector2.ZERO and e0.global_position == Vector2.ZERO, "(0b) missing player -> idle (velocity ZERO, no movement)")

	# (1a) scene definition, slot unset -> default instance.
	var pair := await _spawned_pair("E1a", Vector2(0, 1000), "P1a", Vector2(8, 1000))
	var ea: Enemy = pair[0]
	_check(ea.definition != null and ea.definition.behavior == null, "(1a) scene definition leaves the slot unset")
	_check(_is_default_instance(ea.get("_behavior")), "(1a) default chase/contact behavior instance")

	# (1b) definition, slot unset -> default instance.
	var def_b: Resource = def_script.new()
	pair = await _spawned_pair("E1b", Vector2(0, 2000), "P1b", Vector2(8, 2000), def_b)
	var eb: Enemy = pair[0]
	_check(_is_default_instance(eb.get("_behavior")), "(1b) slot unset -> default chase/contact behavior instance")

	# (1c) slot honored: in-memory marker subclass prototype in the slot.
	var marker_script := GDScript.new()
	marker_script.source_code = "extends EnemyBehaviorChaseContact\nvar marker: int = 1\n"
	_check(marker_script.reload() == OK, "(1c) marker subclass script compiles")
	var def_c: Resource = def_script.new()
	def_c.set("behavior", marker_script.new())
	pair = await _spawned_pair("E1c", Vector2(0, 3000), "P1c", Vector2(8, 3000), def_c)
	var ec: Enemy = pair[0]
	var bc: Variant = ec.get("_behavior")
	_check(bc != null and bc.get("marker") == 1, "(1c) slot prototype duplicated (marker present)")

	# (1d) a slot that is not an EnemyBehavior -> error and no behavior. REAL frame.
	var def_d: Resource = def_script.new()
	def_d.set("behavior", load("res://scripts/reward_table.gd"))
	pair = await _spawned_pair("E1d", Vector2(0, 4000), "P1d", Vector2(8, 4000), def_d)
	var ed: Enemy = pair[0]
	var pd: Player = pair[1]
	_check(ed.get("_behavior") == null, "(1d) non-EnemyBehavior slot -> no fallback behavior")
	ed.set_physics_process(true)
	await physics_frame # settle tick
	pd.hp = 100
	ed.global_position = Vector2(0, 4000)
	await physics_frame # exactly one counted tick
	ed.set_physics_process(false)
	_check(pd.hp == 100, "(1d) enemy without a behavior never contacts (hp stays 100)")

	# (2) movement parity, fixed placement: (0,5000) chasing (1008,5000). REAL.
	pair = await _spawned_pair("E2", Vector2(0, 5000), "P2", Vector2(1008, 5000))
	var e2: Enemy = pair[0]
	await _drive_real(e2, 60, Vector2(0, 5000))
	_check(absf(e2.velocity.x - 110.0) < 0.001 and absf(e2.velocity.y) < 0.001, "(2) velocity exactly (110, 0) while chasing")
	_check(absf(e2.global_position.x - 110.0) < 0.5 and absf(e2.global_position.y - 5000.0) < 0.001, "(2) position advanced 110px in 60 fixed frames (x=%.3f)" % e2.global_position.x)

	# (3) stop within 8px. REAL.
	pair = await _spawned_pair("E3", Vector2(0, 6000), "P3", Vector2(50, 6000))
	var e3: Enemy = pair[0]
	var p3: Player = pair[1]
	await _drive_real(e3, 90, Vector2(0, 6000))
	var dist3: float = (p3.global_position - e3.global_position).length()
	_check(e3.velocity == Vector2.ZERO, "(3) velocity ZERO at rest")
	_check(dist3 <= 8.0, "(3) stopped within 8px (dist %.3f)" % dist3)
	_check(absf(e3.global_position.x - 42.1667) < 0.05, "(3) stop position matches fixed-frame expectation (x=%.3f)" % e3.global_position.x)

	# (7) player-death idle. REAL.
	pair = await _spawned_pair("E7", Vector2(0, 7000), "P7", Vector2(1008, 7000))
	var e7: Enemy = pair[0]
	var p7: Player = pair[1]
	await _drive_real(e7, 10, Vector2(0, 7000))
	var x_alive: float = e7.global_position.x
	_check(x_alive > 10.0, "(7) enemy chases while player alive")
	p7.apply_damage(999) # hp -> 0 (player stays valid; died() emitted)
	await _drive_real(e7, 10, e7.global_position)
	_check(p7.hp == 0 and e7.velocity == Vector2.ZERO, "(7) dead player -> velocity ZERO")
	_check(absf(e7.global_position.x - x_alive) < 0.001, "(7) dead player -> position frozen")

	# ==== DIRECT-drive timer legs (labeled direct-drive; timer/hp ====
	# ==== assertions only, run LAST) ====

	# (4) contact timing/counts: stationary target at exactly 8px.
	pair = await _spawned_pair("E4", Vector2(0, 8000), "P4", Vector2(8, 8000))
	var e4: Enemy = pair[0]
	var p4: Player = pair[1]
	_reset_contact_state(e4, p4)
	var contact_frames: Array[int] = []
	var last_hp4: int = p4.hp
	for i in range(1, 251):
		e4._physics_process(DT)
		if p4.hp < last_hp4:
			contact_frames.append(i)
			last_hp4 = p4.hp
	_check(contact_frames.size() == 6, "(4) exactly 6 contacts in 250 fixed frames (got %d at %s)" % [contact_frames.size(), str(contact_frames)])
	_check(p4.hp == 40, "(4) hp 100 -> 40 (6 x contact_damage 10)")
	var gaps_ok := contact_frames.size() == 6
	for i in range(1, contact_frames.size()):
		var gap: int = contact_frames[i] - contact_frames[i - 1]
		if gap < 46 or gap > 51:
			gaps_ok = false
	_check(gaps_ok, "(4) contact gaps all 46..51 frames (cooldown 0.8s = 48)")

	# (5) MANDATORY staggered two-enemy independence. DIRECT.
	var p1: Player = _player_scene.instantiate() as Player
	p1.name = "PS1"
	p1.collision_layer = 0
	p1.collision_mask = 0
	root.add_child(p1)
	p1.global_position = Vector2(8, 9000)
	p1.set_physics_process(false)
	var p2: Player = _player_scene.instantiate() as Player
	p2.name = "PS2"
	p2.collision_layer = 0
	p2.collision_mask = 0
	root.add_child(p2)
	p2.global_position = Vector2(508, 9000)
	p2.set_physics_process(false)
	var s1: Enemy = _enemy_scene.instantiate() as Enemy
	s1.name = "ES1"
	s1.collision_layer = 0
	s1.collision_mask = 0
	s1.player_path = NodePath("../PS1")
	s1.set_physics_process(false)
	root.add_child(s1)
	s1.global_position = Vector2(0, 9000)
	var s2: Enemy = _enemy_scene.instantiate() as Enemy
	s2.name = "ES2"
	s2.collision_layer = 0
	s2.collision_mask = 0
	s2.player_path = NodePath("../PS2")
	s2.set_physics_process(false)
	root.add_child(s2)
	s2.global_position = Vector2(500, 9000)
	await process_frame
	s1.global_position = Vector2(0, 9000) # re-pin after possible spawn tick
	s2.global_position = Vector2(500, 9000)
	_reset_contact_state(s1, p1)
	_reset_contact_state(s2, p2)
	_drive(s1, 1) # both contact on their first driven frame
	_drive(s2, 1)
	_check(p1.hp == 90 and p2.hp == 90, "(5) setup: both enemies contacted once")
	_drive(s1, 30) # e1 mid-cooldown (0.3s left); e2 NOT driven
	_check(p1.hp == 90, "(5) e1 mid-cooldown: no contact while staggered")
	var drop2: int = _first_drop_frame_direct(s2, p2, 60)
	_check(drop2 >= 46 and drop2 <= 51, "(5) e2 contacts on its OWN clock (frame %d, expect ~48)" % drop2)
	_check(p2.hp == 80, "(5) e2 second contact landed exactly once")
	var drop1: int = _first_drop_frame_direct(s1, p1, 40)
	_check(drop1 >= 14 and drop1 <= 24, "(5) e1 residual clock intact (frame %d, expect ~18)" % drop1)

	# (6) mutation teeth: shared behavior instance MUST break independence.
	var q1: Player = _player_scene.instantiate() as Player
	q1.name = "MS1"
	q1.collision_layer = 0
	q1.collision_mask = 0
	root.add_child(q1)
	q1.global_position = Vector2(8, 10000)
	q1.set_physics_process(false)
	var q2: Player = _player_scene.instantiate() as Player
	q2.name = "MS2"
	q2.collision_layer = 0
	q2.collision_mask = 0
	root.add_child(q2)
	q2.global_position = Vector2(508, 10000)
	q2.set_physics_process(false)
	var m1: Enemy = _enemy_scene.instantiate() as Enemy
	m1.name = "MES1"
	m1.collision_layer = 0
	m1.collision_mask = 0
	m1.player_path = NodePath("../MS1")
	m1.set_physics_process(false)
	root.add_child(m1)
	m1.global_position = Vector2(0, 10000)
	var m2: Enemy = _enemy_scene.instantiate() as Enemy
	m2.name = "MES2"
	m2.collision_layer = 0
	m2.collision_mask = 0
	m2.player_path = NodePath("../MS2")
	m2.set_physics_process(false)
	root.add_child(m2)
	m2.global_position = Vector2(500, 10000)
	await process_frame
	m1.global_position = Vector2(0, 10000) # re-pin after possible spawn tick
	m2.global_position = Vector2(500, 10000)
	_reset_contact_state(m1, q1)
	_reset_contact_state(m2, q2)
	m1.set("_behavior", m2.get("_behavior")) # MUTATION: shared instance
	_drive(m1, 1) # shared timer now 0.8
	_drive(m2, 1) # no contact: shared timer already set
	_drive(m1, 30) # advances the SHARED timer to 0.3
	var dropm: int = _first_drop_frame_direct(m2, q2, 40)
	_check(dropm >= 14 and dropm <= 24, "(6) MUTATION shared instance breaks independence (frame %d, expect ~18 - proves the leg has teeth)" % dropm)

	print("[99] DONE failures=", failures)
	quit(failures)
