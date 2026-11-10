extends SceneTree
## #370 harness: Stone Hammer spell + its two upgrade routes.
##  Base    - overhead swing: nothing is hit during the wind-up, then every
##            enemy within hammer_radius of the (range-clamped) aim point
##            takes heavy damage once; 8.5s cooldown, no projectile.
##  Crush   - Reaper: each kill adds +10% crit chance for the rest of the run
##            (kept on the caster, so it survives upgrades) and the bonus
##            really crits. Titan: strike radius scales with crit chance,
##            capped. Vortex: holding opens a vortex at the strike point that
##            pulls enemies in; releasing swings; refused on cooldown.
##  Rhythm  - Rhythm: consecutive hits cut 1s off the cooldown (min 0.5s), a
##            miss or 30s idle (off cooldown) resets it, each hit plays a
##            tone whose pitch rises and caps at the max reduction. Leap: the
##            player is invulnerable during the wind-up, the shockwave hurts
##            what the hammer missed and never counts as a hit. Dice Roll:
##            every 8 consecutive hits a die rolls above the player and drops
##            the face's currency reward.
##  Tree    - two tier-1 routes, each chains 1 -> 2 -> 3, one route per run;
##            main.gd registers them and the demo table drops Stone Hammer.
## Run headless:
##   godot --headless --path . -s scripts/test370_stone_hammer.gd

const DIR := "res://resources/spells/"
const NAMES := ["stone_hammer", "stone_hammer_reaper", "stone_hammer_titan", "stone_hammer_vortex", "stone_hammer_rhythm", "stone_hammer_leap", "stone_hammer_gambler"]
const IDS := ["hammer_reaper", "hammer_titan", "hammer_vortex", "hammer_rhythm", "hammer_leap", "hammer_gambler"]

var _area: Node2D
var _player: Player
var _caster: SpellCaster
var _checks := 0
var _failures := 0

func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if ok:
		print("PASS: %s" % msg)
	else:
		_failures += 1
		print("FAIL: %s" % msg)

func _spell(n: String) -> Spell:
	return load(DIR + n + ".tres")

func _wait(seconds: float) -> void:
	for i in maxi(int(ceil(seconds * 60.0)), 1):
		await physics_frame

func _enemy(pos: Vector2, hp: int = 1000) -> Enemy:
	var e: Enemy = load("res://scenes/enemy.tscn").instantiate()
	e.max_hp = hp
	e.speed = 0.0
	e.contact_damage = 0
	_area.add_child(e)
	e.global_position = pos
	return e

func _clear_area() -> void:
	for c in _area.get_children():
		if c != _player:
			c.queue_free()
	for c in _player.get_children():
		if c is HammerDice:
			c.queue_free()
	_caster.hammer_state = StoneHammerState.new()
	_caster._cooldowns.clear()
	_player.set_invulnerable(false)
	await physics_frame
	await physics_frame

func _cast(spell: Spell, aim: Vector2) -> void:
	_caster.aim_override = aim
	_caster._cooldowns.erase(spell)
	_caster._cast_spell(spell)

## Cast and wait until the swing has landed.
func _swing(spell: Spell, aim: Vector2) -> void:
	_cast(spell, aim)
	await _wait(spell.hammer_windup + 0.08)

func _hammers() -> Array:
	return _area.get_children().filter(func(c): return c is StoneHammer and not c.is_queued_for_deletion())

func _initialize() -> void:
	print("test370: Stone Hammer tree (#370)")
	_area = Node2D.new()
	root.add_child(_area)
	current_scene = _area
	_player = load("res://scenes/player.tscn").instantiate()
	_player.add_to_group("player")
	_area.add_child(_player)
	_player.global_position = Vector2(400, 300)
	_caster = _player.get_node("SpellCaster")
	await physics_frame
	await physics_frame

	_check_data()
	await _check_base()
	await _check_reaper()
	await _check_titan()
	await _check_vortex()
	await _check_rhythm()
	await _check_leap()
	await _check_gambler()
	await _check_tree()

	print("test370 done: %d checks, %d failures" % [_checks, _failures])
	print("RESULT: %s" % ("ALL PASS" if _failures == 0 else "FAIL"))
	quit(1 if _failures > 0 else 0)

