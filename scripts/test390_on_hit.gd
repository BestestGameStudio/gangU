extends SceneTree
## #390 harness: the shared on-hit event (OnHit.bus().hit_landed).
## Proves every DamageCalc call site reports one HitEvent per landed hit with
## the standard payload (attacker, spell, target, DamageResult, killed,
## delivery), whatever the delivery:
##   projectile  - Water Ball shot (player -> enemy), incl. a killing hit
##   melee       - Stone Hammer slam
##   splash      - Water Splash landing (one event per enemy in the radius)
##   contact     - Water Bubble touch, a guard Summon's melee, and an enemy's
##                 chase/contact hit on the player (enemy -> player direction)
## Plus the bus contract: amount matches the HP actually lost, killed is set
## only by the hit that took hp to 0, targets without hp never report a kill,
## and a freed Node subscriber is dropped without breaking the emit.
## Run headless:
##   godot --headless --path . -s scripts/test390_on_hit.gd

const DIR := "res://resources/spells/"

class Listener extends Node:
	var seen := 0
	func on_hit(_e: HitEvent) -> void:
		seen += 1

var _area: Node2D
var _player: Player
var _caster: SpellCaster
var _events: Array[HitEvent] = []
var _valid_at_emit: Array[bool] = []
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

func _enemy(pos: Vector2, hp: int = 1000, contact: int = 0) -> Enemy:
	var e: Enemy = load("res://scenes/enemy.tscn").instantiate()
	e.max_hp = hp
	e.speed = 0.0
	e.contact_damage = contact
	_area.add_child(e)
	e.global_position = pos
	return e

func _cast(spell: Spell, aim: Vector2) -> void:
	_caster.aim_override = aim
	_caster._cooldowns.erase(spell)
	_caster._cast_spell(spell)

func _clear_area() -> void:
	for c in _area.get_children():
		if c != _player:
			c.queue_free()
	for c in _player.get_children():
		if c is WaterShield:
			c.queue_free()
	_caster._cooldowns.clear()
	await physics_frame
	await physics_frame
	_events.clear()
	_valid_at_emit.clear()

func _on_hit(e: HitEvent) -> void:
	_events.append(e)
	_valid_at_emit.append(is_instance_valid(e.target) and int(e.target.get(&"hp")) <= 0 if e.killed else is_instance_valid(e.target))

func _for(target: Node) -> Array[HitEvent]:
	var out: Array[HitEvent] = []
	for e in _events:
		if e.target == target:
			out.append(e)
	return out

func _initialize() -> void:
	print("test390: shared on-hit event (#390)")
	_area = Node2D.new()
	root.add_child(_area)
	current_scene = _area
	_player = load("res://scenes/player.tscn").instantiate()
	_player.add_to_group("player")
	_area.add_child(_player)
	_player.global_position = Vector2(400, 300)
	_player.set_invulnerable(true) # only the enemy-contact check lets hits land
	_caster = _player.get_node("SpellCaster")
	await physics_frame
	await physics_frame
	OnHit.bus().hit_landed.connect(_on_hit)

	_check_bus()
	await _check_projectile()
	await _check_projectile_kill()
	await _check_hammer()
	await _check_splash()
	await _check_bubble()
	await _check_summon()
	await _check_enemy_contact()
	await _check_freed_subscriber()

	print("test390 done: %d checks, %d failures" % [_checks, _failures])
	print("RESULT: %s" % ("ALL PASS" if _failures == 0 else "FAIL"))
	quit(1 if _failures > 0 else 0)

func _check_bus() -> void:
	_check(OnHit.bus() == OnHit.bus(), "bus: one shared instance")
	var stub := Node.new() # no hp property
	root.add_child(stub)
	var r := DamageResult.new()
	r.amount = 7
	var e := OnHit.report(_player, null, stub, r, OnHit.DELIVERY_CONTACT, OnHit.is_alive(stub))
	_check(_events.size() == 1 and _events[0] == e, "bus: report() emits hit_landed with the returned event")
	_check(e.attacker == _player and e.target == stub and e.result == r and e.spell == null, "bus: payload carries attacker / target / result / spell")
	_check(not e.killed, "bus: a target without hp never reports a kill")
	stub.queue_free()
	_events.clear()
	_valid_at_emit.clear()

func _check_projectile() -> void:
	var ball := _spell("water_ball")
	var e := _enemy(Vector2(520, 300))
	await physics_frame
	_cast(ball, Vector2(520, 300))
	await _wait(0.6)
	var got := _for(e)
	_check(got.size() == 1, "projectile: one event per landed shot (%d)" % got.size())
	if got.size() == 1:
		var h := got[0]
		_check(h.delivery == OnHit.DELIVERY_PROJECTILE, "projectile: delivery = projectile")
		_check(h.attacker == _player and h.spell == ball, "projectile: attacker = player, spell = Water Ball")
		_check(h.result != null and h.result.amount == 1000 - e.hp and h.result.amount > 0, "projectile: result.amount = HP lost (%d)" % (1000 - e.hp))
		_check(not h.killed, "projectile: non-lethal hit is not a kill")
		_check(h.position.distance_to(e.global_position) < 1.0, "projectile: position = target position")
	await _clear_area()

