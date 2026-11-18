extends SceneTree
## #98 (Foundation E1) harness: EnemyDefinition resource - stats + reward
## table per enemy type, required on every enemy scene.
##
## Legs:
##   (a) the Mustache Warrior scene carries its definition with the exact
##       current stats.
##   (b) enemy WITH a definition uses the definition's stats as a set.
##   (c) definition reward_table rolls identically to a directly assigned
##       table (same drop result on death).
##   (d) BOTH assigned: the direct reward_table WINS (instance override).
##   (e) null everywhere: no drop (existing null behavior preserved).
## Fail-when-broken: (b)/(c)/(d) fail on current main (no definition
## support) - exercised stringly via load()/set()/get() so the harness
## RUNS on the old base and reports FAIL legs instead of a parse error.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[98] ", name, " -> PASS")
	else:
		failures += 1
		print("[98] ", name, " -> FAIL")

func _drop_labels(parent: Node) -> Array:
	var out: Array = []
	for c in parent.get_children():
		if c.has_node("NameLabel"):
			out.append(c.get_node("NameLabel").text)
	return out

func _initialize() -> void:
	var def_script: Script = load("res://game/enemies/enemy_definition.gd")
	_check(def_script != null, "EnemyDefinition resource script exists")
	var enemy_scene: PackedScene = load("res://game/enemies/enemy.tscn")
	# Single-entry fixture table BUILT IN CODE (Placeholder Bolt). The
	# production demo_table.tres is content-owned data - #212 added the
	# summon spell entry - so loading it here would couple these exact-roll
	# assertions to unrelated content changes.
	var fix_entry_script: Script = load("res://game/economy/reward_entry.gd")
	var fix_table_script: Script = load("res://game/economy/reward_table.gd")
	var bolt_entry: Resource = fix_entry_script.new()
	bolt_entry.set("spell", load("res://data/spells/placeholder_bolt.tres"))
	bolt_entry.set("weight", 1.0)
	var demo_table: Resource = fix_table_script.new()
	demo_table.set("entries", Array([bolt_entry], TYPE_OBJECT, "Resource", fix_entry_script))
	_check(demo_table != null, "single-entry fixture reward table (Placeholder Bolt)")
	if def_script == null or enemy_scene == null or demo_table == null:
		print("[98] DONE failures=", failures)
		quit(failures)
		return

	# (a) the scene's own definition -> exact current stats.
	# NOTE: _ready defers to the first frame in a SceneTree harness, so
	# hp init and definition overrides are read AFTER a process frame.
	var e1: Node = enemy_scene.instantiate()
	root.add_child(e1)
	await process_frame
	_check(e1.get("definition") != null and e1.get("definition").resource_path == "res://data/enemies/mustache_warrior.tres", "(a) scene carries the mustache_warrior definition")
	_check(e1.get("max_hp") == 30 and e1.get("hp") == 30, "(a) max_hp/hp 30 unchanged")
	_check(is_equal_approx(e1.get("speed"), 110.0), "(a) speed 110 unchanged")
	_check(e1.get("contact_damage") == 10, "(a) contact_damage 10 unchanged")
	_check(is_equal_approx(e1.get("contact_cooldown"), 0.8), "(a) contact_cooldown 0.8 unchanged")
	_check(is_equal_approx(e1.get("contact_range"), 40.0), "(a) contact_range 40 unchanged")

	# (b) definition stats take effect as a set (assigned before _ready).
	var def_b: Resource = def_script.new()
	def_b.set("max_hp", 55)
	def_b.set("speed", 140.0)
	def_b.set("contact_damage", 7)
	def_b.set("contact_cooldown", 1.5)
	def_b.set("contact_range", 60.0)
	var e2: Node = enemy_scene.instantiate()
	e2.set("definition", def_b)
	root.add_child(e2)
	await process_frame
	_check(e2.get("max_hp") == 55 and e2.get("hp") == 55, "(b) definition max_hp 55 takes effect (hp init from definition)")
	_check(is_equal_approx(e2.get("speed"), 140.0), "(b) definition speed 140 takes effect")
	_check(e2.get("contact_damage") == 7, "(b) definition contact_damage 7 takes effect")
	_check(is_equal_approx(e2.get("contact_cooldown"), 1.5), "(b) definition contact_cooldown 1.5 takes effect")
	_check(is_equal_approx(e2.get("contact_range"), 60.0), "(b) definition contact_range 60 takes effect")
	e2.apply_damage(10)
	_check(e2.get("hp") == 45, "(b) damage applies against definition-based hp (55-10=45)")

	# (c) definition reward_table rolls identically to direct assignment.
	var area := Node2D.new()
	root.add_child(area)
	var def_c: Resource = def_script.new()
	def_c.set("reward_table", demo_table)
	var e_def: Node = enemy_scene.instantiate()
	e_def.set("definition", def_c)
	e_def.position = Vector2(100, 100)
	var e_dir: Node = enemy_scene.instantiate()
	e_dir.set("reward_table", demo_table)
	e_dir.position = Vector2(200, 100)
	area.add_child(e_def)
	area.add_child(e_dir)
	await process_frame # let _ready init hp before the kills
	e_def.apply_damage(999)
	e_dir.apply_damage(999)
	await process_frame
	await process_frame
	var labels := _drop_labels(area)
	print("[98] (c) drops: ", labels)
	_check(labels.size() == 2, "(c) both definition-only and direct-only enemies drop")
	_check(labels.count("Placeholder Bolt") == 2, "(c) definition reward rolls identically to direct assignment (same entry)")

	# (d) BOTH assigned: direct reward_table WINS (instance override).
	var entry_script: Script = load("res://game/economy/reward_entry.gd")
	var table_script: Script = load("res://game/economy/reward_table.gd")
	var other_entry: Resource = entry_script.new()
	other_entry.set("spell", load("res://data/spells/fire_ball.tres"))
	other_entry.set("weight", 1.0)
	var other_table: Resource = table_script.new()
	# Typed Array[RewardEntry] - a plain array is rejected by the export type.
	other_table.set("entries", Array([other_entry], TYPE_OBJECT, "Resource", entry_script))
	_check(other_table.get("entries").size() == 1, "(d) fixture table built with Fire Ball entry")
	var def_d: Resource = def_script.new()
	def_d.set("reward_table", demo_table) # definition says Placeholder Bolt
	var e_both: Node = enemy_scene.instantiate()
	e_both.set("definition", def_d)
	e_both.set("reward_table", other_table) # direct says Fire Ball
	e_both.position = Vector2(300, 100)
	area.add_child(e_both)
	await process_frame # _ready hp init before the kill
	e_both.apply_damage(999)
	await process_frame
	await process_frame
	labels = _drop_labels(area)
	print("[98] (d) drops: ", labels)
	_check(labels.count("Fire Ball") == 1, "(d) direct reward_table WINS over definition table (both assigned)")
	_check(labels.count("Placeholder Bolt") == 2, "(d) definition table did not roll while direct assigned")

	# (e) null everywhere: definition without a table + no direct table
	# -> no drop (existing null behavior preserved).
	var def_e: Resource = def_script.new()
	var e_none: Node = enemy_scene.instantiate()
	e_none.set("definition", def_e)
	e_none.position = Vector2(400, 100)
	area.add_child(e_none)
	await process_frame # _ready hp init before the kill
	e_none.apply_damage(999)
	await process_frame
	await process_frame
	labels = _drop_labels(area)
	_check(labels.size() == 3, "(e) null definition table + no direct table -> no drop (null behavior preserved)")

	await _test_fishy_audio()
	await _test_scorpion()
	await _test_desert_group()

	if failures == 0:
		print("[98] PASS")
	else:
		print("[98] DONE failures=", failures)
	quit(failures)