func _check_data() -> void:
	var s := Spell.new()
	_check(s.hammer_radius == 0.0 and s.hammer_kill_crit == 0.0 and s.hammer_crit_scale == 0.0 and s.hammer_vortex_radius == 0.0, "crush fields default off")
	_check(s.hammer_combo_cdr == 0.0 and not s.hammer_jump and s.hammer_shockwave_radius == 0.0 and s.hammer_dice_every == 0, "rhythm fields default off")
	_check(SpellTags.is_valid(SpellTags.EARTH), "earth tag is in the vocabulary")
	for n in NAMES:
		var sp := _spell(n)
		_check(sp != null and sp.hammer_radius > 0.0 and sp.projectile_count == 0, "%s is a hammer strike with no projectile" % n)
		_check(sp.tags.has(SpellTags.EARTH) and SpellTags.unknown_tags(sp.tags).is_empty(), "%s carries the earth tag" % n)
		_check(is_equal_approx(sp.cooldown, 8.5), "%s has the 8.5s cooldown" % n)
	var g := _spell("stone_hammer_gambler")
	_check(g.hammer_dice_tables.size() == 6, "dice roll: one loot table per face")
	var prev_min := 0
	var rising := true
	for t in g.hammer_dice_tables:
		var lo := 1 << 30
		var all_currency := true
		for e in t.entries:
			lo = mini(lo, e.currency_amount)
			all_currency = all_currency and e.kind == RewardEntry.Kind.CURRENCY and e.currency_amount > 0
		rising = rising and all_currency and lo > prev_min
		prev_min = lo
	_check(rising, "dice roll: currency only, and higher faces pay more")

func _check_base() -> void:
	var base := _spell("stone_hammer")
	var at := _enemy(Vector2(500, 300))
	var edge := _enemy(Vector2(500, 300 + base.hammer_radius + 5.0))
	var far := _enemy(Vector2(500, 420))
	await physics_frame
	_cast(base, Vector2(500, 300))
	var cd_at_cast := _caster.cooldown_remaining(base)
	await physics_frame
	_check(_hammers().size() == 1, "base: one hammer swing spawned")
	_check(_caster.live_shots(base).is_empty(), "base: no projectile")
	# Cooldown ticks down in _process, so only the value right after the cast
	# is exactly 8.5; after the await it has lost a frame or more.
	_check(is_equal_approx(cd_at_cast, 8.5), "base: 8.5s cooldown starts on cast")
	_check(is_equal_approx(_caster.cooldown_duration(base), 8.5), "base: cooldown total is 8.5s")
	var cd_left := _caster.cooldown_remaining(base)
	_check(cd_left <= cd_at_cast and cd_left > 8.5 - 0.25, "base: cooldown only decays by elapsed frames")
	await _wait(base.hammer_windup * 0.5)
	_check(at.hp == 1000, "base: nothing is hit during the wind-up")
	await _wait(base.hammer_windup * 0.5 + 0.08)
	_check(at.hp == 1000 - int(base.damage), "base: heavy hit on the target (hp %d)" % at.hp)
	_check(edge.hp == 1000 - int(base.damage), "base: an enemy at the edge of the area is hit")
	_check(far.hp == 1000, "base: an enemy outside the small area is untouched")
	await _wait(0.6)
	_check(_hammers().is_empty(), "base: the swing cleans itself up")
	_check(at.hp == 1000 - int(base.damage), "base: one hit per swing")
	await _clear_area()
	# Range clamp: aiming far away lands at most `range` from the player.
	_cast(base, Vector2(2000, 300))
	await physics_frame
	var h: Array = _hammers()
	_check(h.size() == 1 and absf(h[0].target.distance_to(_player.global_position) - base.range) < 1.0, "base: strike point clamped to range")
	await _clear_area()

