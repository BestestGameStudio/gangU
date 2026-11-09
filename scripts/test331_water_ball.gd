extends SceneTree
## #331 harness: Water Ball spell + its three upgrade branches.
##  Base      - plain projectile on the water_ball sheet row, damages + despawns.
##  Steer     - Guided: a fresh press with shots in flight re-aims them and
##              never casts; Seeking: chases the cursor for cursor_chase_time
##              then flies straight; Tidal Seeker: chases the whole life and
##              hits exactly pierce_hits bodies before disappearing.
##  Splash    - Splash: lobbed, hits nothing in flight, AOE on landing;
##              Barrage: projectile_count lobs; Heavy Rain: rain zone drops
##              repeated splashes then ends.
##  Bubble    - Water Bubble: contact damage + absorbs N hostile shots, then
##              pops; Surging: pushes enemies back when it ends; Big Ball:
##              bigger, recast fires a Water Ball and shrinks it, real
##              cooldown starts when it ends.
##  Tree      - SpellProgress offers three tier-1 paths from the base and
##              each branch chains tier 1 -> 2 -> 3.
## Run headless:
##   godot --headless --path . -s scripts/test331_water_ball.gd

const DIR := "res://resources/spells/"

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

func _spell(name: String) -> Spell:
	return load(DIR + name + ".tres")

func _wait(seconds: float) -> void:
	for i in maxi(int(ceil(seconds * 60.0)), 1):
		await physics_frame

func _enemy(pos: Vector2) -> Enemy:
	var e: Enemy = load("res://scenes/enemy.tscn").instantiate()
	e.max_hp = 1000
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
		if c is WaterShield:
			c.queue_free()
	await physics_frame
	await physics_frame

func _cast(spell: Spell, aim: Vector2) -> void:
	_caster.aim_override = aim
	_caster._cooldowns.erase(spell)
	_caster._cast_spell(spell)

func _shots(spell: Spell) -> Array[Projectile]:
	return _caster.live_shots(spell)

func _initialize() -> void:
	print("test331: Water Ball tree (#331)")
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

	_check_defaults()
	await _check_base()
	await _check_guided()
	await _check_seeking()
	await _check_tidal()
	await _check_splash()
	await _check_barrage()
	await _check_rain()
	await _check_bubble()
	await _check_surging()
	await _check_big_ball()
	await _check_tree()

	print("test331 done: %d checks, %d failures" % [_checks, _failures])
	print("RESULT: %s" % ("ALL PASS" if _failures == 0 else "FAIL"))
	quit(1 if _failures > 0 else 0)

func _check_defaults() -> void:
	var s := Spell.new()
	_check(not s.recast_redirect and s.cursor_chase_time == 0.0 and s.pierce_hits == 0, "steer fields default off")
	_check(s.splash_radius == 0.0 and s.rain_duration == 0.0, "splash/rain fields default off")
	_check(s.shield_radius == 0.0 and s.shield_shot == null and s.shield_push_force == 0.0, "bubble fields default off")
	for n in ["water_ball", "water_ball_guided", "water_ball_seeking", "water_ball_tidal", "water_splash", "water_barrage", "heavy_rain", "water_bubble", "surging_bubble", "big_ball"]:
		var sp := _spell(n)
		_check(sp.tags.has(SpellTags.WATER) and SpellTags.unknown_tags(sp.tags).is_empty(), "%s carries the water tag" % n)
		_check(Projectile.SPELL_SPRITE_ANIMS.get(sp.spell_name, &"") == &"water_ball", "%s flies the water_ball sheet row" % n)

func _check_base() -> void:
	var base := _spell("water_ball")
	var e := _enemy(Vector2(520, 300))
	_cast(base, Vector2(800, 300))
	await physics_frame
	var shots := _shots(base)
	_check(shots.size() == 1, "base: one Water Ball in flight")
	if shots.size() == 1:
		var spr := shots[0].get_node_or_null("Sprite") as AnimatedSprite2D
		_check(spr != null and String(spr.animation).begins_with("water_ball"), "base: plays the water_ball sprite")
	await _wait(0.5)
	_check(e.hp < 1000, "base: hit the enemy (hp %d)" % e.hp)
	_check(_shots(base).is_empty(), "base: despawned on its first hit")
	await _clear_area()