func _test_fishy_audio() -> void:
	var p: Player = load("res://game/player/player.tscn").instantiate()
	root.add_child(p)
	var fish: Enemy = load("res://game/enemies/enemy_fishy.tscn").instantiate()
	root.add_child(fish)
	var second: Enemy = load("res://game/enemies/enemy_fishy.tscn").instantiate()
	root.add_child(second)
	fish.set_physics_process(false)
	second.set_physics_process(false)
	var audio := fish.get_node("FishyAudio") as FishyAudio
	var other := second.get_node("FishyAudio") as FishyAudio
	audio.set_physics_process(false)
	other.set_physics_process(false)
	await process_frame
	fish._player = p
	second._player = p
	fish.position = p.position + Vector2(200, 0)
	second.position = fish.position
	var behavior := fish._behavior as EnemyBehaviorFishy
	var other_behavior := second._behavior as EnemyBehaviorFishy
	behavior.notice_radius = 100.0
	behavior.leash_radius = 500.0
	behavior.home = fish.global_position
	behavior._update_engaged(fish, p, true)
	other_behavior.engaged = false
	audio._idle_left = 0.0
	other._idle_left = 0.0
	audio.step(0.01)
	other.step(0.01)
	_check(audio.whistle_count == 1 and audio._whistle.playing, "Fishy: actual unaware guard starts full whistle nearby")
	_check(other.whistle_count == 0, "Fishy: global one-whistler cap")
	_check(not audio._whistle.stream.loop and absf(audio._whistle.stream.get_length() - 16.4) < 0.02, "Fishy: approved full nonlooping B2 melody")
	_check(audio._idle_left >= 46.3 and audio._idle_left <= 66.4, "Fishy: full cue plus 30-50s quiet spacing")
	behavior.notice_radius = INF
	behavior._update_engaged(fish, p, true)
	audio.step(0.01)
	_check(not audio._whistle.playing, "Fishy: real dungeon awareness stops whistle")
	behavior.notice_radius = 100.0
	behavior.engaged = false
	audio._idle_left = 0.0
	audio.step(0.01)
	p.position += Vector2(1500, 0)
	audio.step(0.01)
	_check(not audio._whistle.playing, "Fishy: range exit stops whistle")
	p.position = fish.position - Vector2(800, 0)
	audio.step(0.01)
	_check(audio._whistle.playing, "Fishy: whistle starts at once on entering 800 px range")
	p.position = Vector2.ZERO
	behavior._begin_windup(fish, p)
	audio.step(0.01)
	_check(audio.cast_count == 0, "Fishy: windup is not cast audio")
	behavior._windup(fish, p, true, behavior.windup_time)
	audio.step(0.01)
	audio.step(0.01)
	_check(audio.cast_count == 1 and audio._cast.playing, "Fishy: real CAST edge plays once")
	fish.freeze.apply(true)
	audio.step(0.01)
	_check(not audio._cast.playing and audio.cast_count == 1, "Fishy: freeze silences existing CAST without a new cast")
	fish.freeze.apply(false)
	audio.step(0.01)
	_check(audio.cast_count == 1 and not audio._cast.playing, "Fishy: thaw in same CAST does not replay one-shot")
	behavior._end_cast(fish, &"miss")
	audio.step(0.01)
	behavior._begin_windup(fish, p)
	audio.step(0.01)
	behavior._windup(fish, p, true, behavior.windup_time)
	audio.step(0.01)
	_check(audio.cast_count == 2 and audio._cast.playing, "Fishy: genuine next CAST still plays once after thaw")
	behavior._begin_hooked(fish, p)
	audio.step(0.01)
	_check(audio.reel_count == 1 and audio._reel.playing and not audio._reel.stream.loop, "Fishy: real HOOKED starts nonlooping reel")
	audio.step(0.2)
	_check(audio.reel_count == 1, "Fishy: no frame-by-frame reel retrigger")
	audio.step(1.3)
	_check(audio.reel_count == 2, "Fishy: reel repeats with natural gap")
	for reason in [&"reeled", &"dash", &"blocked", &"timeout", &"stalled", &"dead", &"terrain", &"miss"]:
		behavior._end_cast(fish, reason)
		audio.step(0.01)
		_check(not audio._reel.playing, "Fishy: reel stops on " + String(reason))
		behavior._begin_hooked(fish, p)
		audio.step(0.01)
	p.hp = 0
	audio.step(0.01)
	_check(not audio._cast.playing and not audio._reel.playing and not audio._whistle.playing, "Fishy: player death silences all voices")
	p.hp = 100
	fish.hp = 0
	audio.step(0.01)
	_check(not audio._cast.playing and not audio._reel.playing, "Fishy: enemy death silences voices")
	fish.free()
	second.free()
	p.free()