func _check_reaper() -> void:
	var reaper := _spell("stone_hammer_reaper")
	var weak := [_enemy(Vector2(500, 300), 30), _enemy(Vector2(510, 310), 30)]
	await physics_frame
	await _swing(reaper, Vector2(505, 305))
	_check(not is_instance_valid(weak[0]) or weak[0].hp <= 0, "reaper: kill 1")
	_check(is_equal_approx(_caster.hammer_state.bonus_crit, 0.2), "reaper: two kills -> +20%% crit (%.2f)" % _caster.hammer_state.bonus_crit)
	var tough := _enemy(Vector2(500, 300))
	await physics_frame
	await _swing(reaper, Vector2(500, 300))
	_check(is_equal_approx(_caster.hammer_state.bonus_crit, 0.2), "reaper: a hit without a kill adds nothing")
	# The bonus is permanent: an upgrade keeps it (state lives on the caster).
	_caster.add_spell(reaper)
	_check(_caster.replace_spell(reaper, _spell("stone_hammer_titan")), "reaper: replace_spell to Titan")
	_check(is_equal_approx(_caster.hammer_state.bonus_crit, 0.2), "reaper: crit bonus survives the upgrade")
	_caster.replace_spell(_spell("stone_hammer_titan"), reaper)
	# The bonus really crits: 100% bonus = a guaranteed x2 tier.
	_caster.hammer_state.bonus_crit = 1.0
	var hp0 := tough.hp
	await _swing(reaper, Vector2(500, 300))
	_check(hp0 - tough.hp == int(reaper.damage * 2.0), "reaper: 100%% bonus crit doubles the hit (%d)" % (hp0 - tough.hp))
	_check(not _spell("stone_hammer").hammer_kill_crit > 0.0, "base: kills grant nothing")
	_caster.unlocked.clear()
	_caster.spells.clear()
	for i in SpellCaster.SLOT_COUNT:
		_caster.clear_slot(i)
	await _clear_area()

func _check_titan() -> void:
	var titan := _spell("stone_hammer_titan")
	var st := _caster.hammer_state
	_check(is_equal_approx(st.size_scale(titan, _player), 1.0), "titan: no crit -> normal size")
	_check(is_equal_approx(st.size_scale(_spell("stone_hammer_reaper"), _player), 1.0), "reaper: size never scales")
	st.bonus_crit = 0.5
	_check(is_equal_approx(st.size_scale(titan, _player), 1.5), "titan: 50%% crit -> 1.5x size")
	st.bonus_crit = 10.0
	_check(is_equal_approx(st.size_scale(titan, _player), titan.hammer_max_scale), "titan: size is capped")
	# Player crit modifiers count too.
	st.bonus_crit = 0.0
	var m := DamageModifier.crit(0.5, 2.0)
	_player.damage_modifiers.add(m)
	_check(is_equal_approx(st.size_scale(titan, _player), 1.5), "titan: the player's own crit chance scales it too")
	_player.damage_modifiers.remove(m)
	# A bigger strike reaches farther.
	st.bonus_crit = 0.5
	var outer := _enemy(Vector2(500, 300 + titan.hammer_radius * 1.4))
	await physics_frame
	_cast(titan, Vector2(500, 300))
	await physics_frame
	var h: Array = _hammers()
	_check(h.size() == 1 and is_equal_approx(h[0].radius, titan.hammer_radius * 1.5) and is_equal_approx(h[0].size_scale, 1.5), "titan: the swing is bigger")
	await _wait(titan.hammer_windup + 0.08)
	_check(outer.hp < 1000, "titan: hits an enemy outside the base radius")
	await _clear_area()

