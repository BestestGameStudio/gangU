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
## Plus the bus contract: result.amount is the DamageCalc roll and hp_lost the
## HP actually removed (they differ on overkill), killed is set only by the
## hit that took hp to 0, targets without hp never report a kill, and a freed
## Node subscriber is dropped without breaking the emit.
## Review of #410 boundaries:
##   - a shot / splash landing after its shooter was freed reports attacker
##     = null without a script error, and the shot's despawn still runs
##   - receiver-refused damage emits NOTHING: invulnerable Player (contact and
##     enemy shot), already-dead target, DestroyableContainer refusing a
##     non-Player source; an accepted 0-damage hit still lands (hp_lost 0)
##   - killed / hp_lost are captured at the receiver's HP mutation, so a
##     synchronous revive (RunManager + ReviveSatchel) keeps killed = true and
##     a legacy Projectile.hit listener's lethal follow-up keeps killed = false
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

## An accepted receipt for a non-recording target (fallback path).
func _stub_receipt(stub: Node) -> OnHit.Receipt:
	return OnHit.end(OnHit.begin(stub), stub)

func _shot(spell: Spell, src: Node2D, dir: Vector2 = Vector2.RIGHT) -> Projectile:
	var p: Projectile = load("res://scenes/projectile.tscn").instantiate()
	p.setup(spell, dir, src)
	_area.add_child(p)
	return p

func _flat_spell(dmg: float) -> Spell:
	var s: Spell = _spell("water_ball").duplicate()
	s.damage = dmg
	s.tags = s.tags.duplicate()
	s.tags.erase(SpellTags.PIERCING)
	s.pierce_hits = 0
	return s

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
	await _check_freed_source()
	await _check_refusals()
	await _check_overkill_and_zero()
	await _check_killed_vs_revive()
	await _check_killed_vs_followup()

	print("test390 done: %d checks, %d failures" % [_checks, _failures])
	print("RESULT: %s" % ("ALL PASS" if _failures == 0 else "FAIL"))
	quit(1 if _failures > 0 else 0)

func _check_bus() -> void:
	_check(OnHit.bus() == OnHit.bus(), "bus: one shared instance")
	var stub := Node.new() # no hp property
	root.add_child(stub)
	var r := DamageResult.new()
	r.amount = 7
	var e := OnHit.report(_player, null, stub, r, OnHit.DELIVERY_CONTACT, _stub_receipt(stub))
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
		_check(h.result != null and h.hp_lost == 1000 - e.hp and h.result.amount == h.hp_lost and h.result.amount > 0, "projectile: hp_lost = HP lost (%d), = roll when not overkill" % (1000 - e.hp))
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
	r.amount = 5
	var rc := OnHit.begin(dead)
	dead.apply_damage(5)
	OnHit.end(rc, dead)
	_check(OnHit.report(_player, ball, dead, r, OnHit.DELIVERY_PROJECTILE, rc) == null, "kill: a hit on an already-dead body is refused (no event, never a kill)")
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
		_check(got[0].hp_lost == 1000 - e.hp and got[0].result.amount == got[0].hp_lost, "melee: hp_lost = HP lost (= roll, not overkill)")
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
		_check(got[0].hp_lost == 1000 - e.hp and got[0].result.amount == got[0].hp_lost, "summon: hp_lost = HP lost (= roll, not overkill)")
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
	var stub := Node.new()
	root.add_child(stub)
	var r0 := DamageResult.new()
	OnHit.report(_player, null, stub, r0, OnHit.DELIVERY_CONTACT, _stub_receipt(stub))
	_check(listener.seen == 1 and OnHit.bus().hit_landed.get_connections().size() == before + 1, "subscriber: node listener receives")
	_events.clear()
	_valid_at_emit.clear()
	listener.free()
	_check(OnHit.bus().hit_landed.get_connections().size() == before, "subscriber: freed listener is dropped from the bus")
	var r := DamageResult.new()
	OnHit.report(_player, null, stub, r, OnHit.DELIVERY_CONTACT, _stub_receipt(stub))
	_check(_events.size() == 1, "subscriber: remaining subscribers still receive")
	stub.queue_free()
	_events.clear()
	_valid_at_emit.clear()