## Scorpion core contract: type-local concealment, hit resolution and attack
## state timing. No content-count/tuning-only harness is added.
func _test_scorpion() -> void:
	var area := Node2D.new()
	root.add_child(area)
	current_scene = area
	var p: Player = load("res://game/player/player.tscn").instantiate()
	area.add_child(p)
	p.set_physics_process(false)
	p.global_position = Vector2(200,0)
	var e: EnemyScorpion = load("res://game/enemies/enemy_scorpion.tscn").instantiate()
	e.player_path = NodePath("../"+p.name)
	area.add_child(e)
	e.set_physics_process(false)
	await process_frame
	var b := e._behavior as EnemyBehaviorScorpion
	_check(b != null and e.hp == 500 and e.buried,"definition + initial buried state")
	e.apply_damage(99)
	_check(e.hp == 500 and not HitContext.targetable(e),"hidden refuses damage and targeting")
	b.physics_step(e,p,0.01)
	_check(b.state == b.State.BURROW_RUSH,"nearby player triggers rush")
	p.position = Vector2(180,0)
	b.physics_step(e,p,0.01)
	_check(b.state == b.State.EMERGE and not e.buried,"rush reaches sting range and emerges")
	b.physics_step(e,p,0.30)
	_check(b.state == b.State.CHARGE_WINDUP,"300ms emerge -> charge tell")
	b.physics_step(e,p,0.17)
	_check(b.state == b.State.CHARGE_WINDUP,"initial tell remains before fast deadline")
	b.physics_step(e,p,0.01)
	_check(b.state == b.State.CHARGE,"initial fast locked tell -> body charge")
	_check(b.charge_windup_duration() == b.CHARGE_WINDUP_TIME,"later charges retain normal windup")
	p.position = Vector2(0,500)
	for i in 21: b.physics_step(e,p,1.0/60.0)
	_check(b.state in [b.State.PINCER_STRIKE,b.State.PINCER_RECOVER],"charge -> immediate pincer follow-up")
	b._enter(e,b.State.MISS_STUN)
	_check(e.sprite.frame == 2 and not e.sprite.is_playing(),"miss holds forward strike pose")
	var tip := e.stinger_tip()
	var shell := HitContext.projectile(e.global_position+Vector2(-100,0),e.global_position+Vector2(-100,0),1)
	var weak := HitContext.projectile(tip,tip,1)
	var aoe := HitContext.area(e.global_position,1)
	var rng := RandomNumberGenerator.new()
	_check(DamageCalc.compute(100,null,e.modifiers_for_hit(shell),rng).amount == 100,"grounded body loses shell reduction")
	_check(DamageCalc.compute(100,null,e.modifiers_for_hit(weak),rng).amount == 100,"grounded shell drop is not location-specific")
	_check(DamageCalc.compute(100,null,e.modifiers_for_hit(aoe),rng).amount == 100,"all AoE bypasses shell")
	var f := e.sprite.frame
	e.apply_calculated_damage(1)
	_check(e.sprite.frame == f and e.sprite.current_action() == &"attack","damage preserves miss pose")
	b.physics_step(e,p,0.97)
	_check(b.state == b.State.MISS_STUN,"stun holds before1s")
	b.physics_step(e,p,0.03)
	_check(b.state == b.State.CHASE,"stun ends at1s")
	p.position = e.position+Vector2(20,0)
	b.physics_step(e,p,0.01)
	_check(b.state == b.State.STING_WINDUP,"close -> stationary sting")
	var stationary_position := e.position
	b.physics_step(e,p,0.4)
	b.physics_step(e,p,0.01)
	_check(e.position == stationary_position,"point-blank hop never travels through player")
	b._enter(e,b.State.PINCER_WINDUP)
	b.physics_step(e,p,0.52)
	_check(b.state == b.State.PINCER_STRIKE,"pincer impact at520ms")
	p.set_invulnerable(false)
	var hp := p.hp
	b.physics_step(e,p,0.01)
	_check(p.hp == hp-15,"pincer applies15 through shared damage")
	b.physics_step(e,p,0.06)
	b.physics_step(e,p,0.32)
	p.position = e.position+Vector2(1000,0)
	b.physics_step(e,p,2.0)
	_check(b.state == b.State.BURY,"out of range2s -> bury")
	b.physics_step(e,p,0.30)
	_check(b.state == b.State.BURIED and e.hp == 499,"bury hides without healing")

	# Computed shell damage is never reduced twice; raw unlocated damage is.
	e.set_buried(false)
	b._enter(e,b.State.CHASE)
	e.hp = 100
	var expected := DamageCalc.compute(25.0,null,e.damage_modifiers,e.damage_rng).amount
	e.apply_damage(25)
	_check(e.hp == 100-expected,"scorpion: raw/unlocated damage stays armored")
	e.hp = 100
	e.apply_calculated_damage(expected)
	_check(e.hp == 100-expected,"scorpion: calculated damage not armored twice")
	b._enter(e,b.State.MISS_STUN)
	e.set_frozen(true)
	var clock := b._time
	e._physics_process(0.4)
	_check(b._time == clock,"scorpion: freeze pauses miss timer")
	e.set_frozen(false)
	_check(e.sprite.frame == 2 and not e.sprite.is_playing(),"scorpion: thaw preserves held forward stinger")
	# Real projectile path reaches tip-only geometry outside the body circle.
	b._enter(e,b.State.MISS_STUN)
	e.face_player(Vector2.RIGHT)
	e.play_action(&"attack",true)
	e.sprite.set_frame_and_progress(2,0.0)
	e.sprite.pause()
	e.hp = 100
	await physics_frame
	await physics_frame
	var spell := Spell.new()
	spell.damage = 10.0
	spell.radius = 1.0
	spell.range = 1000.0
	var shot: Projectile = load("res://game/spells/projectile.tscn").instantiate()
	shot.setup(spell,Vector2.DOWN,p)
	area.add_child(shot)
	shot.set_physics_process(false)
	var tip_now := e.stinger_tip()
	shot.global_position = tip_now + Vector2(0,40)
	shot._sweep_segment(tip_now-Vector2(0,40),Vector2(0,80))
	_check(e.hp == 100,"scorpion: removed tip collider does not receive tip-only projectile")
	var body_shot: Projectile = load("res://game/spells/projectile.tscn").instantiate()
	body_shot.setup(spell,Vector2.DOWN,p)
	area.add_child(body_shot)
	body_shot.set_physics_process(false)
	body_shot.global_position = e.position+Vector2(0,-40)
	body_shot._sweep_segment(e.position+Vector2(0,40),Vector2(0,-80))
	_check(e.hp == 90,"scorpion: real BODY projectile while grounded deals full10 damage")
	# Rendered suffix overrides aim during a terrain-path detour. Coordinates
	# below were independently captured from the committed Python pixel rig.
	e.facing = Vector2.RIGHT
	_check_scorpion_pose(e,&"idle_s",[[77,54],[78,56],[77,56],[76,54]])
	_check_scorpion_pose(e,&"idle_se",[[75,47],[76,49],[75,49],[75,48]])
	_check_scorpion_pose(e,&"idle_e",[[68,43],[68,44],[68,45],[68,44]])
	_check_scorpion_pose(e,&"idle_ne",[[58,44],[57,45],[58,46],[58,45]])
	_check_scorpion_pose(e,&"idle_n",[[51,49],[50,51],[51,51],[52,49]])
	_check_scorpion_pose(e,&"idle_nw",[[53,56],[52,58],[53,58],[53,55]])
	_check_scorpion_pose(e,&"idle_w",[[60,60],[60,62],[60,62],[60,59]])
	_check_scorpion_pose(e,&"idle_sw",[[70,59],[71,61],[70,61],[70,59]])
	_check_scorpion_pose(e,&"walk_s",[[77,54],[78,54],[77,54],[76,54],[75,54]])
	_check_scorpion_pose(e,&"walk_se",[[75,47],[76,47],[76,47],[75,48],[74,48]])
	_check_scorpion_pose(e,&"walk_e",[[68,43],[68,42],[68,43],[68,44],[68,44]])
	_check_scorpion_pose(e,&"walk_ne",[[58,44],[57,43],[57,44],[58,44],[59,45]])
	_check_scorpion_pose(e,&"walk_n",[[51,49],[50,49],[51,49],[52,49],[53,49]])
	_check_scorpion_pose(e,&"walk_nw",[[53,56],[52,56],[52,56],[53,55],[54,55]])
	_check_scorpion_pose(e,&"walk_w",[[60,60],[60,61],[60,60],[60,59],[60,59]])
	_check_scorpion_pose(e,&"walk_sw",[[70,59],[71,60],[71,60],[70,59],[69,59]])
	_check_scorpion_pose(e,&"attack_s",[[77,54],[74,71],[64,118],[73,82],[77,54]])
	_check_scorpion_pose(e,&"attack_se",[[75,47],[82,63],[101,108],[87,73],[75,47]])
	_check_scorpion_pose(e,&"attack_e",[[68,43],[80,54],[116,84],[88,61],[68,43]])
	_check_scorpion_pose(e,&"attack_ne",[[58,44],[68,48],[101,60],[75,51],[58,44]])
	_check_scorpion_pose(e,&"attack_n",[[51,49],[54,50],[64,50],[55,51],[51,49]])
	_check_scorpion_pose(e,&"attack_nw",[[53,56],[46,58],[27,60],[41,59],[53,56]])
	_check_scorpion_pose(e,&"attack_w",[[60,60],[48,67],[12,84],[40,72],[60,60]])
	_check_scorpion_pose(e,&"attack_sw",[[70,59],[60,72],[27,108],[53,81],[70,59]])
	_check_scorpion_pose(e,&"hurt_s",[[77,53],[77,54],[77,54]])
	_check_scorpion_pose(e,&"hurt_se",[[74,47],[75,47],[75,47]])
	_check_scorpion_pose(e,&"hurt_e",[[66,43],[68,43],[68,43]])
	_check_scorpion_pose(e,&"hurt_ne",[[56,45],[58,44],[58,44]])
	_check_scorpion_pose(e,&"hurt_n",[[51,50],[51,49],[51,49]])
	_check_scorpion_pose(e,&"hurt_nw",[[54,57],[53,56],[53,56]])
	_check_scorpion_pose(e,&"hurt_w",[[62,60],[60,60],[60,60]])
	_check_scorpion_pose(e,&"hurt_sw",[[72,58],[70,59],[70,59]])
	_check_scorpion_pose(e,&"death_s",[[77,54],[80,60],[83,66],[86,72],[89,79]])
	_check_scorpion_pose(e,&"death_se",[[75,47],[77,52],[78,57],[79,62],[81,67]])
	_check_scorpion_pose(e,&"death_e",[[68,43],[66,48],[65,53],[64,58],[62,63]])
	_check_scorpion_pose(e,&"death_ne",[[58,44],[54,50],[51,56],[48,63],[45,69]])
	_check_scorpion_pose(e,&"death_n",[[51,49],[48,57],[45,65],[42,73],[39,81]])
	_check_scorpion_pose(e,&"death_nw",[[53,56],[51,65],[50,74],[49,83],[47,92]])
	_check_scorpion_pose(e,&"death_w",[[60,60],[62,69],[63,78],[64,87],[66,96]])
	_check_scorpion_pose(e,&"death_sw",[[70,59],[74,67],[77,75],[80,83],[83,91]])
	_check_scorpion_pose(e,&"pincer_s",[[77,54],[77,52],[77,55],[77,54],[77,54]])
	_check_scorpion_pose(e,&"pincer_se",[[75,47],[73,46],[76,48],[76,48],[75,47]])
	_check_scorpion_pose(e,&"pincer_e",[[67,43],[64,43],[68,43],[68,43],[68,43]])
	_check_scorpion_pose(e,&"pincer_ne",[[57,44],[55,46],[58,44],[58,44],[58,44]])
	_check_scorpion_pose(e,&"pincer_n",[[51,50],[51,52],[51,49],[51,49],[51,49]])
	_check_scorpion_pose(e,&"pincer_nw",[[53,56],[55,57],[52,55],[52,56],[53,56]])
	_check_scorpion_pose(e,&"pincer_w",[[61,60],[64,60],[60,60],[60,60],[60,60]])
	_check_scorpion_pose(e,&"pincer_sw",[[71,59],[73,57],[70,60],[70,59],[70,59]])
	_check_scorpion_pose(e,&"emerge_s",[[-1,-1],[79,78],[79,67],[77,58],[74,54],[77,54]])
	_check_scorpion_pose(e,&"emerge_se",[[-1,-1],[77,70],[77,59],[75,51],[73,49],[75,47]])
	_check_scorpion_pose(e,&"emerge_e",[[-1,-1],[68,65],[68,54],[68,47],[68,45],[68,43]])
	_check_scorpion_pose(e,&"emerge_ne",[[-1,-1],[56,67],[56,56],[58,48],[60,45],[58,44]])
	_check_scorpion_pose(e,&"emerge_n",[[-1,-1],[49,73],[49,62],[51,53],[54,49],[51,49]])
	_check_scorpion_pose(e,&"emerge_nw",[[-1,-1],[51,81],[51,70],[53,60],[55,54],[53,56]])
	_check_scorpion_pose(e,&"emerge_w",[[-1,-1],[60,86],[60,75],[60,64],[60,58],[60,60]])
	_check_scorpion_pose(e,&"emerge_sw",[[-1,-1],[72,84],[72,73],[70,63],[68,58],[70,59]])
	_check_scorpion_pose(e,&"bury_s",[[77,54],[74,54],[77,58],[79,67],[79,78],[-1,-1]])
	_check_scorpion_pose(e,&"bury_se",[[75,47],[73,49],[75,51],[77,59],[77,70],[-1,-1]])
	_check_scorpion_pose(e,&"bury_e",[[68,43],[68,45],[68,47],[68,54],[68,65],[-1,-1]])
	_check_scorpion_pose(e,&"bury_ne",[[58,44],[60,45],[58,48],[56,56],[56,67],[-1,-1]])
	_check_scorpion_pose(e,&"bury_n",[[51,49],[54,49],[51,53],[49,62],[49,73],[-1,-1]])
	_check_scorpion_pose(e,&"bury_nw",[[53,56],[55,54],[53,60],[51,70],[51,81],[-1,-1]])
	_check_scorpion_pose(e,&"bury_w",[[60,60],[60,58],[60,64],[60,75],[60,86],[-1,-1]])
	_check_scorpion_pose(e,&"bury_sw",[[70,59],[68,58],[70,63],[72,73],[72,84],[-1,-1]])
	e.face_player(Vector2.RIGHT)
	# Grounded body vulnerability and accepted-player miss-only extension.
	b._enter(e,b.State.MISS_STUN)
	_check(e.is_stunned() and e.stinger_grounded(),"stun: grounded miss status")
	var halo := e.get_node("StunHalo") as EnemyStunHalo
	halo._process(0.0)
	_check(halo.visible and halo.is_playing() and halo.position == e.stun_halo_position(),"stun: grounded miss shows halo")
	b.physics_step(e,p,0.4)
	var body_hit := HitContext.projectile(e.position,e.position,1.0)
	_check(DamageCalc.compute(100,null,e.modifiers_for_hit(body_hit),e.damage_rng).amount == 100,"armor: grounded BODY hit unreduced")
	var hp_grounded := e.hp
	e.apply_damage(10)
	_check(e.hp == hp_grounded-10,"armor: raw body damage also loses shell while grounded")
	e.apply_calculated_damage(1,0,body_hit)
	e.apply_calculated_damage(1,0,body_hit)
	_check(b._miss_duration == 1.0 and b._time == 0.4,"stun: unattributed raw/calculated calls cannot extend miss")
	b.physics_step(e,p,0.59)
	_check(e.is_stunned(),"stun: miss remains before1s")
	b.physics_step(e,p,0.02)
	_check(not e.is_stunned(),"stun: miss ends after1s without accepted player event")
	# Actual shared splash/body delivery authenticates attacker and acceptance.
	b._enter(e,b.State.MISS_STUN)
	b.physics_step(e,p,0.4)
	var small_spell := Spell.new()
	small_spell.damage = 1.0
	var enemy_attacker := Node2D.new()
	area.add_child(enemy_attacker)
	WaterSplash.deal_damage(e,small_spell,enemy_attacker,OnHit.DELIVERY_SPLASH,HitContext.area(e.position,40))
	_check(b._miss_duration == 1.0,"stun: non-player accepted AoE cannot extend")
	WaterSplash.deal_damage(e,small_spell,p,OnHit.DELIVERY_SPLASH,HitContext.area(e.position,40))
	_check(b._miss_duration == 3.0 and b._time == 0.4,"stun: first accepted player AoE adds2s without resetting elapsed")
	WaterSplash.deal_damage(e,small_spell,p,OnHit.DELIVERY_SPLASH,HitContext.area(e.position,40))
	_check(b._miss_duration == 3.0,"stun: repeated player AoE does not stack")
	e.set_frozen(true)
	e._physics_process(1.0)
	_check(b._time == 0.4,"stun: freeze holds extended deadline clock")
	e.set_frozen(false)
	b.physics_step(e,p,2.59)
	_check(e.is_stunned(),"stun: extended episode persists until3s")
	b.physics_step(e,p,0.02)
	_check(not e.is_stunned(),"stun: extended episode ends after3s")
	b._enter(e,b.State.MISS_STUN)
	var direct_shot: Projectile = load("res://game/spells/projectile.tscn").instantiate()
	direct_shot.setup(small_spell,Vector2.RIGHT,p)
	area.add_child(direct_shot)
	direct_shot.set_physics_process(false)
	direct_shot._resolve_body_hit(e,HitContext.projectile(e.position,e.position,1))
	_check(b._miss_duration == 3.0,"stun: new miss re-arms for actual player BODY projectile")
	b._enter(e,b.State.MISS_STUN)
	var zero_spell := small_spell.duplicate() as Spell
	zero_spell.damage = 0.0
	WaterSplash.deal_damage(e,zero_spell,p,OnHit.DELIVERY_SPLASH,HitContext.area(e.position,40))
	_check(b._miss_duration == 3.0,"stun: accepted zero player roll still qualifies under OnHit")
	b._enter(e,b.State.CHASE)
	e.stun(0.4)
	var generic_before := e.stun_left
	WaterSplash.deal_damage(e,small_spell,p,OnHit.DELIVERY_SPLASH,HitContext.area(e.position,40))
	_check(e.stun_left == generic_before,"stun: generic stun never gains missed-sting bonus")
	e.stun_left = 0.0
	e._hold_grounded_stinger()
	halo._process(0.0)
	_check(not halo.visible and not halo.is_playing(),"stun: halo stops on expiry")
	b._enter(e,b.State.RECOVER)
	_check(not e.stinger_grounded() and DamageCalc.compute(100,null,e.modifiers_for_hit(body_hit),e.damage_rng).amount in [19,20],"armor: lifting recovery regains shell")
	_check(DamageCalc.compute(100,null,e.modifiers_for_hit(HitContext.area(e.position,1)),e.damage_rng).amount == 100,"armor: AoE still bypasses raised shell")
	b._enter(e,b.State.CHASE)
	e.play_action(&"attack",true)
	e.sprite.set_frame_and_progress(0,0.0)
	e.stun(0.4)
	_check(e.sprite.frame == 2 and not e.sprite.is_playing(),"stun: generic stun cancels raising into grounded strike pose")
	e.apply_calculated_damage(1)
	_check(e.sprite.frame == 2 and not e.sprite.is_playing(),"stun: hurt cannot raise grounded stinger")
	_check(e.is_stunned(),"stun: generic enemy stun uses same status hook")
	e.stun_left = 0.0
	e._hold_grounded_stinger()
	_check(e.sprite.frame == 0,"stun: generic hold releases original pose after expiry")
	# Telegraph is state-owned and predicts the body charge sweep, not
	# the unrelated tail-tip pose. Geometry stays aligned in every octant.
	b._enter(e,b.State.EMERGE)
	_check(e.charge_warning().is_empty(),"scorpion: emerge alone has no dash warning")
	for direction in [Vector2.RIGHT,Vector2(1,1).normalized(),Vector2.DOWN,Vector2(-1,1).normalized(),Vector2.LEFT,Vector2(-1,-1).normalized(),Vector2.UP,Vector2(1,-1).normalized()]:
		e.face_player(direction)
		b._aim = direction
		b._enter(e,b.State.CHARGE_WINDUP)
		var warning := e.charge_warning()
		_check(warning.direction == direction and warning.length == b.dash_distance+48.0 and warning.width == 48.0,"scorpion: warning uses actual dash sweep dimensions")
		e.sprite.set_frame_and_progress(2,0.0)
		_check(warning.origin.is_equal_approx(e.global_position-direction*24.0),"scorpion: warning tracks body charge envelope")
		b._enter(e,b.State.MISS_STUN)
		_check(e.charge_warning().is_empty(),"scorpion: warning clears outside windup")
	# The warning and charge execution share one clipped center path.
	e.position = Vector2.ZERO
	e.movement_constraint = func(point: Vector2) -> Vector2: return Vector2(minf(point.x,80.0),point.y)
	b._aim = Vector2.RIGHT
	b._enter(e,b.State.CHARGE_WINDUP)
	var constrained := e.charge_warning()
	_check(constrained.length == 128.0,"charge: warning clipped to constraint80 plus48caps")
	b._enter(e,b.State.CHARGE)
	for i in 20:
		if b.state == b.State.CHARGE: b.physics_step(e,p,1.0/60.0)
	_check(is_equal_approx(e.position.x,80.0) and b.state == b.State.PINCER_STRIKE,"charge: actual travel matches clipped warning then pincer")
	e.movement_constraint = Callable()
	e.position = Vector2.ZERO
	var wall := StaticBody2D.new()
	wall.position = Vector2(100,0)
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(10,300)
	shape.shape = box
	wall.add_child(shape)
	area.add_child(wall)
	b._aim = Vector2.RIGHT
	b._enter(e,b.State.CHARGE_WINDUP)
	await physics_frame
	await physics_frame
	var wall_length: float = e.charge_warning().length-48.0
	_check(wall_length > 70.0 and wall_length < 72.0,"charge: body sweep clips lane at physical wall")
	b._enter(e,b.State.CHARGE)
	for i in 20:
		if b.state == b.State.CHARGE: b.physics_step(e,p,1.0/60.0)
	_check(absf(e.position.x-wall_length)<0.1,"charge: physical wall execution matches warning")
	wall.free()
	e.position = Vector2.ZERO
	var map := TerrainMap.new()
	area.add_child(map)
	map.set_cell(Vector2i(2,0),TerrainTypes.MOUNTAIN)
	e.terrain = map
	b._aim = Vector2.RIGHT
	b._enter(e,b.State.CHARGE_WINDUP)
	var terrain_length: float = e.charge_warning().length-48.0
	b._enter(e,b.State.CHARGE)
	for i in 30:
		if b.state == b.State.CHARGE: b.physics_step(e,p,1.0/60.0)
	_check(terrain_length < 128.0 and absf(e.position.x-terrain_length)<0.1,"charge: terrain endpoint matches warning, never slides")
	e.terrain = null
	map.free()
	# Scene now has only body collision; grounded armor applies everywhere.
	_check(not e.has_node("StingerShape"),"armor: separate tip collider removed")
	b._enter(e,b.State.STING_STRIKE)
	e.face_player(Vector2.RIGHT)
	e.play_action(&"attack",true)
	e.sprite.set_frame_and_progress(2,0)
	e.sprite.pause()
	_check(e.stinger_grounded(),"armor: actual strike pose drops shell before stun")
	p.set_invulnerable(false)
	p.position = e.stinger_tip()
	b._aim = Vector2.RIGHT
	b._enter(e,b.State.STING_STRIKE)
	var before_strike := e.position
	var before_hp := p.hp
	b.physics_step(e,p,0.01)
	_check(e.position == before_strike and p.hp == before_hp-25,"sting: close stationary tip deals25 without charge movement")
	# Player i-frames refuse the sting and lead to miss, not success.
	p.position = e.stinger_tip()
	p.set_invulnerable(true)
	b._aim = Vector2.RIGHT
	b._enter(e,b.State.STING_STRIKE)
	for i in 21: b.physics_step(e,p,1.0/60.0)
	_check(b.state == b.State.MISS_STUN,"scorpion: i-frames count as sting miss")
	# Production sole-mover seam: a hooked charge submits drive, never moves twice.
	e.position = Vector2(650,0)
	p.position = Vector2.ZERO
	b._aim = Vector2.RIGHT
	b._enter(e,b.State.CHARGE_WINDUP)
	b._enter(e,b.State.CHARGE)
	var hook: Spell = load("res://data/spells/hook_shot.tres")
	var reel := HookReel.begin(area,e,p,hook)
	reel.set_physics_process(false)
	var held_before := e.position
	e._physics_process(1.0/60.0)
	_check(e.position == held_before and e.reel_propulsion.is_equal_approx(Vector2(900,0)),"charge reel: Enemy step submits900 propulsion without moving")
	var expected_velocity := Enemy.force_step(Vector2(900,0),Vector2.ZERO,reel.pull_force(e),e.weight,1.0/60.0,reel.pull_speed_limit(e))
	reel._physics_process(1.0/60.0)
	_check(e.position.is_equal_approx(held_before+expected_velocity/60.0),"charge reel: actual HookReel performs sole force-integrated move")
	_check(e.position.x > held_before.x and e.position.x < held_before.x+15.0,"charge reel: opposing pull slows rather than double-moves charge")
	_check(HookPullStack.contains(e,reel) and b.state == b.State.CHARGE,"charge reel: movement preserves ownership and charge state")
	# Perpendicular force also changes the one resolved step, not a flat slow.
	p.position = e.position+Vector2(0,-500)
	e.reel_force_velocity = Vector2.ZERO
	held_before = e.position
	e._physics_process(1.0/60.0)
	expected_velocity = Enemy.force_step(Vector2(900,0),Vector2.ZERO,reel.pull_force(e),e.weight,1.0/60.0,reel.pull_speed_limit(e))
	_check(e.position == held_before,"charge reel: perpendicular pull still samples without displacement")
	reel._physics_process(1.0/60.0)
	_check(e.position.is_equal_approx(held_before+expected_velocity/60.0) and e.position.y < held_before.y,"charge reel: actual pull deflects through force resolver")
	# Charge propulsion ends on its own budget even if a pull cancels progress.
	for i in 25:
		if b.state == b.State.CHARGE: e._physics_process(1.0/60.0)
	_check(b.state == b.State.PINCER_STRIKE,"charge reel: finite submitted budget still reaches immediate pincer")
	reel.free()
	# Opening at close range obeys the same stationary selection as chase.
	e.position = Vector2.ZERO
	p.position = Vector2(20,0)
	b._enter(e,b.State.BURIED)
	b.physics_step(e,p,0.01)
	b.physics_step(e,p,0.01)
	b.physics_step(e,p,0.30)
	_check(b.state == b.State.STING_WINDUP,"opening: close player selects stationary sting, not body charge")
	# Recheck range at charge launch, even after initial long-range selection.
	b._aim = Vector2.RIGHT
	b._enter(e,b.State.CHARGE_WINDUP)
	b.physics_step(e,p,0.4)
	_check(b.state == b.State.STING_WINDUP and e.charge_warning().is_empty(),"charge: close player at launch cancels charge for sting")
	# A70px target produces an18px toward hop to the52px spacing point.
	e.position = Vector2.ZERO
	p.position = Vector2(70,0)
	b._enter(e,b.State.STING_WINDUP)
	b.physics_step(e,p,0.399)
	_check(b.state == b.State.STING_WINDUP and e.position == Vector2.ZERO,"hop: full warning before any movement")
	b.physics_step(e,p,0.0011)
	_check(b.state == b.State.STING_HOP and not e.stinger_grounded(),"hop: windup enters raised-tail hop, not early strike")
	b.physics_step(e,p,0.035)
	_check(e.position.is_equal_approx(Vector2(18,0)) and e.sprite.position.y < -31.9,"hop: half-time stops short18px ground travel and12px visual arc")
	e.set_frozen(true)
	var hop_clock := b._time
	e._physics_process(0.2)
	_check(b._time == hop_clock and e.sprite.position.y < -31.9,"hop: freeze holds both clock and visual altitude")
	e.set_frozen(false)
	b.physics_step(e,p,0.035)
	_check(b.state == b.State.STING_STRIKE and e.position.is_equal_approx(Vector2(18,0)) and e.sprite.position.y == -20,"hop: lands short after0.07s then grounded strike")
	# A retreat during tell cannot turn hop into a long-range lunge.
	e.position = Vector2.ZERO
	p.position = Vector2(200,0)
	b._enter(e,b.State.STING_WINDUP)
	b.physics_step(e,p,0.4)
	b.physics_step(e,p,0.07)
	_check(e.position.is_equal_approx(Vector2(100,0)),"hop: retreating target caps total ground travel100")
	# Constraints clip the hop too; no wall slide or forbidden movement.
	e.position = Vector2.ZERO
	e.movement_constraint = func(point: Vector2) -> Vector2: return Vector2(minf(point.x,8.0),point.y)
	p.position = Vector2(70,0)
	b._enter(e,b.State.STING_WINDUP)
	b.physics_step(e,p,0.4)
	b.physics_step(e,p,0.07)
	_check(e.position.is_equal_approx(Vector2(8,0)) and b.state == b.State.STING_STRIKE,"hop: constraint clips travel without delaying impact")
	e.movement_constraint = Callable()
	# A real reel remains sole mover during the new hop as well.
	e.position = Vector2.ZERO
	p.position = Vector2(160,0)
	b._enter(e,b.State.STING_WINDUP)
	b.physics_step(e,p,0.4)
	reel = HookReel.begin(area,e,p,hook)
	reel.set_physics_process(false)
	held_before = e.position
	e._physics_process(1.0/60.0)
	_check(e.position == held_before and e.reel_propulsion.is_equal_approx(Vector2(b.HOP_DISTANCE/b.HOP_TIME,0)),"hop reel: samples ground drive without moving")
	expected_velocity = Enemy.force_step(Vector2(b.HOP_DISTANCE/b.HOP_TIME,0),e.reel_force_velocity,reel.pull_force(e),e.weight,1.0/60.0,reel.pull_speed_limit(e))
	reel._physics_process(1.0/60.0)
	_check(e.position.is_equal_approx(held_before+expected_velocity/60.0),"hop reel: real HookReel performs sole integrated move")
	reel.free()
	# New trigger boundary is shared by chase, opening and launch recheck.
	for separation in [160.0,160.1]:
		e.position = Vector2.ZERO
		p.position = Vector2(separation,0)
		b._sting_cd = 0.0
		b._charge_cd = 0.0
		b._enter(e,b.State.CHASE)
		b.physics_step(e,p,0.01)
		_check(b.state == (b.State.STING_WINDUP if separation == 160.0 else b.State.CHARGE_WINDUP),"sting: chase uses exact160 boundary")
		b._enter(e,b.State.BURIED)
		b.physics_step(e,p,0.01)
		b.physics_step(e,p,0.01)
		b.physics_step(e,p,0.30)
		_check(b.state == (b.State.STING_WINDUP if separation == 160.0 else b.State.CHARGE_WINDUP),"sting: opening uses exact160 boundary")
	b._enter(e,b.State.CHARGE_WINDUP)
	p.position = Vector2(160,0)
	b.physics_step(e,p,0.4)
	_check(b.state == b.State.STING_WINDUP,"sting: charge rechecks expanded160 radius at launch")
	b.physics_step(e,p,0.4)
	b.physics_step(e,p,0.07)
	_check(e.position.is_equal_approx(Vector2(100,0)) and b.state == b.State.STING_STRIKE,"hop:160 target closes100 to60 spacing, no overshoot")
	# Pursuit is selected only outside the surface charge band, after a
	# visible bury, then surfaces directly into the existing hop/strike.
	e.position = Vector2.ZERO
	e.set_buried(false)
	b._charge_cd = 0.0
	p.position = Vector2(300,0)
	b._enter(e,b.State.CHASE)
	b.physics_step(e,p,0.01)
	_check(b.state == b.State.CHARGE_WINDUP,"burrow:300 remains overground charge")
	for reach in [300.1,650.0]:
		e.position = Vector2.ZERO
		e.set_buried(false)
		p.position = Vector2(reach,0)
		b._enter(e,b.State.CHASE)
		b.physics_step(e,p,0.01)
		_check(b.state == b.State.BURY and not e.buried,"burrow:far in-band starts vulnerable bury")
		b.physics_step(e,p,0.299)
		_check(b.state == b.State.BURY,"burrow:bury cannot conceal before deadline")
		b.physics_step(e,p,0.0011)
		_check(b.state == b.State.BURROW_PURSUIT and e.buried and not HitContext.targetable(e),"burrow:full bury enters concealed pursuit")
	var safe_hp := e.hp
	e.apply_damage(10)
	e.apply_calculated_damage(10)
	_check(e.hp == safe_hp,"burrow:both HP entry points reject underground hits")
	e.position = Vector2.ZERO
	p.position = Vector2(400,0)
	var player_safe_hp := p.hp
	b._enter(e,b.State.BURROW_PURSUIT)
	b.physics_step(e,p,1.0/60.0)
	_check(e.position.is_equal_approx(Vector2(10,0)) and p.hp == player_safe_hp,"burrow:600px/s pursuit, no contact damage")
	p.position = e.position+Vector2(0,400)
	b.physics_step(e,p,1.0/60.0)
	_check(e.position.is_equal_approx(Vector2(10,10)),"burrow:tracks changed player position underground")
	e.set_frozen(true)
	var frozen_pos := e.position
	var frozen_clock := b._time
	e._physics_process(0.5)
	_check(e.position == frozen_pos and b._time == frozen_clock,"burrow:freeze holds pursuit movement and clock")
	e.set_frozen(false)
	e.position = Vector2.ZERO
	p.position = Vector2(165,0)
	b.physics_step(e,p,1.0/60.0)
	_check(e.position.is_equal_approx(Vector2(5,0)) and e.buried,"burrow:step stops exactly at160, no pass through")
	b.physics_step(e,p,1.0/60.0)
	_check(b.state == b.State.STING_HOP and not e.buried and b._burrow_hop,"burrow:at160 surfaces directly in hop, zero emerge/tell pause")
	var burrow_hop_origin := e.position
	b.physics_step(e,p,0.035)
	_check(e.position.x > burrow_hop_origin.x and e.sprite.position.y < -31.9 and p.hp == player_safe_hp,"burrow:emerging hop moves immediately, no damage until grounded")
	b.physics_step(e,p,0.035)
	_check(b.state == b.State.STING_STRIKE and e.position.is_equal_approx(burrow_hop_origin+Vector2(100,0)),"burrow:emerging hop lands after0.07s directly into existing sting")
	_check(not b._burrow_hop,"burrow:hop cue resets at strike")

	# Far disengage cannot retain an invisible chaser or re-wake at long range.
	e.position = Vector2.ZERO
	p.position = Vector2(650.1,0)
	b._enter(e,b.State.BURROW_PURSUIT)
	b.physics_step(e,p,1.99)
	_check(b.state == b.State.BURROW_PURSUIT and e.position == Vector2.ZERO,"burrow:beyond650 stops and honors disengage grace")
	b.physics_step(e,p,0.011)
	_check(b.state == b.State.BURIED,"burrow:far2s disengages to buried idle")
	b.physics_step(e,p,0.5)
	_check(b.state == b.State.BURIED,"burrow:idle wake remains300, not unlimited aggro")
	b._enter(e,b.State.BURROW_PURSUIT)
	b.physics_step(e,null,0.01)
	_check(b.state == b.State.BURIED,"burrow:lost/dead/hidden target safely stops pursuit")
	# External owner still samples once; it alone applies the integrated step.
	e.position = Vector2.ZERO
	p.position = Vector2(400,0)
	b._enter(e,b.State.BURROW_PURSUIT)
	# A reel attached above ground remains sole mover through concealment.
	e.set_buried(false)
	e.reel_force_velocity = Vector2.ZERO
	var burrow_reel := HookReel.begin(area,e,p,hook)
	burrow_reel.set_physics_process(false)
	b._enter(e,b.State.BURROW_PURSUIT)
	e._physics_process(1.0/60.0)
	_check(e.position == Vector2.ZERO and e.reel_propulsion.is_equal_approx(Vector2(600,0)),"burrow:external owner samples600 propulsion with zero self move")
	var burrow_velocity := Enemy.force_step(Vector2(600,0),Vector2.ZERO,burrow_reel.pull_force(e),e.weight,1.0/60.0,burrow_reel.pull_speed_limit(e))
	burrow_reel._physics_process(1.0/60.0)
	_check(e.position.is_equal_approx(burrow_velocity/60.0),"burrow:real HookReel performs sole force-integrated move")
	burrow_reel.free()
	e.position = Vector2.ZERO
	p.position = Vector2(400,0)
	e.movement_constraint = func(point:Vector2)->Vector2:return Vector2(minf(point.x,25.0),point.y)
	b._enter(e,b.State.BURROW_PURSUIT)
	for i in 10:e._physics_process(1.0/60.0)
	_check(e.position == Vector2(25,0),"burrow:production constraint clamps underground travel")
	e.movement_constraint = Callable()
	var burrow_map := TerrainMap.new()
	area.add_child(burrow_map)
	for y in range(-2,3):burrow_map.set_cell(Vector2i(2,y),TerrainTypes.MOUNTAIN)
	e.terrain = burrow_map
	e.position = Vector2(32,32)
	p.position = Vector2(432,32)
	b._enter(e,b.State.BURROW_PURSUIT)
	var terrain_safe := true
	var detour := false
	for i in 90:
		if b.state != b.State.BURROW_PURSUIT:break
		e._physics_process(1.0/60.0)
		terrain_safe = terrain_safe and TerrainMotion.can_enter(burrow_map,e.position,false)
		detour = detour or absf(e.position.y-32.0)>32.0
	_check(terrain_safe and detour,"burrow:routes around blocking terrain, never enters mountain")
	e.terrain = null
	burrow_map.free()

	area.free()