func _check_vortex() -> void:
	var vortex := _spell("stone_hammer_vortex")
	_caster.add_spell(vortex) # binds a slot (unbound vortexes are pruned)
	var inside := _enemy(Vector2(640, 300))
	var outside := _enemy(Vector2(400, 700))
	await physics_frame
	_caster.aim_override = Vector2(520, 300)
	_check(_caster.begin_charge(vortex, &"test"), "vortex: holding opens the vortex")
	_check(not _caster.begin_charge(vortex, &"test"), "vortex: one vortex at a time")
	var v := _caster.active_vortex(vortex)
	_check(v != null and v.global_position.is_equal_approx(_caster.hammer_target(vortex)), "vortex: sits where the hammer will strike")
	_check(_hammers().is_empty() and is_zero_approx(_caster.cooldown_remaining(vortex)), "vortex: holding is not a cast")
	var d0 := inside.global_position.distance_to(v.global_position)
	await _wait(0.4)
	var d1 := inside.global_position.distance_to(v.global_position)
	_check(d1 < d0 - 30.0, "vortex: enemy sucked toward the centre (%.0f -> %.0f px)" % [d0, d1])
	_check(outside.global_position.is_equal_approx(Vector2(400, 700)), "vortex: enemies outside the radius stay put")
	_caster.aim_override = Vector2(520, 340)
	await physics_frame
	_check(v.global_position.is_equal_approx(_caster.hammer_target(vortex)), "vortex: follows the aim while held")
	_check(_caster.release_charge(vortex), "vortex: releasing swings")
	await physics_frame
	_check(not _caster.is_charging(vortex) and _hammers().size() == 1, "vortex: vortex closed, hammer swinging")
	_check(_caster.cooldown_remaining(vortex) > 8.0, "vortex: the swing starts the cooldown")
	await _wait(vortex.hammer_windup + 0.08)
	_check(inside.hp < 1000, "vortex: the pulled enemy is crushed")
	_check(not _caster.begin_charge(vortex, &"test"), "vortex: refused while on cooldown")
	# A vortex whose spell leaves every key is dropped.
	_caster._cooldowns.erase(vortex)
	_check(_caster.begin_charge(vortex, &"test"), "vortex: reopens off cooldown")
	for i in SpellCaster.SLOT_COUNT:
		_caster.clear_slot(i)
	_caster.spells.clear()
	await physics_frame
	await physics_frame
	_check(not _caster.is_charging(vortex), "vortex: unequipping drops the vortex")
	_caster.unlocked.clear()
	await _clear_area()

func _check_rhythm() -> void:
	var rhythm := _spell("stone_hammer_rhythm")
	var st := _caster.hammer_state
	_check(StoneHammerState.max_steps(rhythm) == 8, "rhythm: 8 steps from 8.5s to 0.5s")
	var e := _enemy(Vector2(500, 300))
	await physics_frame
	var tones: Array = []
	st.tone_played.connect(func(step: int, pitch: float) -> void: tones.append([step, pitch]))
	var cds: Array = []
	for i in 10:
		_cast(rhythm, Vector2(500, 300))
		cds.append(_caster.cooldown_remaining(rhythm))
		await _wait(rhythm.hammer_windup + 0.05)
	_check(is_equal_approx(cds[0], 8.5) and is_equal_approx(cds[1], 7.5) and is_equal_approx(cds[2], 6.5), "rhythm: each consecutive hit cuts 1s (%s)" % str(cds.slice(0, 3)))
	_check(is_equal_approx(cds[8], 0.5) and is_equal_approx(cds[9], 0.5), "rhythm: floors at 0.5s")
	_check(st.combo_hits == 10, "rhythm: 10 consecutive hits")
	_check(tones.size() == 10, "rhythm: a tone per hit")
	var rising := true
	for i in range(1, 8):
		rising = rising and tones[i][1] > tones[i - 1][1]
	_check(rising, "rhythm: tone pitch rises with each hit")
	_check(tones[7][0] == 8 and is_equal_approx(tones[8][1], tones[7][1]) and is_equal_approx(tones[9][1], tones[7][1]), "rhythm: pitch caps at the max reduction")
	_check(get_nodes_in_group(&"hammer_tones").size() > 0, "rhythm: tone players spawned")
	_check(StoneHammer.tone_stream() is AudioStreamWAV and StoneHammer.tone_stream().data.size() > 1000, "rhythm: tone stream generated")
	# A miss resets the combo.
	await _swing(rhythm, Vector2(500, 420))
	_check(st.combo_hits == 0, "rhythm: a miss resets the combo")
	_cast(rhythm, Vector2(500, 300))
	_check(is_equal_approx(_caster.cooldown_remaining(rhythm), 8.5), "rhythm: full cooldown after a miss")
	await _wait(rhythm.hammer_windup + 0.05)
	_check(st.combo_hits == 1, "rhythm: combo restarts on the next hit")
	# Idle reset: only once off cooldown AND unused for 30s.
	st.tick(29.0, false, rhythm.hammer_combo_idle_reset)
	_check(st.combo_hits == 1, "rhythm: combo kept before 30s")
	st.tick(2.0, true, rhythm.hammer_combo_idle_reset)
	_check(st.combo_hits == 1, "rhythm: combo kept while on cooldown")
	st.tick(0.1, false, rhythm.hammer_combo_idle_reset)
	_check(st.combo_hits == 0, "rhythm: 30s unused off cooldown resets the combo")
	# The caster's clock drives it in play.
	st.combo_hits = 3
	st.idle_time = 0.0
	_caster.add_spell(rhythm)
	_caster._cooldowns.erase(rhythm)
	_caster._process(31.0)
	_check(st.combo_hits == 0, "rhythm: caster clock resets an idle combo")
	_caster.unlocked.clear()
	for i in SpellCaster.SLOT_COUNT:
		_caster.clear_slot(i)
	_caster.spells.clear()
	_check(_spell("stone_hammer").hammer_combo_cdr == 0.0, "base: no combo")
	await _clear_area()