func _check_projectile_kill() -> void:
	var ball := _spell("water_ball")
	var e := _enemy(Vector2(520, 300), 1)
	await physics_frame
	_cast(ball, Vector2(520, 300))
	await _wait(0.6)
	_check(_events.size() == 1, "kill: exactly one event (%d)" % _events.size())
	if _events.size() == 1:
		_check(_events[0].killed, "kill: lethal hit reports killed = true")
		_check(_valid_at_emit[0], "kill: target is still a valid node (hp 0) when subscribers run")
	var dead := _enemy(Vector2(600, 300), 10)
	dead.hp = 0
	var r := DamageResult.new()
	_check(not OnHit.report(_player, ball, dead, r, OnHit.DELIVERY_PROJECTILE, OnHit.is_alive(dead)).killed, "kill: a hit on an already-dead body is never a kill")
	await _clear_area()

func _check_hammer() -> void:
	var hammer := _spell("stone_hammer")
	var e := _enemy(Vector2(500, 300))
	await physics_frame
	_cast(hammer, Vector2(500, 300))
	await _wait(hammer.hammer_windup + 0.1)
	var got := _for(e)
	_check(got.size() == 1, "melee: one event per hammer hit (%d)" % got.size())
	if got.size() == 1:
		_check(got[0].delivery == OnHit.DELIVERY_MELEE, "melee: delivery = melee")
		_check(got[0].attacker == _player and got[0].spell == hammer, "melee: attacker = player, spell = Stone Hammer")
		_check(got[0].result.amount == 1000 - e.hp, "melee: result.amount = HP lost")
	await _clear_area()

func _check_splash() -> void:
	var splash := _spell("water_splash")
	var a := _enemy(Vector2(600, 300))
	var b := _enemy(Vector2(640, 300))
	var far := _enemy(Vector2(760, 300))
	await physics_frame
	_cast(splash, Vector2(600, 300))
	await _wait(0.8)
	_check(_for(a).size() == 1 and _for(b).size() == 1, "splash: one event per enemy in the radius")
	_check(_for(far).is_empty(), "splash: no event for an enemy outside the radius")
	if _for(a).size() == 1:
		_check(_for(a)[0].delivery == OnHit.DELIVERY_SPLASH and _for(a)[0].spell == splash and _for(a)[0].attacker == _player, "splash: delivery = splash, spell + attacker set")
	await _clear_area()

func _check_bubble() -> void:
	var bubble := _spell("water_bubble")
	var e := _enemy(Vector2(440, 300))
	await physics_frame
	_cast(bubble, Vector2(800, 300))
	await _wait(0.2)
	var got := _for(e)
	_check(got.size() >= 1, "bubble: touch reports a hit (%d)" % got.size())
	if got.size() >= 1:
		_check(got[0].delivery == OnHit.DELIVERY_CONTACT and got[0].spell == bubble, "bubble: delivery = contact, spell = Water Bubble")
	await _clear_area()

func _check_summon() -> void:
	var def := SummonDefinition.new()
	def.max_hp = 30
	def.contact_damage = 5
	def.contact_range = 60.0
	def.contact_cooldown = 0.8
	var s := Summon.new()
	s.setup(def)
	_area.add_child(s)
	s.global_position = Vector2(700, 500)
	var e := _enemy(Vector2(720, 500))
	await physics_frame
	var b := SummonBehaviorGuard.new()
	b.physics_step(s, null, 1.0 / 60.0)
	var got := _for(e)
	_check(got.size() == 1, "summon: guard melee reports one hit (%d)" % got.size())
	if got.size() == 1:
		_check(got[0].delivery == OnHit.DELIVERY_CONTACT and got[0].attacker == s and got[0].spell == null, "summon: delivery = contact, attacker = summon, no spell")
		_check(got[0].result.amount == 1000 - e.hp, "summon: result.amount = HP lost")
	await _clear_area()

func _check_enemy_contact() -> void:
	_player.set_invulnerable(false)
	var e := _enemy(Vector2(410, 300), 1000, 3)
	await _wait(0.1)
	var got := _for(_player)
	_check(got.size() >= 1, "enemy contact: enemy -> player hit reports (%d)" % got.size())
	if got.size() >= 1:
		_check(got[0].delivery == OnHit.DELIVERY_CONTACT and got[0].attacker == e and got[0].spell == null, "enemy contact: delivery = contact, attacker = enemy, no spell")
		_check(got[0].result.amount == 3 and not got[0].killed, "enemy contact: amount from DamageCalc, not a kill")
	_player.set_invulnerable(true)
	_player.heal(_player.max_hp)
	await _clear_area()

func _check_freed_subscriber() -> void:
	# A scene-owned subscriber (bound method on a Node) that gets freed is
	# dropped by Godot; the remaining subscribers keep receiving.
	var listener := Listener.new()
	root.add_child(listener)
	var before := OnHit.bus().hit_landed.get_connections().size()
	OnHit.bus().hit_landed.connect(listener.on_hit)
	var r0 := DamageResult.new()
	OnHit.report(_player, null, _player, r0, OnHit.DELIVERY_CONTACT, true)
	_check(listener.seen == 1 and OnHit.bus().hit_landed.get_connections().size() == before + 1, "subscriber: node listener receives")
	_events.clear()
	_valid_at_emit.clear()
	listener.free()
	_check(OnHit.bus().hit_landed.get_connections().size() == before, "subscriber: freed listener is dropped from the bus")
	var r := DamageResult.new()
	OnHit.report(_player, null, _player, r, OnHit.DELIVERY_CONTACT, true)
	_check(_events.size() == 1, "subscriber: remaining subscribers still receive")
	_events.clear()
	_valid_at_emit.clear()
