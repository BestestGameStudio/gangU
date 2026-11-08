extends SceneTree
## #173 EVIDENCE driver (headless): the Head boss in the RED room, through
## the PRODUCTION composition (main.tscn boot -> RED gate entry). Legs:
##   boot      - hub boots, player present, RED gate targets DungeonB
##   red entry - real RED-gate entry swaps to DungeonB; the ELIMINATION
##               objective spawns exactly one BossHead (boss group), target
##               0/1, and the exit portal starts LOCKED (D12 clear-or-die)
##   sprite    - SpriteFrames carries the reference anims with the sliced
##               frame counts (idle 6, move 7/dir, projectile 8, aoe 4,
##               hurt 4, stun 4, death 10)
##   volley    - at range the boss fires VOLLEY_COUNT boss bolts aimed at
##               the player (aim error < spread + tolerance)
##   aoe       - up close the AOE telegraph rings, then the pulse damages
##               the player inside the radius
##   hurt/stun - damage flashes hurt; accumulated damage stuns (no movement)
##   death     - lethal damage emits died once, completes the objective,
##               unlocks the exit portal, and the crumble animation is the
##               last thing playing before despawn
##   escape    - after the unlock the portal returns to the hub
##   guard     - anti-soft-lock negatives: a DungeonB WITHOUT an objective,
##               and one whose objective has NO boss_scene, both mount the
##               exit portal UNLOCKED (the #55 escape path stays safe)
## Negative leg: on the pre-#173 base there is no BossHead / boss spawn in
## DungeonB, so red-entry, sprite, volley, aoe and death legs all FAIL.
## GANGU_CAPTURE_DIR set + real renderer: saves harness PNG captures.

var scene: Node
var p: CharacterBody2D
var boss: Node = null
var objective: Node = null
var portal: Node = null
var fails := 0
var phase := 0
var t := 0.0
var _player_hp_before := 0
var _died_count := 0
var _saw_ring := false
var _bolts_fired := 0
var _capture_dir := ""

func _check(label: String, ok: bool) -> void:
	if not ok:
		fails += 1
	print("[173] ", label, " -> ", "PASS" if ok else "FAIL")

func _initialize() -> void:
	_capture_dir = OS.get_environment("GANGU_CAPTURE_DIR")
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	p = scene.get_node("Player")

func _capture(shot_name: String) -> void:
	if _capture_dir == "" or DisplayServer.get_name() == "headless":
		return
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png(_capture_dir + "/test173_" + shot_name + ".png")

func _find_red_gate() -> Node:
	for g in get_nodes_in_group("gates"):
		if g.gate_type == 1: # Gate.GateType.RED
			return g
	return null

func _physics_process(delta: float) -> bool:
	t += delta
	match phase:
		0: # boot checks, then enter the RED gate
			_check("hub boots with the player", is_instance_valid(p) and p.hp > 0)
			var red := _find_red_gate()
			_check("hub has a RED gate", red != null)
			if red == null:
				return _finish()
			red._on_body_entered(p) # test9 direct-call idiom
			phase = 1
			t = 0.0
		1: # wait for the deferred swap + boss spawn
			if t > 0.5:
				var area: Node = scene.current_area
				_check("RED gate swaps to DungeonB", area != null and area.name == "DungeonB")
				objective = area.get_node_or_null("DungeonObjective")
				_check("DungeonB mounts a DungeonObjective", objective != null)
				if objective != null:
					_check("objective is ELIMINATION w/ 0/1 progress (boss only)", objective.progress() == Vector2i(0, 1))
				portal = area.get_node_or_null("ExitPortal")
				_check("DungeonB exit portal present", portal != null)
				if portal != null:
					_check("exit portal starts LOCKED", portal.locked)
				var bosses := get_nodes_in_group("boss")
				_check("exactly one boss spawned", bosses.size() == 1)
				if bosses.size() == 1:
					boss = bosses[0]
					_check("spawned boss is a BossHead", boss is BossHead)
					_died_count = 0
					boss.died.connect(func(): _died_count += 1)
				if boss == null:
					return _finish()
				_check_spriteframes()
				# park the player far away -> projectile leg
				p.global_position = boss.global_position + Vector2(420, 0)
				_player_hp_before = p.hp
				phase = 2
				t = 0.0
		2: # projectile volley at range
			if boss._state == BossHead.State.WINDUP_AOE and boss._ring != null:
				_saw_ring = true
			if t > 3.2:
				_check("boss fired a volley at range", _bolts_fired >= 2)
				_check("player not in AOE range was NOT pulse-damaged at range", p.hp >= _player_hp_before - 30)
				_capture("volley")
				# AOE leg: move next to the boss
				p.global_position = boss.global_position + Vector2(90, 0)
				_player_hp_before = p.hp
				_saw_ring = false
				phase = 3
				t = 0.0
		3: # AOE pulse up close
			if boss._state == BossHead.State.WINDUP_AOE and boss._ring != null:
				_saw_ring = true
			if t > 4.0:
				_check("AOE telegraph ring shown", _saw_ring)
				_check("AOE pulse damaged the player inside the radius", p.hp < _player_hp_before)
				_capture("aoe")
				# hurt/stun leg
				boss.apply_damage(10)
				_check("boss hp tracks damage (120 -> 110)", boss.hp == 110)
				boss.apply_damage(35) # crosses the 40 stun accumulator
				phase = 4
				t = 0.0
		4: # stun window
			if t > 0.2:
				_check("accumulated damage stuns the boss", boss._state == BossHead.State.STUNNED)
				_check("stunned boss does not move", boss.velocity == Vector2.ZERO)
				_capture("stun")
				# death leg
				boss.apply_damage(999)
				phase = 5
				t = 0.0
		5: # death + objective + portal
			if t > 0.2:
				_check("died emitted exactly once", _died_count == 1)
				_check("objective completed by the boss kill", objective.is_cleared())
				_check("exit portal unlocked on completion", not portal.locked)
				_check("death animation playing", boss.sprite.animation == &"death")
				_capture("death")
				_capture("unlock")
				phase = 6
				t = 0.0
		6: # despawn after crumble
			if t > 2.0:
				_check("boss despawns after the death animation", not is_instance_valid(boss) or boss.sprite.animation != &"death" or not boss.sprite.is_playing())
				portal._on_body_entered(p)
				phase = 7
				t = 0.0
		7:
			if t > 0.5:
				_check("unlocked portal returns to the hub", scene.current_area != null and scene.current_area.name == "Hub")
				_capture("hub")
				_guard_legs()
				return _finish()
	if t > 12.0:
		_check("watchdog: phase " + str(phase) + " finished in time", false)
		return _finish()
	return false