func _check_leap() -> void:
	var leap := _spell("stone_hammer_leap")
	var hit := _enemy(Vector2(500, 300))
	var shock := _enemy(Vector2(500, 300 + leap.hammer_radius + 40.0))
	var beyond := _enemy(Vector2(500, 300 + leap.hammer_shockwave_radius + 40.0))
	await physics_frame
	var hp := _player.hp
	_cast(leap, Vector2(500, 300))
	await physics_frame
	_check(_player.is_invulnerable(), "leap: invulnerable while jumping")
	_player.apply_damage(25)
	_check(_player.hp == hp, "leap: hits are ignored mid-jump")
	await _wait(leap.hammer_windup + 0.08)
	_check(not _player.is_invulnerable(), "leap: vulnerable again after landing")
	_check(hit.hp == 1000 - int(leap.damage), "leap: hammer hit")
	_check(shock.hp == 1000 - int(leap.hammer_shockwave_damage), "leap: shockwave hits outside the hammer for small damage (hp %d)" % shock.hp)
	_check(beyond.hp == 1000, "leap: shockwave has a limited radius")
	_check(_caster.hammer_state.combo_hits == 1, "leap: keeps the Rhythm combo")
	# Shockwave-only damage is not a hit: the combo resets.
	# 90px above `hit`: outside the hammer, inside the shockwave.
	await _swing(leap, Vector2(500, 210))
	_check(hit.hp < 1000 - int(leap.damage) and _caster.hammer_state.combo_hits == 0, "leap: shockwave-only damage counts as a miss")
	await _clear_area()
	await _check_leap_overlap("stone_hammer_leap")
	await _check_leap_overlap("stone_hammer_gambler")

