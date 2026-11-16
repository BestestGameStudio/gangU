extends SceneTree
## #696 harness: the hit stop decision rules.
##   - local by default: a normal hit freezes only the enemy it hit
##   - overlapping requests merge by max remaining time, never stack
##   - the rolling global budget and the global cooldown drop (never queue)
##     heavy-hit freezes, and the local stop still plays
##   - multi-hit volleys stop on the first hit, not every hit
##   - rapid spells never get a global stop
##   - the boss finisher outranks normal stops and restores the time scale
## HitStop is driven by hand (set_process(false) + _process(delta)) so the
## timing is exact. Run headless:
##   godot --headless --path . -s tests/combat/test_hit_stop.gd

const STEP := 1.0 / 60.0

class Mover extends Node2D:
	var claims := 0
	func set_frozen(f: bool) -> void:
		claims = maxi(claims + (1 if f else -1), 0)
	func frozen() -> bool:
		return claims > 0

var _failures := 0
var _checks := 0
var _hs: HitStop

func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if ok:
		print("PASS: %s" % msg)
	else:
		_failures += 1
		print("FAIL: %s" % msg)

func _initialize() -> void:
	call_deferred("_run")

func _fresh() -> void:
	if is_instance_valid(_hs):
		_hs.free()
	Engine.time_scale = 1.0
	_hs = HitStop.new()
	root.add_child(_hs)
	_hs.set_process(false)

func _mover(group: StringName) -> Mover:
	var m := Mover.new()
	m.add_to_group(group)
	root.add_child(m)
	return m

func _spell(cooldown: float, count: int = 1, mult: float = 1.0) -> Spell:
	var s := Spell.new()
	s.cooldown = cooldown
	s.projectile_count = count
	s.hit_stop = mult
	return s

func _hit(target: Node, spell: Spell, amount: int, killed: bool = false, tier: int = 0) -> void:
	var e := HitEvent.new()
	e.target = target
	e.spell = spell
	e.killed = killed
	e.position = (target as Node2D).global_position
	e.result = DamageResult.new()
	e.result.amount = amount
	e.result.crit_tier = tier
	_hs._on_hit_landed(e)

func _step(seconds: float, time_scale: float = 1.0) -> void:
	for i in int(round(seconds / STEP)):
		_hs._process(STEP * time_scale)

func _run() -> void:
	var player := _mover(PhysicsLayers.PLAYER_GROUP)
	var a := _mover(PhysicsLayers.ENEMY_GROUP)
	var b := _mover(PhysicsLayers.ENEMY_GROUP)
	var c := _mover(PhysicsLayers.ENEMY_GROUP)
	var normal := _spell(0.6)

	# --- local by default ---
	_fresh()
	_hit(a, normal, 10)
	_check(a.frozen() and not b.frozen() and not player.frozen(), "normal hit freezes only the enemy it hit")
	_check(_hs.is_local_active(a) and not _hs.is_global_active(), "normal hit is a local stop, not global")
	_step(0.07)
	_check(not a.frozen(), "local stop ends on its own")
	_hit(a, normal, 10)
	_check(not a.frozen(), "re-arm gap: the same enemy is not re-frozen right after a stop")
	_step(0.15)
	_hit(a, normal, 10)
	_check(a.frozen(), "after the gap a new local stop starts")
	_step(0.2)

	# --- overlapping local requests merge, never stack or restart ---
	_fresh()
	for i in 6:
		_hit(a, normal, 10)
	_check(a.claims == 1, "six simultaneous hits on one enemy hold ONE claim")
	_step(0.5)
	_check(not a.frozen(), "merged local stop is capped, not extended by every hit")

	# --- heavy hit: global + budget + cooldown ---
	_fresh()
	var heavy := _spell(1.0)
	_hit(a, heavy, 60)
	_check(_hs.is_global_active() and a.frozen() and b.frozen() and player.frozen(), "heavy hit freezes the whole world")
	var used := 0.1 - _hs.global_budget_left()
	# Five more heavy hits in the same impact window merge, never add up.
	for i in 5:
		_hit(b, heavy, 60)
	_check(a.claims == 1 and b.claims == 1 and player.claims == 1, "simultaneous heavy hits hold one claim per mover")
	_check(0.1 - _hs.global_budget_left() <= used + 0.0001, "simultaneous heavy hits do not add global time")
	_step(0.2)
	_check(not _hs.is_global_active() and not a.frozen() and not player.frozen(), "global stop releases everyone")

	# --- cooldown: a second heavy hit too soon is local only, not queued ---
	_hit(b, heavy, 60)
	_check(not _hs.is_global_active() and b.frozen(), "global cooldown rejects the freeze, local stop still plays")
	_step(0.4)
	_check(not b.frozen() and not _hs.is_global_active(), "a rejected global request is never queued")

	# --- budget exhaustion ---
	_fresh()
	_hs.global_cooldown = 0.1
	_hs.global_budget_seconds = 0.1
	_hit(a, heavy, 60)
	_step(0.2)
	_hit(b, heavy, 60) # +0.2s: budget left ~0.033
	var second_len := _hs._stop_length
	_check(_hs.is_global_active() and second_len < 0.0667, "partial budget grants a shorter global stop")
	_step(0.2)
	_hit(c, heavy, 60) # budget gone
	_check(not _hs.is_global_active() and c.frozen(), "exhausted budget skips the global stop, local stop plays")
	_step(1.0)
	_check(_hs.global_budget_left() > 0.09, "budget refills after the rolling window")
	_hit(a, heavy, 60)
	_check(_hs.is_global_active(), "global stop is available again after the window")
	_step(0.2)

	# --- multi-hit volley stops on the first hit only ---
	_fresh()
	var volley := _spell(1.2, 3)
	_hit(a, volley, 10)
	_hit(b, volley, 10)
	_hit(c, volley, 10)
	_check(a.frozen() and not b.frozen() and not c.frozen(), "multi-hit volley stops on the first hit only")
	_step(0.5)
	# A heavy killing blow still passes the volley gate.
	_hit(a, volley, 60, true)
	_check(_hs.is_global_active(), "a heavy killing blow in a volley still stops")
	_step(0.2)

	# --- rapid spells never go global ---
	_fresh()
	var rapid := _spell(0.2)
	_hit(a, rapid, 80, false, 3)
	_check(not _hs.is_global_active() and a.frozen(), "rapid spell never gets a global stop, even on a big roll")
	_step(0.2)

	# --- boss finisher priority ---
	_fresh()
	var boss := _mover(PhysicsLayers.ENEMY_GROUP)
	boss.add_to_group(&"boss")
	_hit(a, heavy, 60) # a normal global stop is running
	_hit(boss, heavy, 60, true)
	_check(_hs.is_boss_active() and is_equal_approx(Engine.time_scale, _hs.boss_slowmo_scale), "boss kill starts the finisher (slow-mo on)")
	_check(player.frozen() and a.frozen(), "finisher freezes the world, player included")
	var length := _hs._stop_length
	_hit(b, heavy, 60)
	_hit(c, normal, 10)
	_check(is_equal_approx(_hs._stop_length, length) and not _hs.is_local_active(c), "normal hits cannot touch the finisher")
	_step(length + 0.05, _hs.boss_slowmo_scale)
	_check(not _hs.is_boss_active() and not player.frozen() and not a.frozen(), "finisher releases everyone when its beat ends")
	_step(_hs.zoom_out_time + 0.1, 1.0)
	_check(is_equal_approx(Engine.time_scale, 1.0), "time scale returns to 1.0 after the finisher")

	_fresh()
	Engine.time_scale = 1.0
	print("[hit stop] checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