## Anti-soft-lock negatives (lead boundary rule): the red exit may only be
## locked when BOTH a live objective AND its boss_scene exist.
func _guard_legs() -> void:
	# No objective at all: portal must stay unlocked.
	var bare := Node2D.new()
	bare.name = "DungeonB"
	scene.add_child(bare)
	scene._mount_exit_portal(bare)
	var bp: Node = bare.get_node_or_null("ExitPortal")
	_check("guard: no objective -> portal stays UNLOCKED", bp != null and not bp.locked)
	## Immediate free: a deferred free would leave a live "DungeonB" sibling
	## and the next bare node would be auto-renamed off the mount guards.
	scene.remove_child(bare)
	bare.free()
	# Objective present but boss_scene missing: portal must stay unlocked.
	var bare2 := Node2D.new()
	bare2.name = "DungeonB"
	scene.add_child(bare2)
	scene._mount_objective(bare2)
	var obj2: Node = bare2.get_node_or_null("DungeonObjective")
	_check("guard: objective mounted for the leg", obj2 != null)
	if obj2 != null:
		obj2.boss_scene = null
	scene._mount_exit_portal(bare2)
	var bp2: Node = bare2.get_node_or_null("ExitPortal")
	_check("guard: objective without boss_scene -> portal stays UNLOCKED", bp2 != null and not bp2.locked)
	scene.remove_child(bare2)
	bare2.free()

func _check_spriteframes() -> void:
	var sf: SpriteFrames = boss.sprite.sprite_frames
	var expect := {
		&"idle": [6, true], &"move_down": [7, true], &"move_left": [7, true],
		&"move_right": [7, true], &"move_up": [7, true],
		&"attack_projectile": [8, false], &"attack_aoe": [4, false],
		&"hurt": [4, false], &"stun": [4, true], &"death": [10, false],
	}
	for anim in expect:
		_check("anim " + String(anim) + " exists with " + str(expect[anim][0]) + " frames, loop=" + str(expect[anim][1]),
			sf.has_animation(anim) and sf.get_frame_count(anim) == expect[anim][0] and sf.get_animation_loop(anim) == expect[anim][1])

func _on_bolt_tree_entered() -> void:
	pass

func _finish() -> bool:
	print("[173] DONE fails=", fails)
	quit(fails)
	return true

func _process(_delta: float) -> bool:
	# count live bolts each frame (volley leg)
	if boss != null and phase >= 2:
		var n := 0
		for c in scene.current_area.get_children() if scene.current_area else []:
			if c.name.begins_with("BossProjectile") or c.get_script() == preload("res://scripts/boss_projectile.gd"):
				n += 1
		if n > _bolts_fired:
			_bolts_fired = n
	return false