## Review on #374: at max Rhythm combo (0.5s) and the legal 60% cooldown
## reduction the cooldown is 0.2s, shorter than the 0.35s wind-up, so a HELD
## cast starts the next jump before the previous one lands. The first landing
## must not close the window while another jump is in the air, and the
## visual hop must return to rest only after the last jump.
func _check_leap_overlap(spell_name: String) -> void:
	var spell := _spell(spell_name)
	var tag := "overlap(%s)" % spell_name
	var st := _caster.hammer_state
	_enemy(Vector2(500, 300), 1000000)
	var rest_body := _player.body.position
	var rest_nose := _player.nose_edge.position
	var cdr := StatModifier.flat(PlayerStats.COOLDOWN_REDUCTION, PlayerStats.COOLDOWN_REDUCTION_MAX, 0.0, &"test370_overlap")
	_player.stats.add(cdr)
	_caster.unlocked.clear()
	for i in SpellCaster.SLOT_COUNT:
		_caster.clear_slot(i)
	_caster.spells.clear()
	_caster.add_spell(spell)
	_caster._cooldowns.clear()
	_caster.aim_override = Vector2(500, 300)
	st.combo_hits = StoneHammerState.max_steps(spell)
	await physics_frame
	var hp := _player.hp
	var casts := [0]
	var on_cast := func(_s: Spell) -> void: casts[0] += 1
	_caster.spell_cast.connect(on_cast)
	Input.action_press(&"cast")
	var max_active := 0
	var jump_frames := 0
	var leaks := 0
	var window_wrong := 0
	var first_cd := -1.0
	# Hold for ~1.5s, then release and keep sampling until every jump lands.
	for f in 150:
		if f == 90:
			Input.action_release(&"cast")
		await physics_frame
		if first_cd < 0.0 and casts[0] > 0:
			first_cd = _caster._cooldown_totals.get(spell, -1.0)
		var active := StoneHammer.active_jumps(_player)
		max_active = maxi(max_active, active)
		if active > 0:
			jump_frames += 1
			_player.apply_damage(5)
			if _player.hp != hp:
				leaks += 1
				hp = _player.hp
			if not _player.is_invulnerable():
				window_wrong += 1
		elif _player.is_invulnerable():
			window_wrong += 1
		if f > 90 and active == 0 and _hammers().all(func(h): return not h.is_jumping()):
			break
	_caster.spell_cast.disconnect(on_cast)
	_check(is_equal_approx(first_cd, 0.2) and first_cd < spell.hammer_windup, "%s: max combo + 60%% CDR gives a 0.2s cooldown (got %.3f) < %.2fs wind-up" % [tag, first_cd, spell.hammer_windup])
	_check(casts[0] >= 4, "%s: held cast refires (%d casts)" % [tag, casts[0]])
	_check(max_active >= 2, "%s: jumps really overlap (max %d at once)" % [tag, max_active])
	_check(jump_frames > 0 and leaks == 0, "%s: damage ignored on all %d jump frames (%d leaked)" % [tag, jump_frames, leaks])
	_check(window_wrong == 0, "%s: invulnerable exactly while any jump is active (%d wrong frames)" % [tag, window_wrong])
	_check(StoneHammer.active_jumps(_player) == 0 and not _player.is_invulnerable(), "%s: vulnerable again after the last jump lands" % tag)
	_check(_player.body.position == rest_body and _player.nose_edge.position == rest_nose, "%s: hop offset restored to rest (body %s, nose %s)" % [tag, _player.body.position, _player.nose_edge.position])
	var hp_before := _player.hp
	_player.apply_damage(5)
	_check(_player.hp == hp_before - 5, "%s: damage lands once grounded" % tag)
	# Cancellation: overlapping jumps freed mid-air (e.g. scene change) close
	# the window and restore the hop too.
	_caster._cooldowns.clear()
	_caster._cast_spell(spell)
	for i in 12:
		await physics_frame
	_caster._cooldowns.clear()
	_caster._cast_spell(spell)
	await physics_frame
	_check(StoneHammer.active_jumps(_player) == 2 and _player.is_invulnerable(), "%s: two jumps in the air before cancelling" % tag)
	_hammers().filter(func(h): return h.is_jumping())[0].queue_free()
	await physics_frame
	_check(StoneHammer.active_jumps(_player) == 1 and _player.is_invulnerable(), "%s: cancelling one jump keeps the other's window" % tag)
	_hammers().filter(func(h): return h.is_jumping())[0].queue_free()
	await physics_frame
	_check(StoneHammer.active_jumps(_player) == 0 and not _player.is_invulnerable(), "%s: cancelling the last jump closes the window" % tag)
	_check(_player.body.position == rest_body and _player.nose_edge.position == rest_nose, "%s: cancelled hop restored to rest" % tag)
	_player.stats.remove(cdr)
	_caster.aim_override = null
	_caster.spells.clear()
	_player.heal(_player.max_hp)
	await _clear_area()