# ---- review of #410 ---------------------------------------------------------

func _check_freed_source() -> void:
	# P1: a shot that outlives its shooter. Real flight into an enemy after the
	# shooter node was freed.
	var shooter := Node2D.new()
	_area.add_child(shooter)
	shooter.global_position = Vector2(100, 600)
	var e := _enemy(Vector2(220, 600))
	await physics_frame
	var p := _shot(_flat_spell(9.0), shooter)
	p.global_position = Vector2(130, 600)
	shooter.free()
	await _wait(0.5)
	var got := _for(e)
	_check(got.size() == 1, "freed source: shot landing after its shooter was freed still reports (%d)" % got.size())
	if got.size() == 1:
		_check(got[0].attacker == null and got[0].hp_lost == 1000 - e.hp and got[0].hp_lost > 0, "freed source: attacker normalized to null, damage applied")
	_check(not is_instance_valid(p) or p.is_queued_for_deletion(), "freed source: despawn continuation after the hit still ran")
	# Direct dispatch too (deterministic: no physics in between).
	var shooter2 := Node2D.new()
	_area.add_child(shooter2)
	var e2 := _enemy(Vector2(400, 800))
	var p2 := _shot(_flat_spell(9.0), shooter2)
	p2.global_position = Vector2(0, 900)
	shooter2.free()
	_events.clear()
	p2._on_body_entered(e2)
	_check(_for(e2).size() == 1 and _for(e2)[0].attacker == null, "freed source: direct _on_body_entered reports attacker = null")
	_check(p2.is_queued_for_deletion(), "freed source: direct hit queues the shot's despawn")
	# Splash / rain share WaterSplash.deal_damage: freed caster too.
	var caster := Node2D.new()
	_area.add_child(caster)
	caster.free()
	var e3 := _enemy(Vector2(400, 900))
	_events.clear()
	WaterSplash.deal_damage(e3, _spell("water_splash"), caster)
	_check(_for(e3).size() == 1 and _for(e3)[0].attacker == null and e3.hp < 1000, "freed source: splash after its caster was freed reports attacker = null")
	await _clear_area()

func _check_refusals() -> void:
	# P2: the receiver decides "landed"; refused damage emits nothing.
	_player.set_invulnerable(true)
	var hp0 := _player.hp
	# Invulnerable Player vs enemy contact.
	var e := _enemy(Vector2(410, 300), 1000, 7)
	await _wait(0.1)
	_check(_player.hp == hp0 and _for(_player).is_empty(), "refusal: invulnerable Player contact -> HP unchanged, no event (%d)" % _for(_player).size())
	e.queue_free()
	await physics_frame
	# Invulnerable Player vs enemy projectile (direct dispatch).
	var shooter := _enemy(Vector2(900, 900))
	var p := _shot(_flat_spell(8.0), shooter)
	p.global_position = Vector2(900, 100)
	_events.clear()
	p._on_body_entered(_player)
	_check(_player.hp == hp0 and _for(_player).is_empty(), "refusal: enemy shot vs invulnerable Player -> HP unchanged, no event")
	# Player-only DestroyableContainer refusing an enemy-sourced shot.
	var def := ContainerDefinition.new()
	var c: DestroyableContainer = preload("res://scenes/destroyable_container.tscn").instantiate()
	c.definition = def
	_area.add_child(c)
	c.global_position = Vector2(900, 400)
	await physics_frame
	var chp := c.hp
	var p2 := _shot(_flat_spell(8.0), shooter)
	p2.global_position = Vector2(900, 150)
	_events.clear()
	p2._on_body_entered(c)
	_check(c.hp == chp and _for(c).is_empty(), "refusal: container refuses an enemy-sourced shot -> HP unchanged, no event")
	# ... and the same container accepts a Player-sourced shot: it lands.
	var p3 := _shot(_flat_spell(3.0), _player)
	p3.global_position = Vector2(900, 200)
	p3._on_body_entered(c)
	_check(c.hp < chp and _for(c).size() == 1 and _for(c)[0].hp_lost == chp - c.hp, "refusal: container accepts a Player shot -> one event, hp_lost = HP lost")
	# Container's sourceless apply_damage path is refused too.
	_events.clear()
	var rc := OnHit.begin(c)
	c.apply_damage(4)
	OnHit.end(rc, c)
	_check(OnHit.report(_player, null, c, DamageResult.new(), OnHit.DELIVERY_SPLASH, rc) == null and _events.is_empty(), "refusal: container's unknown-source apply_damage -> no event")
	await _clear_area()

