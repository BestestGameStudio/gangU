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
	_check(b != null and e.hp == 100 and e.buried,"definition + initial buried state")
	e.apply_damage(99)
	_check(e.hp == 100 and not HitContext.targetable(e),"hidden refuses damage and targeting")
	b.physics_step(e,p,0.01)
	_check(b.state == b.State.BURROW_RUSH,"nearby player triggers rush")
	p.position = Vector2(100,0)
	b.physics_step(e,p,0.01)
	_check(b.state == b.State.EMERGE and not e.buried,"rush reaches sting range and emerges")
	b.physics_step(e,p,0.30)
	_check(b.state == b.State.STING_WINDUP,"300ms emerge -> sting tell")
	b.physics_step(e,p,0.36)
	_check(b.state == b.State.STING_DASH,"360ms locked tell -> dash")
	p.position = Vector2(0,500)
	for i in 21: b.physics_step(e,p,1.0/60.0)
	_check(b.state == b.State.MISS_STUN,"miss -> stun")
	_check(e.sprite.frame == 2 and not e.sprite.is_playing(),"miss holds forward strike pose")
	var tip := e.stinger_tip()
	var shell := HitContext.projectile(e.global_position+Vector2(-100,0),e.global_position+Vector2(-100,0),1)
	var weak := HitContext.projectile(tip,tip,1)
	var aoe := HitContext.area(e.global_position,1)
	var rng := RandomNumberGenerator.new()
	_check(DamageCalc.compute(100,null,e.modifiers_for_hit(shell),rng).amount in [19,20],"shell reduces damage80percent")
	_check(DamageCalc.compute(100,null,e.modifiers_for_hit(weak),rng).amount == 100,"actual tip bypasses shell")
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
	_check(b.state == b.State.PINCER_WINDUP,"close -> pincer")
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
	_check(b.state == b.State.BURIED and e.hp == 99,"bury hides without healing")

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
	b._enter(e,b.State.CHASE)
	e.face_player(Vector2.RIGHT)
	e.play_action(&"attack",true)
	e.sprite.set_frame_and_progress(2,0.0)
	e.sprite.pause()
	e.get_node("StingerShape").position = e.to_local(e.stinger_tip())
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
	_check(e.hp == 90,"scorpion: tip-only actual physics hit deals unreduced damage")
	# Rendered suffix overrides aim during a terrain-path detour. Coordinates
	# below were independently captured from the committed Python pixel rig.
	e.facing = Vector2.RIGHT
	_check_scorpion_pose(e,&"idle_s",[[39,24],[40,25],[39,25],[38,24]])
	_check_scorpion_pose(e,&"idle_se",[[38,21],[39,21],[38,22],[38,21]])
	_check_scorpion_pose(e,&"idle_e",[[34,18],[34,19],[34,19],[34,19]])
	_check_scorpion_pose(e,&"idle_ne",[[28,19],[28,20],[28,20],[29,19]])
	_check_scorpion_pose(e,&"idle_n",[[25,22],[24,23],[25,23],[26,22]])
	_check_scorpion_pose(e,&"idle_nw",[[26,25],[25,27],[26,26],[26,25]])
	_check_scorpion_pose(e,&"idle_w",[[30,28],[30,29],[30,29],[30,27]])
	_check_scorpion_pose(e,&"idle_sw",[[36,27],[36,28],[36,28],[35,27]])
	_check_scorpion_pose(e,&"walk_s",[[39,24],[40,24],[39,24],[39,24],[38,24]])
	_check_scorpion_pose(e,&"walk_se",[[38,21],[39,20],[39,20],[38,21],[38,21]])
	_check_scorpion_pose(e,&"walk_e",[[34,18],[34,18],[34,18],[34,19],[34,19]])
	_check_scorpion_pose(e,&"walk_ne",[[28,19],[28,18],[28,19],[29,19],[29,19]])
	_check_scorpion_pose(e,&"walk_n",[[25,22],[24,22],[25,22],[25,22],[26,22]])
	_check_scorpion_pose(e,&"walk_nw",[[26,25],[25,26],[25,26],[26,25],[26,25]])
	_check_scorpion_pose(e,&"walk_w",[[30,28],[30,28],[30,28],[30,27],[30,27]])
	_check_scorpion_pose(e,&"walk_sw",[[36,27],[36,28],[36,27],[35,27],[35,27]])
	_check_scorpion_pose(e,&"attack_s",[[39,24],[38,34],[32,60],[37,40],[39,24]])
	_check_scorpion_pose(e,&"attack_se",[[38,21],[42,29],[53,55],[45,35],[38,21]])
	_check_scorpion_pose(e,&"attack_e",[[34,18],[41,24],[61,41],[45,28],[34,18]])
	_check_scorpion_pose(e,&"attack_ne",[[28,19],[34,21],[53,27],[38,23],[28,19]])
	_check_scorpion_pose(e,&"attack_n",[[25,22],[26,22],[32,22],[27,22],[25,22]])
	_check_scorpion_pose(e,&"attack_nw",[[26,25],[22,27],[11,27],[19,27],[26,25]])
	_check_scorpion_pose(e,&"attack_w",[[30,28],[23,32],[3,41],[19,34],[30,28]])
	_check_scorpion_pose(e,&"attack_sw",[[36,27],[30,35],[11,55],[26,40],[36,27]])
	_check_scorpion_pose(e,&"hurt_s",[[39,24],[39,24],[39,24]])
	_check_scorpion_pose(e,&"hurt_se",[[38,20],[38,21],[38,21]])
	_check_scorpion_pose(e,&"hurt_e",[[33,18],[34,18],[34,18]])
	_check_scorpion_pose(e,&"hurt_ne",[[28,19],[28,19],[28,19]])
	_check_scorpion_pose(e,&"hurt_n",[[25,22],[25,22],[25,22]])
	_check_scorpion_pose(e,&"hurt_nw",[[26,26],[26,25],[26,25]])
	_check_scorpion_pose(e,&"hurt_w",[[31,28],[30,28],[30,28]])
	_check_scorpion_pose(e,&"hurt_sw",[[36,27],[36,27],[36,27]])
	_check_scorpion_pose(e,&"pincer_s",[[39,24],[39,24],[39,24],[39,24],[39,24]])
	_check_scorpion_pose(e,&"pincer_se",[[38,21],[38,21],[38,21],[38,21],[38,21]])
	_check_scorpion_pose(e,&"pincer_e",[[34,18],[34,18],[34,18],[34,18],[34,18]])
	_check_scorpion_pose(e,&"pincer_ne",[[28,19],[28,19],[28,19],[28,19],[28,19]])
	_check_scorpion_pose(e,&"pincer_n",[[25,22],[25,22],[25,22],[25,22],[25,22]])
	_check_scorpion_pose(e,&"pincer_nw",[[26,25],[26,25],[26,25],[26,25],[26,25]])
	_check_scorpion_pose(e,&"pincer_w",[[30,28],[30,28],[30,28],[30,28],[30,28]])
	_check_scorpion_pose(e,&"pincer_sw",[[36,27],[36,27],[36,27],[36,27],[36,27]])
	_check_scorpion_pose(e,&"emerge_s",[[-1,-1],[37,37],[42,31],[37,26],[40,24],[39,24]])
	_check_scorpion_pose(e,&"emerge_se",[[-1,-1],[37,34],[41,27],[37,23],[39,21],[38,21]])
	_check_scorpion_pose(e,&"emerge_e",[[-1,-1],[33,32],[35,24],[33,21],[35,19],[34,18]])
	_check_scorpion_pose(e,&"emerge_ne",[[-1,-1],[28,32],[28,25],[28,21],[30,19],[28,19]])
	_check_scorpion_pose(e,&"emerge_n",[[-1,-1],[25,35],[24,29],[25,24],[26,22],[25,22]])
	_check_scorpion_pose(e,&"emerge_nw",[[-1,-1],[25,38],[25,33],[25,27],[27,25],[26,25]])
	_check_scorpion_pose(e,&"emerge_w",[[-1,-1],[29,40],[31,36],[29,29],[31,27],[30,28]])
	_check_scorpion_pose(e,&"emerge_sw",[[-1,-1],[34,40],[38,35],[34,29],[36,27],[36,27]])
	_check_scorpion_pose(e,&"bury_s",[[39,24],[40,24],[37,26],[42,31],[37,37],[-1,-1]])
	_check_scorpion_pose(e,&"bury_se",[[38,21],[39,21],[37,23],[41,27],[37,34],[-1,-1]])
	_check_scorpion_pose(e,&"bury_e",[[34,18],[35,19],[33,21],[35,24],[33,32],[-1,-1]])
	_check_scorpion_pose(e,&"bury_ne",[[28,19],[30,19],[28,21],[28,25],[28,32],[-1,-1]])
	_check_scorpion_pose(e,&"bury_n",[[25,22],[26,22],[25,24],[24,29],[25,35],[-1,-1]])
	_check_scorpion_pose(e,&"bury_nw",[[26,25],[27,25],[25,27],[25,33],[25,38],[-1,-1]])
	_check_scorpion_pose(e,&"bury_w",[[30,28],[31,27],[29,29],[31,36],[29,40],[-1,-1]])
	_check_scorpion_pose(e,&"bury_sw",[[36,27],[36,27],[34,29],[38,35],[34,40],[-1,-1]])
	e.face_player(Vector2.RIGHT)
	# The modifier query never extends a timer. Only the first accepted
	# direct tip application extends this stun, preserving elapsed time.
	b._enter(e,b.State.MISS_STUN)
	_check(e.is_stunned(),"stun: behavior opts into generic status")
	var halo := e.get_node("StunHalo") as EnemyStunHalo
	halo._process(0.0)
	_check(halo.visible and halo.is_playing() and halo.position == Vector2(0,-16),"stun: behavior shows looping halo at scorpion anchor")
	b.physics_step(e,p,0.4)
	var before_hit := b._time
	var tip_hit := HitContext.projectile(e.stinger_tip(),e.stinger_tip(),1.0)
	e.modifiers_for_hit(tip_hit)
	_check(b._miss_duration == 1.0,"stun: modifier query has no timer side effect")
	e.apply_calculated_damage(1,0,HitContext.area(e.position,100.0))
	_check(b._miss_duration == 1.0,"stun: AoE full damage does not trigger direct-tip bonus")
	e.apply_calculated_damage(1,0,HitContext.projectile(e.position-Vector2(200,0),e.position-Vector2(200,0),1.0))
	_check(b._miss_duration == 1.0,"stun: shell hit does not extend")
	e.apply_calculated_damage(0,0,tip_hit)
	_check(b._miss_duration == 1.0,"stun: zero-damage receipt does not extend")
	e.apply_calculated_damage(1,0,tip_hit)
	_check(b._miss_duration == 3.0 and b._time == before_hit,"stun: first tip adds2s without resetting elapsed time")
	e.apply_calculated_damage(1,0,tip_hit)
	_check(b._miss_duration == 3.0,"stun: repeated tip cannot extend again")
	b.physics_step(e,p,2.59)
	_check(e.is_stunned(),"stun: extended miss remains before3s")
	b.physics_step(e,p,0.02)
	_check(not e.is_stunned(),"stun: extended miss ends at3s")
	halo._process(0.0)
	_check(not halo.visible and not halo.is_playing(),"stun: halo stops immediately on real stun end")
	b._enter(e,b.State.MISS_STUN)
	e.apply_calculated_damage(1,0,tip_hit)
	_check(b._miss_duration == 3.0,"stun: bonus re-arms next miss")
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
	# Player i-frames refuse the sting and lead to miss, not success.
	p.position = e.position+Vector2(100,0)
	p.set_invulnerable(true)
	b._aim = Vector2.RIGHT
	b._enter(e,b.State.STING_DASH)
	for i in 21: b.physics_step(e,p,1.0/60.0)
	_check(b.state == b.State.MISS_STUN,"scorpion: i-frames count as sting miss")
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
		var actual := e.sprite.to_local(e.stinger_tip())+Vector2(32,32)
		_check(actual == expected,"scorpion: rendered tip follows source pose %s:%d" % [animation,k])
		var image := e.sprite.sprite_frames.get_frame_texture(animation,k).get_image()
		var color := image.get_pixelv(Vector2i(expected))
		var visible_tip := color.a > 0.0 and color.r < 0.68 and color.b > color.r
		_check(e.stinger_exposed() == visible_tip,"scorpion: occlusion follows actual pixel %s:%d" % [animation,k])