func _check_guided() -> void:
	var guided := _spell("water_ball_guided")
	var casts := [0]
	var cb := func(_s: Spell) -> void: casts[0] += 1
	_caster.spell_cast.connect(cb)
	_cast(guided, Vector2(800, 300))
	await _wait(0.1)
	var shots := _shots(guided)
	_check(shots.size() == 1, "guided: one shot in flight")
	_check(casts[0] == 1, "guided: first press casts")
	if shots.size() == 1:
		var p := shots[0]
		_check(p.direction.dot(Vector2.RIGHT) > 0.99, "guided: flies at the first aim")
		_caster.aim_override = p.global_position + Vector2(0, 300)
		_check(_caster._redirect_gate(guided, true), "guided: fresh press with a shot in flight is consumed")
		_check(p.direction.dot(Vector2.DOWN) > 0.99, "guided: shot re-aimed at the cursor")
		_check(_caster._redirect_gate(guided, false), "guided: held press still blocks a recast")
		_check(casts[0] == 1, "guided: redirect is not a cast")
		var before := p.direction
		await _wait(0.3)
		_check(is_instance_valid(p) and p.direction.is_equal_approx(before), "guided: no chase after redirect (straight line)")
	for s in _shots(guided):
		s.queue_free()
	await physics_frame
	_check(not _caster._redirect_gate(guided, true), "guided: no shots in flight -> press casts normally")
	_caster.spell_cast.disconnect(cb)
	await _clear_area()

func _check_seeking() -> void:
	var seeking := _spell("water_ball_seeking")
	_cast(seeking, Vector2(800, 300))
	await physics_frame
	var shots := _shots(seeking)
	_check(shots.size() == 1, "seeking: one shot in flight")
	if shots.size() != 1:
		return
	var p := shots[0]
	_caster.aim_override = Vector2(400, 700)
	await _wait(0.3)
	_check(p.direction.dot(Vector2.DOWN) > 0.3, "seeking: turning toward the cursor while chasing")
	await _wait(0.85)
	var d1 := p.direction
	await _wait(0.2)
	_check(is_instance_valid(p) and p.direction.is_equal_approx(d1), "seeking: flies straight after cursor_chase_time")
	_check(_caster._redirect_gate(seeking, true), "seeking: keeps the click-to-redirect")
	await _clear_area()

func _check_tidal() -> void:
	var tidal := _spell("water_ball_tidal")
	var enemies: Array[Enemy] = []
	for i in 6:
		enemies.append(_enemy(Vector2(470 + i * 45, 300)))
	await physics_frame
	_cast(tidal, Vector2(1200, 300))
	await physics_frame
	var shots := _shots(tidal)
	_check(shots.size() == 1, "tidal: one shot in flight")
	var p: Projectile = shots[0] if shots.size() == 1 else null
	await _wait(1.0)
	var hit := 0
	for e in enemies:
		if e.hp < 1000:
			hit += 1
	_check(hit == 5, "tidal: hit exactly pierce_hits=5 enemies (%d)" % hit)
	_check(p == null or not is_instance_valid(p) or p.is_queued_for_deletion(), "tidal: disappears after its 5th hit")
	await _clear_area()
	# Whole-life chase: still turning toward the cursor long after spawn.
	_cast(tidal, Vector2(900, 300))
	await physics_frame
	shots = _shots(tidal)
	if shots.size() == 1:
		p = shots[0]
		await _wait(1.5)
		_caster.aim_override = p.global_position + Vector2(0, -400)
		await _wait(0.4)
		_check(is_instance_valid(p) and p.direction.dot(Vector2.UP) > 0.5, "tidal: follows the cursor for its whole life")
		_check(not _caster._redirect_gate(tidal, true), "tidal: no redirect gate, recasts allowed")
	await _clear_area()

