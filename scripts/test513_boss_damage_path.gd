extends SceneTree
## Every boss hit (contact, lunge, ring, Warlord spin) goes through
## Enemy.deal_hit: the player's damage modifiers apply and OnHit reports the
## hit. Also: an enemy scene without an EnemyDefinition reports an error.

class ErrorLog extends Logger:
	var messages: Array[String] = []
	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		messages.append(code + " " + rationale)

	func count(fragment: String) -> int:
		return messages.filter(func(m: String) -> bool: return m.contains(fragment)).size()

const MISSING_DEF := "has no EnemyDefinition"

var failures := 0
var _events: Array[HitEvent] = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[513 boss damage] ", label, " -> ", "PASS" if ok else "FAIL")

func _initialize() -> void:
	call_deferred("_run")

func _on_hit(e: HitEvent) -> void:
	_events.append(e)

func _last_event_is(attacker: Enemy, delivery: StringName, hp_lost: int) -> bool:
	if _events.size() != 1:
		return false
	var e := _events[0]
	return e.attacker == attacker and e.delivery == delivery and e.hp_lost == hp_lost

func _run() -> void:
	var log := ErrorLog.new()
	OS.add_logger(log)
	OnHit.bus().hit_landed.connect(_on_hit)
	var area := Node2D.new()
	root.add_child(area)
	var player: Player = load("res://scenes/player.tscn").instantiate()
	area.add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(20, 0)
	player.damage_modifiers.add(DamageModifier.reduction(0.5))
	player.hp = 100
	_check(player.max_hp == 100 and player.hp == 100, "player starts at 100/100")

	var beast: Enemy = load("res://scenes/beast_boss.tscn").instantiate()
	area.add_child(beast)
	beast.set_physics_process(false)
	beast.global_position = Vector2.ZERO
	_check(log.count(MISSING_DEF) == 0, "a boss scene with a definition logs no missing-definition error")
	var bb := beast._behavior as EnemyBehaviorBeast
	_check(bb != null, "beast scene runs the beast behavior")
	var to_player := player.global_position - beast.global_position

	_events.clear()
	bb._contact_timer = 0.0
	bb._attack_timer = 999.0
	bb._chase(beast, player, to_player, 0.016, null)
	_check(player.hp == 94, "contact 12 halved by the player's reduction (hp %d, want 94)" % player.hp)
	_check(_last_event_is(beast, OnHit.DELIVERY_CONTACT, 6), "contact reports one contact hit for 6")

	_events.clear()
	bb._dir = Vector2.RIGHT
	bb._hits = 0
	bb._lunge_step(beast, player, 0.0)
	_check(player.hp == 85, "lunge 18 halved (hp %d, want 85)" % player.hp)
	_check(_last_event_is(beast, OnHit.DELIVERY_CONTACT, 9), "lunge reports one contact hit for 9")

	_events.clear()
	bb._ring_release(beast, player, to_player, 200.0, null)
	_check(player.hp == 78, "ring 15 halved and truncated (hp %d, want 78)" % player.hp)
	_check(_last_event_is(beast, OnHit.DELIVERY_SPLASH, 7), "ring reports one splash hit for 7")

	_events.clear()
	bb._ring_release(beast, player, Vector2(500, 0), 200.0, null)
	_check(player.hp == 78 and _events.is_empty(), "ring out of range: no damage, no report")

	_events.clear()
	player.set_invulnerable(true)
	bb._hits = 0
	bb._lunge_step(beast, player, 0.0)
	player.set_invulnerable(false)
	_check(player.hp == 78 and _events.is_empty() and bb._hits == 1, "refused lunge (invulnerable): no damage, no report")

	_events.clear()
	var amp := DamageModifier.amp(1.0)
	beast.damage_modifiers.add(amp)
	bb._contact_timer = 0.0
	bb._chase(beast, player, to_player, 0.016, null)
	beast.damage_modifiers.remove(amp)
	_check(player.hp == 66, "boss AMP doubles contact before the reduction (hp %d, want 66)" % player.hp)
	_check(_last_event_is(beast, OnHit.DELIVERY_CONTACT, 12), "amped contact reports 12")

	var warlord: Enemy = load("res://scenes/mustache_warlord.tscn").instantiate()
	area.add_child(warlord)
	warlord.set_physics_process(false)
	warlord.global_position = Vector2.ZERO
	var wb := warlord._behavior as EnemyBehaviorWarlord
	_check(wb != null, "warlord scene runs the warlord behavior")
	_events.clear()
	wb._t = 0.0
	wb._tick_t = 0.0
	wb._spin(warlord, player, player.global_position - warlord.global_position, 0.016, null)
	_check(player.hp == 60, "spin 12 halved (hp %d, want 60)" % player.hp)
	_check(_last_event_is(warlord, OnHit.DELIVERY_MELEE, 6), "spin reports one melee hit for 6")

	var bare: Enemy = load("res://scenes/enemy_base.tscn").instantiate()
	area.add_child(bare)
	bare.set_physics_process(false)
	_check(log.count(MISSING_DEF) == 1, "enemy_base.tscn without a definition logs the missing-definition error")
	_check(bare.max_hp == 0, "no definition: no stats to fall back on")

	OnHit.bus().hit_landed.disconnect(_on_hit)
	OS.remove_logger(log)
	area.free()
	print("[513 boss damage] DONE failures=", failures)
	quit(1 if failures else 0)
