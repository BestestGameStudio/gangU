extends SceneTree
## #426: boss-drop relic "Twin Dash" - two dash charges.
##  - Without the relic the dash keeps its single charge / 0.6s cooldown.
##  - Owning the relic gives two charges: two back-to-back dashes, the third
##    refused; charges recharge one at a time (dash_cooldown each).
##  - Any "boss"-group enemy rolls a 50% relic drop on death (ground pickup,
##    beside its reward-table drop); non-bosses never do; owned = no roll.
##  - Pickup grants through OwnedRelics; a second floor copy is consumed
##    without a duplicate grant.
## Run headless:
##   godot --headless --path . -s scripts/test426_twin_dash.gd

const TWIN_DASH := "res://resources/relics/twin_dash.tres"

var _area: Node2D
var _player: Player
var _relics: OwnedRelics
var _checks := 0
var _failures := 0

func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if ok:
		print("PASS: %s" % msg)
	else:
		_failures += 1
		print("FAIL: %s" % msg)

func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await physics_frame

func _initialize() -> void:
	_run.call_deferred()

func _drops() -> Array[RewardDrop]:
	var out: Array[RewardDrop] = []
	for c in _area.get_children():
		if c is RewardDrop and not c.is_queued_for_deletion():
			out.append(c)
	return out

func _relic_drops() -> Array[RewardDrop]:
	var out: Array[RewardDrop] = []
	for d in _drops():
		if d.entry != null and d.entry.kind == RewardEntry.Kind.RELIC:
			out.append(d)
	return out

func _kill(scene: String, pos: Vector2, boss: bool) -> Enemy:
	var e: Enemy = load(scene).instantiate()
	e.speed = 0.0
	e.contact_damage = 0
	if boss:
		e.add_to_group("boss")
	_area.add_child(e)
	e.global_position = pos
	await _frames(2)
	e.apply_damage(e.max_hp * 10)
	await _frames(3)
	return e

func _clear_drops() -> void:
	for d in _drops():
		d.queue_free()
	await _frames(2)