func _splashes() -> Array:
	return _area.get_children().filter(func(c): return c is WaterSplash and not c.is_queued_for_deletion())

func _check_splash() -> void:
	var splash := _spell("water_splash")
	var mid := _enemy(Vector2(500, 300))
	var at := _enemy(Vector2(600, 300))
	var near := _enemy(Vector2(640, 300))
	var far := _enemy(Vector2(720, 300))
	await physics_frame
	_cast(splash, Vector2(600, 300))
	await physics_frame
	_check(_splashes().size() == 1, "splash: one lob spawned")
	_check(_shots(splash).is_empty(), "splash: no flat projectile")
	await _wait(0.2)
	_check(mid.hp == 1000, "splash: passes over enemies in flight")
	await _wait(0.45)
	_check(at.hp < 1000 and near.hp < 1000, "splash: AOE hits enemies inside splash_radius")
	_check(far.hp == 1000 and mid.hp == 1000, "splash: enemies outside the radius untouched")
	# Range clamp.
	await _wait(0.4)
	_cast(splash, Vector2(2000, 300))
	await physics_frame
	var s: Array = _splashes()
	_check(s.size() == 1 and absf(s[0].target.distance_to(_caster.global_position) - splash.range) < 1.0, "splash: landing point clamped to range")
	await _clear_area()

func _check_barrage() -> void:
	var barrage := _spell("water_barrage")
	_cast(barrage, Vector2(600, 300))
	await physics_frame
	var s: Array = _splashes()
	_check(s.size() == barrage.projectile_count, "barrage: %d lobs per cast (%d)" % [barrage.projectile_count, s.size()])
	var spread := 0.0
	for x in s:
		spread = maxf(spread, x.target.distance_to(Vector2(600, 300)))
	_check(spread > 30.0 and spread <= barrage.splash_scatter + 0.5, "barrage: lobs scatter around the aim point")
	await _clear_area()

func _check_rain() -> void:
	var rain := _spell("heavy_rain").duplicate() as Spell
	rain.rain_duration = 1.0
	# Drops land at random points; a splash as wide as the zone makes every
	# drop reach the centre enemy, so the damage check is deterministic.
	rain.splash_radius = rain.rain_radius + 5.0
	var e := _enemy(Vector2(600, 300))
	await physics_frame
	_cast(rain, Vector2(600, 300))
	await physics_frame
	var zones := _area.get_children().filter(func(c): return c is WaterRain)
	_check(zones.size() == 1, "rain: one rain zone at the cursor")
	if zones.is_empty():
		return
	var zone: WaterRain = zones[0]
	_check(zone.global_position.is_equal_approx(Vector2(600, 300)), "rain: anchored at the aim point")
	var ended := [false]
	zone.ended.connect(func() -> void: ended[0] = true)
	await _wait(0.9)
	_check(zone.drops >= 5, "rain: keeps dropping splashes (%d)" % zone.drops)
	await _wait(1.0)
	_check(ended[0], "rain: ends after rain_duration")
	_check(e.hp < 1000, "rain: drops damage enemies inside the zone (hp %d)" % e.hp)
	await _clear_area()

func _hostile_shot(at: Vector2, src: Node2D) -> Projectile:
	var p: Projectile = load("res://scenes/projectile.tscn").instantiate()
	p.setup(load("res://resources/spells/head_bolt.tres"), Vector2.LEFT, src)
	_area.add_child(p)
	p.global_position = at
	return p