func _check_overkill_and_zero() -> void:
	# Non-blocking doc point: result.amount is the roll, hp_lost what was lost.
	var e := _enemy(Vector2(900, 700), 1)
	var shooter := Node2D.new()
	_area.add_child(shooter)
	var p := _shot(_flat_spell(12.0), shooter)
	p.global_position = Vector2(900, 50)
	p._on_body_entered(e)
	var got := _for(e)
	_check(got.size() == 1 and got[0].result.amount >= 12 and got[0].hp_lost == 1 and got[0].killed, "overkill: roll %s, hp_lost 1, killed" % (str(got[0].result.amount) if got.size() == 1 else "?"))
	# Accepted 0-damage hit still lands (the receiver took it).
	var e2 := _enemy(Vector2(900, 750), 50)
	_events.clear()
	var rc := OnHit.begin(e2)
	e2.apply_damage(0)
	OnHit.end(rc, e2)
	var ev := OnHit.report(_player, null, e2, DamageResult.new(), OnHit.DELIVERY_CONTACT, rc)
	_check(ev != null and ev.hp_lost == 0 and not ev.killed, "zero damage: an accepted 0-damage hit lands with hp_lost 0")
	await _clear_area()

func _check_killed_vs_revive() -> void:
	# P3a: synchronous revive in died() must not erase this hit's kill.
	_player.set_invulnerable(false)
	var satchel := ReviveSatchel.new()
	satchel.player_path = _player.get_path()
	_area.add_child(satchel)
	satchel.collect()
	var rm := RunManager.new()
	rm.player = _player
	rm.satchel = satchel
	_area.add_child(rm)
	await physics_frame
	await physics_frame
	_player.hp = 1
	var shooter := _enemy(Vector2(900, 900))
	var p := _shot(_flat_spell(8.0), shooter)
	p.global_position = Vector2(900, 80)
	_events.clear()
	p._on_body_entered(_player)
	var got := _for(_player)
	_check(satchel.carried == 0 and _player.hp == satchel.revive_hp, "revive: satchel consumed, Player healed to %d (hp %d)" % [satchel.revive_hp, _player.hp])
	_check(got.size() == 1 and got[0].killed and got[0].hp_lost == 1, "revive: HitEvent.killed = true, hp_lost = 1 despite the synchronous revive")
	_player.died.disconnect(rm._on_player_died)
	rm.free()
	satchel.free()
	_player.heal(_player.max_hp)
	_player.set_invulnerable(true)
	await _clear_area()

func _check_killed_vs_followup() -> void:
	# P3b: a legacy Projectile.hit listener's lethal follow-up is not this
	# hit's kill.
	var e := _enemy(Vector2(900, 650), 100)
	var shooter := Node2D.new()
	_area.add_child(shooter)
	var p := _shot(_flat_spell(12.0), shooter)
	p.global_position = Vector2(900, 60)
	p.hit.connect(func(body: Node2D) -> void: body.apply_damage(1000))
	_events.clear()
	p._on_body_entered(e)
	var got := _for(e)
	_check(e.hp == 0, "follow-up: the legacy hit listener did kill the enemy")
	_check(got.size() == 1 and not got[0].killed and got[0].hp_lost == got[0].result.amount and got[0].hp_lost < 100, "follow-up: HitEvent.killed = false, hp_lost = this shot's damage only")
	await _clear_area()