func _check_gambler() -> void:
	var gambler := _spell("stone_hammer_gambler")
	var wallet := CurrencyWallet.new()
	_area.add_child(wallet)
	var e := _enemy(Vector2(500, 300), 100000)
	await physics_frame
	var rolls: Array = []
	_caster.hammer_state.dice_rolled.connect(func(face: int, entry: RewardEntry) -> void: rolls.append([face, entry]))
	for i in 7:
		await _swing(gambler, Vector2(500, 300))
	_check(rolls.is_empty(), "dice: no roll before 8 hits")
	await _swing(gambler, Vector2(500, 300))
	_check(rolls.size() == 1, "dice: rolls on the 8th consecutive hit")
	if rolls.size() != 1:
		return
	var face: int = rolls[0][0]
	var entry: RewardEntry = rolls[0][1]
	_check(face >= 1 and face <= 6, "dice: face %d in 1-6" % face)
	_check(entry != null and gambler.hammer_dice_tables[face - 1].entries.has(entry), "dice: reward rolled from face %d's table" % face)
	var dice: HammerDice = null
	for c in _player.get_children():
		if c is HammerDice:
			dice = c
	_check(dice != null, "dice: die shown above the player")
	if dice != null:
		_check(dice.global_position.y < _player.global_position.y - 40.0, "dice: drawn above the player's head")
		await _wait(HammerDice.ROLL_TIME + 0.1)
		_check(dice.is_settled() and dice.shown_face() == face, "dice: settles on the rolled face")
		# (The drop lands at the player's feet, so it may already be collected.)
		_check(dice.dropped_entry == entry, "dice: reward drop spawned for the rolled entry")
		await _wait(0.2)
		_check(wallet.balance() == entry.currency_amount, "dice: walking over the drop pays %dc (wallet %d)" % [entry.currency_amount, wallet.balance()])
	for i in 8:
		await _swing(gambler, Vector2(500, 300))
	_check(rolls.size() == 2, "dice: rolls again after 8 more")
	await _clear_area()

func _check_tree() -> void:
	var progress := SpellProgress.new()
	for id in IDS:
		progress.upgrades.append(load("res://resources/upgrades/%s.tres" % id))
	var base := _spell("stone_hammer")
	var paths := progress.get_upgrade_paths(base)
	_check(paths.size() == 2, "tree: two Specialization routes from the base")
	for p in paths:
		_check(p.tier == 1, "tree: %s is tier 1" % p.id)
		var cur: Spell = p.result_spell
		for tier in [2, 3]:
			var next := progress.get_upgrade_paths(cur)
			_check(next.size() == 1 and next[0].tier == tier, "tree: %s continues to tier %d" % [cur.spell_name, tier])
			if next.size() != 1:
				break
			cur = next[0].result_spell
	progress.free()
	# One route per run, like Water Ball.
	var holder := Node2D.new()
	_area.add_child(holder)
	var caster := SpellCaster.new()
	caster.name = "RouteCaster"
	holder.add_child(caster)
	var rp := SpellProgress.new()
	rp.caster_path = NodePath("../RouteCaster")
	for id in IDS:
		rp.upgrades.append(load("res://resources/upgrades/%s.tres" % id))
	holder.add_child(rp)
	await physics_frame
	caster.add_spell(base)
	for i in 10:
		caster.spell_cast.emit(base)
	_check(rp.apply_upgrade(base, &"hammer_rhythm"), "route: Rhythm applies")
	caster.add_spell(base)
	_check(rp.route_taken(base) and rp.get_upgrade_paths(base).is_empty(), "route: Crush closed after Rhythm")
	_check(not rp.apply_upgrade(base, &"hammer_reaper"), "route: Reaper refused after Rhythm")
	holder.queue_free()
	await physics_frame
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	for id in IDS:
		_check(main_src.contains("upgrades/%s.tres" % id), "main.gd registers %s" % id)
	# #465 (Daniel, 2026-11-09: regular mobs drop currency only): the
	# production mob table no longer carries spells, so the Stone Hammer
	# reward wiring is pinned with an in-code fixture entry.
	var table := RewardTable.new()
	var sh_entry := RewardEntry.new()
	sh_entry.kind = RewardEntry.Kind.SPELL
	sh_entry.spell = load("res://resources/spells/stone_hammer.tres")
	sh_entry.weight = 1.0
	var sh_entries: Array[RewardEntry] = [sh_entry]
	table.entries = sh_entries
	_check(table.roll([]) == sh_entry and sh_entry.spell.spell_name == "Stone Hammer", "fixture reward table rolls the Stone Hammer spell entry")