func _check_bubble() -> void:
	var bubble := _spell("water_bubble")
	var toucher := _enemy(Vector2(440, 300))
	var outside := _enemy(Vector2(600, 300))
	await physics_frame
	_cast(bubble, Vector2(800, 300))
	var sh := _caster.active_shield()
	_check(sh != null and sh.get_parent() == _player, "bubble: shield surrounds the player")
	if sh == null:
		return
	_check(is_equal_approx(sh.radius, bubble.shield_radius) and sh.charges == bubble.shield_charges, "bubble: radius + charges from the spell")
	await _wait(0.1)
	_check(toucher.hp < 1000, "bubble: damages a touching enemy")
	_check(outside.hp == 1000, "bubble: leaves distant enemies alone")
	var hp_after := toucher.hp
	await _wait(0.2)
	_check(toucher.hp == hp_after, "bubble: contact damage waits shield_tick")
	# Player-side shots pass through, hostile ones are absorbed.
	var mine := _hostile_shot(_player.global_position + Vector2(10, 0), _player)
	var popped := [false, -1]
	sh.ended.connect(func(p: bool) -> void:
		popped[0] = true
		popped[1] = int(p))
	await physics_frame
	_check(is_instance_valid(mine) and not mine.is_queued_for_deletion(), "bubble: the player's own shots are not absorbed")
	mine.queue_free()
	for i in bubble.shield_charges:
		var shot := _hostile_shot(_player.global_position + Vector2(20, 0), outside)
		await physics_frame
		await physics_frame
		_check(not is_instance_valid(shot) or shot.is_queued_for_deletion(), "bubble: absorbed hostile shot %d" % (i + 1))
	_check(popped[0] and popped[1] == 1, "bubble: pops after shield_charges absorbs")
	await _clear_area()
	# Time-out.
	var short := bubble.duplicate() as Spell
	short.shield_duration = 0.3
	_cast(short, Vector2(800, 300))
	sh = _caster.active_shield()
	await _wait(0.4)
	_check(_caster.active_shield() == null, "bubble: ends after shield_duration")
	await _clear_area()

func _check_surging() -> void:
	var surging := _spell("surging_bubble").duplicate() as Spell
	surging.shield_duration = 0.2
	var e := _enemy(Vector2(500, 300))
	var far := _enemy(Vector2(800, 300))
	await physics_frame
	var start := e.global_position
	_cast(surging, Vector2(800, 300))
	await _wait(0.25)
	_check(e.is_knocked_back() or e.global_position.x > start.x + 5.0, "surging: shield end knocks a nearby enemy back")
	await _wait(0.4)
	_check(e.global_position.x > start.x + 60.0, "surging: pushed away from the player (%.0f px)" % (e.global_position.x - start.x))
	_check(far.global_position.is_equal_approx(Vector2(800, 300)), "surging: enemies past shield_push_radius stay put")
	await _clear_area()

func _check_big_ball() -> void:
	var big := _spell("big_ball")
	var shot: Spell = big.shield_shot
	_check(shot != null and shot.spell_name == "Water Ball", "big ball: brings back the basic Water Ball")
	_check(big.shield_radius > _spell("surging_bubble").shield_radius and big.shield_duration > _spell("surging_bubble").shield_duration and big.shield_charges > _spell("surging_bubble").shield_charges, "big ball: bigger, longer, absorbs more")
	_cast(big, Vector2(800, 300))
	var sh := _caster.active_shield()
	_check(sh != null, "big ball: shield up")
	if sh == null:
		return
	_check(is_equal_approx(_caster.cooldown_remaining(big), shot.cooldown), "big ball: shield cast costs only the shot cooldown")
	var r0 := sh.radius
	_cast(big, Vector2(800, 300))
	await physics_frame
	_check(_shots(shot).size() == 1, "big ball: recast fires a Water Ball")
	_check(sh.radius < r0 and sh.is_active(), "big ball: the shot shrinks the ball")
	_check(_caster.active_shield() == sh, "big ball: recast keeps the same shield")
	sh.end_shield(false)
	await physics_frame
	_check(is_equal_approx(_caster.cooldown_remaining(big), big.cooldown) or _caster.cooldown_remaining(big) > big.cooldown - 0.05, "big ball: full cooldown starts when the ball ends")
	for i in 30:
		sh.shrink()
	_check(sh.radius >= big.shield_radius * WaterShield.MIN_RADIUS_FRACTION - 0.01, "big ball: shrinking has a floor")
	await _clear_area()