func _check_scorpion_pose(e: EnemyScorpion, animation: StringName, pixels: Array) -> void:
	e.sprite.play(animation)
	e.sprite.pause()
	for k in pixels.size():
		e.sprite.set_frame_and_progress(k,0.0)
		var expected := Vector2(pixels[k][0],pixels[k][1])
		if expected.x < 0:
			_check(not e.stinger_exposed(),"scorpion: sand-only pose has no exposed weakspot " + String(animation))
			continue
		if String(animation).begins_with("attack_"):
			_check(e.stinger_grounded() == (k == 2),"armor: grounded mapping follows attack frame2 in every octant")
		var actual := e.sprite.to_local(e.stinger_tip())+Vector2(64,64)
		_check(actual == expected,"scorpion: rendered tip follows source pose %s:%d" % [animation,k])
		var image := e.sprite.sprite_frames.get_frame_texture(animation,k).get_image()
		var color := image.get_pixelv(Vector2i(expected))
		var visible_tip := color.a > 0.0 and color.r < 0.68 and color.b > color.r
		_check(e.stinger_exposed() == visible_tip,"scorpion: occlusion follows actual pixel %s:%d" % [animation,k])

## Shared squad lifecycle and grenade-landing synchronization are otherwise
## silent core contracts; content tuning/visual poses are deliberately unpinned.
func _test_desert_group() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var p: Player = load("res://game/player/player.tscn").instantiate()
	p.name = "Player"
	world.add_child(p)
	p.set_physics_process(false)
	p.position = Vector2(-2000,0)
	var area := Node2D.new()
	world.add_child(area)
	var squad: DesertMustacheGroup = load("res://game/enemies/desert_mustache_group.tscn").instantiate()
	area.add_child(squad)
	squad.set_physics_process(false)
	for member in squad.members: member.set_physics_process(false)
	_check(squad.members.size() == 5,"desert: group scene owns exactly five independent enemies")
	_check(squad.members[0]._behavior != squad.members[1]._behavior,"desert: member behavior state is never shared")
	squad._physics_process(0.1)
	_check(squad.state == DesertMustacheGroup.State.TRAVEL,"desert: distant player keeps traveling formation")
	p.position = squad.leader.position+Vector2(200,0)
	squad._physics_process(0.1)
	_check(squad.state == DesertMustacheGroup.State.SPREAD,"desert: player approach spreads group")
	_check(squad.destination(squad.members[0]).distance_to(squad.destination(squad.members[4])) > 100,"desert: spread members have distinct separated destinations")
	squad._physics_process(squad.spread_seconds)
	_check(squad.state == DesertMustacheGroup.State.THROW,"desert: spread precedes leader throw")
	squad.leader.set_frozen(true)
	var clock := squad._clock
	squad._physics_process(2.0)
	_check(squad._clock == clock,"desert: frozen leader cannot advance throw clock")
	squad.leader.set_frozen(false)
	squad._physics_process(squad.throw_windup)
	_check(squad.state == DesertMustacheGroup.State.WAIT_SMOKE,"desert: throw does not immediately release charge")
	await process_frame
	_check(squad._grenade != null,"desert: deferred production grenade exists")
	for i in 45: await physics_frame
	_check(squad.state == DesertMustacheGroup.State.CHARGE,"desert: real cloud landing releases group charge")
	var old_leader := squad.leader
	old_leader.apply_damage(10000)
	squad._physics_process(0.01)
	_check(squad.leader != old_leader and is_instance_valid(squad.leader),"desert: surviving member inherits leadership")
	p.apply_damage(10000)
	squad._physics_process(0.01)
	_check(squad.state == DesertMustacheGroup.State.SMOKE_HOLD,"desert: target loss stays in live smoke")
	_check(squad._cloud.contains_smoke(squad.destination(squad.leader)),"desert: hold destination remains inside live puffs")
	squad._cloud.lifetime = 0.0
	squad._physics_process(0.01)
	_check(squad.state == DesertMustacheGroup.State.SCATTER,"desert: dissipated cloud releases scatter")
	for i in 90: await physics_frame
	world.queue_free()
	await process_frame