func _run() -> void:
	_area = Node2D.new()
	get_root().add_child(_area)
	current_scene = _area
	_player = load("res://scenes/player.tscn").instantiate()
	_player.position = Vector2(400, 300)
	_area.add_child(_player)
	await _frames(2)

	# --- Relic data -------------------------------------------------------
	var relic: Relic = load(TWIN_DASH)
	_check(relic != null and relic.id == &"twin_dash" and relic.is_valid_definition(), "twin_dash relic resource is a valid definition")
	_check(relic.scalar_effects.get(Player.DASH_CHARGES_KEY, 0.0) == 1.0, "relic adds exactly one dash charge")

	# --- No relic provider: single charge, classic cooldown ---------------
	_check(_player.dash_max_charges() == 1 and _player.dash_charges() == 1, "no OwnedRelics: one dash charge")
	_check(_player.try_dash(Vector2.RIGHT), "first dash starts")
	await _frames(12)
	_check(not _player.is_dashing(), "dash finished")
	_check(not _player.try_dash(Vector2.RIGHT), "single charge: second dash refused on cooldown")
	_check(_player.dash_cooldown_remaining() > 0.0, "cooldown running with no charges")
	await _frames(30)
	_check(_player.dash_charges() == 1 and is_zero_approx(_player.dash_cooldown_remaining()), "single charge back after 0.6s")

	# --- Mount OwnedRelics without the relic: still one charge ------------
	_relics = OwnedRelics.new()
	_area.add_child(_relics)
	await _frames(2)
	_check(_player.dash_max_charges() == 1, "OwnedRelics without twin_dash: one charge")

	# --- BossRelicDrop.pick contract --------------------------------------
	_check(BossRelicDrop.drop_chance == 0.5, "production drop chance is 50%")
	_check(BossRelicDrop.pick(_relics, 0.0) != null and BossRelicDrop.pick(_relics, 0.0).id == &"twin_dash", "roll below 0.5 picks twin_dash")
	_check(BossRelicDrop.pick(_relics, 0.4999) != null, "roll 0.4999 drops")
	_check(BossRelicDrop.pick(_relics, 0.5) == null, "roll 0.5 does not drop")
	_check(BossRelicDrop.pick(null, 0.0) == null, "no OwnedRelics: no drop")
	var hits := 0
	for i in 4000:
		if BossRelicDrop.pick(_relics, randf()) != null:
			hits += 1
	var rate := float(hits) / 4000.0
	print("[426] observed drop rate over 4000 rolls: ", rate)
	_check(rate > 0.45 and rate < 0.55, "observed drop rate ~50% (0.45..0.55)")

	# --- Non-boss never drops the relic -----------------------------------
	BossRelicDrop.drop_chance = 1.0
	await _kill("res://scenes/enemy.tscn", Vector2(100, 100), false)
	_check(_relic_drops().is_empty(), "non-boss enemy death never drops a relic")
	await _clear_drops()

	# --- Forced-miss boss: no relic, token still drops --------------------
	BossRelicDrop.drop_chance = 0.0
	await _kill("res://scenes/mustache_warlord.tscn", Vector2(100, 100), true)
	_check(_relic_drops().is_empty(), "boss with a failed roll drops no relic")
	await _clear_drops()

	# --- Forced-hit boss: relic lands beside the token ---------------------
	BossRelicDrop.drop_chance = 1.0
	for scene in ["res://scenes/mustache_warlord.tscn", "res://scenes/head_boss.tscn", "res://scenes/beast_boss.tscn"]:
		await _kill(scene, Vector2(100, 100), true)
		var rd := _relic_drops()
		var token := false
		for d in _drops():
			if d.entry != null and d.entry.kind == RewardEntry.Kind.UPGRADE_TOKEN:
				token = true
		_check(rd.size() == 1 and rd[0].entry.relic.id == &"twin_dash", "%s drops the Twin Dash relic" % scene.get_file())
		_check(token, "%s still drops its upgrade token" % scene.get_file())
		if rd.size() == 1:
			_check(rd[0].get_node("NameLabel").text == "Twin Dash", "relic drop is labeled Twin Dash")
		if scene != "res://scenes/beast_boss.tscn":
			await _clear_drops()
	var floor_copies := _relic_drops()
	_check(floor_copies.size() == 1, "one relic drop left on the floor")

	# A second floor copy (as if a second boss dropped before pickup).
	var extra: RewardDrop = load("res://scenes/reward_drop.tscn").instantiate()
	extra.setup(BossRelicDrop.entry_for(relic))
	extra.global_position = Vector2(700, 500)
	_area.add_child(extra)
	await _frames(2)

	# --- Pickup grants the relic -> two charges ---------------------------
	_player.global_position = floor_copies[0].global_position
	await _frames(4)
	_check(_relics.has_id(&"twin_dash") and _relics.count() == 1, "walk-over pickup grants twin_dash")
	_check(_player.dash_max_charges() == 2, "relic owned: two dash charges max")
	await _frames(2)
	_check(_player.dash_charges() == 2, "new charge slot fills immediately")
	_check(BossRelicDrop.pick(_relics, 0.0) == null, "owned relic is never rolled again")

	# A boss killed now drops no relic even at 100%.
	for d in _drops():
		if d != extra:
			d.queue_free()
	await _frames(2)
	await _kill("res://scenes/mustache_warlord.tscn", Vector2(100, 100), true)
	var after := _relic_drops()
	_check(after.size() == 1 and after[0] == extra, "boss kill while owning the relic drops no new relic")

	# Stale floor copy: consumed, no duplicate.
	_player.global_position = extra.global_position
	await _frames(4)
	_check(not is_instance_valid(extra) or extra.is_queued_for_deletion(), "second floor copy consumed without a duplicate grant")
	_check(_relics.count() == 1, "still exactly one owned relic")

	# --- Dash twice ---------------------------------------------------------
	_player.global_position = Vector2(400, 300)
	var start := _player.global_position
	_check(_player.try_dash(Vector2.RIGHT), "relic: first dash starts")
	await _frames(12)
	_check(not _player.is_dashing() and _player.dash_charges() == 1, "after first dash one charge remains")
	_check(is_zero_approx(_player.dash_cooldown_remaining()), "cooldown reads 0 while a charge is ready")
	_check(_player.try_dash(Vector2.RIGHT), "relic: second back-to-back dash starts")
	await _frames(12)
	var moved := _player.global_position - start
	print("[426] two dashes moved ", moved)
	# #450: compare against the base dash distance (81 px) instead of a hard
	# number, so range tuning does not break this check.
	var one_dash := _player.dash_speed * _player.dash_duration
	_check(moved.x > one_dash * 1.8, "two dashes cover about double the distance")
	_check(_player.dash_charges() == 0 and not _player.try_dash(Vector2.LEFT), "third dash refused with no charges")
	_check(_player.dash_cooldown_remaining() > 0.0, "cooldown running once both charges are spent")
	# First recharge started at the first dash (frame 0); 24 frames gone.
	await _frames(14) # ~0.63s since first dash
	_check(_player.dash_charges() == 1, "one charge recharged after one dash_cooldown")
	await _frames(20) # ~0.97s: second still recharging (sequential)
	_check(_player.dash_charges() == 1, "charges recharge one at a time")
	await _frames(20) # ~1.3s: both back
	_check(_player.dash_charges() == 2, "both charges back after two dash_cooldowns")

	BossRelicDrop.drop_chance = 0.5
	print("[426] DONE checks=%d failures=%d" % [_checks, _failures])
	print("RESULT: ", "ALL PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