func _check_tree() -> void:
	var progress := SpellProgress.new()
	progress.upgrades = [
		load("res://resources/upgrades/water_guided.tres"),
		load("res://resources/upgrades/water_seeking.tres"),
		load("res://resources/upgrades/water_tidal.tres"),
		load("res://resources/upgrades/water_splash.tres"),
		load("res://resources/upgrades/water_barrage.tres"),
		load("res://resources/upgrades/water_heavy_rain.tres"),
		load("res://resources/upgrades/water_bubble.tres"),
		load("res://resources/upgrades/water_surging_bubble.tres"),
		load("res://resources/upgrades/water_big_ball.tres"),
	]
	var base := _spell("water_ball")
	var paths := progress.get_upgrade_paths(base)
	_check(paths.size() == 3, "tree: three Specialization paths from the base")
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
	await _check_one_route()
	# Production wiring: main.gd registers every Water Ball upgrade.
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	for id in ["water_guided", "water_seeking", "water_tidal", "water_splash", "water_barrage", "water_heavy_rain", "water_bubble", "water_surging_bubble", "water_big_ball"]:
		_check(main_src.contains("upgrades/%s.tres" % id), "main.gd registers %s" % id)
	var table: RewardTable = load("res://resources/rewards/demo_table.tres")
	var found := false
	for entry in table.entries:
		if entry.spell != null and entry.spell.spell_name == "Water Ball":
			found = true
	_check(found, "demo loot table can drop Water Ball")

## Mitra on #339: each row is ONE route. Picking Steer closes Splash and
## Bubble for good, even when a second Water Ball is looted afterwards.
func _check_one_route() -> void:
	var holder := Node2D.new()
	_area.add_child(holder)
	var caster := SpellCaster.new()
	caster.name = "RouteCaster"
	holder.add_child(caster)
	var progress := SpellProgress.new()
	progress.caster_path = NodePath("../RouteCaster")
	for id in ["water_guided", "water_seeking", "water_tidal", "water_splash", "water_barrage", "water_heavy_rain", "water_bubble", "water_surging_bubble", "water_big_ball"]:
		progress.upgrades.append(load("res://resources/upgrades/%s.tres" % id))
	holder.add_child(progress)
	await physics_frame
	var base := _spell("water_ball")
	caster.add_spell(base)
	for i in 10:
		caster.spell_cast.emit(base)
	_check(progress.get_upgrade_paths(base).size() == 3, "route: all three rows offered before choosing")
	_check(progress.apply_upgrade(base, &"water_guided"), "route: Steer (Guided) applies")
	var guided := _spell("water_ball_guided")
	_check(progress.get_upgrade_paths(guided).size() == 1 and progress.get_upgrade_paths(guided)[0].id == &"water_seeking", "route: Guided only continues down Steer")
	# A second base Water Ball looted later must not reopen the other rows.
	caster.add_spell(base)
	_check(progress.route_taken(base), "route: base is marked as route taken")
	_check(progress.get_upgrade_paths(base).is_empty(), "route: Splash/Bubble not offered on a re-looted Water Ball")
	_check(not progress.can_upgrade(base), "route: re-looted Water Ball cannot upgrade")
	_check(not progress.apply_upgrade(base, &"water_splash"), "route: Splash refused after Steer")
	_check(not progress.apply_upgrade(base, &"water_bubble"), "route: Bubble refused after Steer")
	_check(not caster.get_unlocked().has(_spell("water_splash")) and not caster.get_unlocked().has(_spell("water_bubble")), "route: no second branch held")
	# Deeper in the route the lock still holds (Seeking descends from base too).
	for i in 15:
		caster.spell_cast.emit(guided)
	_check(progress.apply_upgrade(guided, &"water_seeking"), "route: Steer continues to Seeking")
	_check(progress.get_upgrade_paths(base).is_empty(), "route: still locked at tier 2")
	holder.queue_free()
	await physics_frame
