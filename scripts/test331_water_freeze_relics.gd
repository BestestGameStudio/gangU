extends SceneTree
## #331 review repair harness (stove-jebs CHANGES_REQUESTED on 6b5a43f):
##  P1 - Water Ball lobs (WaterSplash), rain zones (WaterRain) and rain drops
##       follow The World's freeze contract: balanced, reference-counted
##       claims from FreezeBubble, held motion / clock / animation, attacks
##       spawned inside an active bubble claimed before they move, overlapping
##       bubbles release independently, no leaked or doubled claims.
##  P2 - splash / rain / shield damage composes matching owned-relic
##       modifiers (like Projectile.setup) without mutating the source's
##       collection; non-matching relics and absent providers are neutral;
##       attacker crit and receiver reduction still apply.
## Run headless:
##   godot --headless --path . -s scripts/test331_water_freeze_relics.gd

const DIR := "res://resources/spells/"

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

func _spell(n: String) -> Spell:
	return load(DIR + n + ".tres")

func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await physics_frame

func _wait(seconds: float) -> void:
	await _frames(int(ceil(seconds * 60.0)))

func _enemy(pos: Vector2) -> Enemy:
	var e: Enemy = load("res://scenes/enemy.tscn").instantiate()
	e.max_hp = 1000
	e.speed = 0.0
	e.contact_damage = 0
	_area.add_child(e)
	e.global_position = pos
	return e

## Records every damage amount an enemy takes.
func _record(e: Enemy) -> Array:
	var hits: Array = []
	var last := [e.max_hp]
	e.health_changed.connect(func(hp: int, _max: int) -> void:
		hits.append(last[0] - hp)
		last[0] = hp)
	return hits

func _clear() -> void:
	for c in _area.get_children():
		if c != _player and c != _relics:
			c.queue_free()
	for c in _player.get_children():
		if c is WaterShield:
			c.queue_free()
	await _frames(2)

func _bubble(at: Vector2, r: float, dur: float) -> FreezeBubble:
	return FreezeBubble.spawn(_area, at, r, dur)

func _drops() -> Array[WaterSplash]:
	var out: Array[WaterSplash] = []
	for c in _area.get_children():
		if c is WaterSplash and not c.is_queued_for_deletion():
			out.append(c)
	return out

func _wait_release(b: FreezeBubble) -> void:
	var guard := 0
	while is_instance_valid(b) and not b._releasing and guard < 1200:
		await physics_frame
		guard += 1

## Replace the owned-relics provider with one holding a single AOE AMP relic
## hooked to `tag` (or none at all when tag is empty).
func _set_relic(tag: StringName, amp: float = 1.0) -> void:
	if _relics != null:
		_relics.remove_from_group("owned_relics")
		_relics.free()
		_relics = null
	if tag == &"":
		return
	_relics = OwnedRelics.new()
	_area.add_child(_relics)
	var r := Relic.new()
	r.id = &"test331_fixture"
	r.display_name = "Fixture relic"
	r.hooked_tags = [tag]
	r.amount = amp
	_check(_relics.add(r), "relic fixture (%s) accepted" % tag)

func _initialize() -> void:
	print("test331_water_freeze_relics (#331 review repair)")
	_area = Node2D.new()
	root.add_child(_area)
	current_scene = _area
	_player = load("res://scenes/player.tscn").instantiate()
	_player.add_to_group("player")
	_area.add_child(_player)
	_player.global_position = Vector2(400, 300)
	_player.set_physics_process(false)
	await _frames(2)

	await _check_reproduction()
	await _check_spawned_inside()
	await _check_overlap()
	await _check_relics_splash()
	await _check_relics_rain()
	await _check_relics_shield()

	print("test331_water_freeze_relics done: %d checks, %d failures" % [_checks, _failures])
	print("RESULT: %s" % ("ALL PASS" if _failures == 0 else "FAIL"))
	quit(1 if _failures > 0 else 0)

## The reviewer's reproduction: 1.5 s lob (400,300)->(600,300), Heavy Rain at
## (600,300), production FreezeBubble at (550,300) r350 / 5 s.
func _check_reproduction() -> void:
	var e := _enemy(Vector2(600, 300))
	var hp0 := e.hp
	var lob := WaterSplash.spawn(_area, _spell("water_splash"), _player, Vector2(400, 300), Vector2(600, 300), 70.0, 1.5)
	var rain := WaterRain.spawn(_area, _spell("heavy_rain"), _player, Vector2(600, 300))
	await _frames(3)
	var b := _bubble(Vector2(550, 300), 350.0, 5.0)
	await _wait(0.4) # expand (0.25 s) + margin
	_check(e._freeze_count == 1, "repro: enemy claimed once (%d)" % e._freeze_count)
	_check(lob.freeze_count() == 1, "repro: lob claimed once (%d)" % lob.freeze_count())
	_check(rain.freeze_count() == 1, "repro: rain zone claimed once (%d)" % rain.freeze_count())
	var drops := _drops()
	drops.erase(lob)
	var all_one := true
	for d in drops:
		all_one = all_one and d.freeze_count() == 1
	_check(all_one, "repro: every existing rain drop claimed once (%d drops)" % drops.size())
	_check(lob._ball.process_mode == Node.PROCESS_MODE_DISABLED, "repro: lob sprite animation held")
	var pos := lob.global_position
	var t := lob._t
	var n_drops := rain.drops
	var r_el := rain._elapsed
	var drop_t: Array = []
	for d in drops:
		drop_t.append(d._t)
	await _frames(45)
	_check(lob.global_position.distance_to(pos) < 0.001, "repro: lob moved %.1f px in 45 frames (want 0)" % lob.global_position.distance_to(pos))
	_check(lob._t == t, "repro: lob flight clock held")
	_check(rain.drops == n_drops, "repro: rain drops held at %d (now %d)" % [n_drops, rain.drops])
	_check(rain._elapsed == r_el, "repro: rain clock held")
	var held := true
	for i in drops.size():
		held = held and is_instance_valid(drops[i]) and drops[i]._t == drop_t[i]
	_check(held, "repro: existing drops held mid-fall")
	_check(lob.freeze_count() == 1 and rain.freeze_count() == 1, "repro: per-frame claim requests never double the claim")
	_check(e.hp == hp0, "repro: no damage while frozen")
	await _wait_release(b)
	await _frames(1)
	_check(lob.freeze_count() == 0 and rain.freeze_count() == 0 and e._freeze_count == 0, "repro: all claims released to 0")
	var leaked := false
	for d in drops:
		if is_instance_valid(d) and d.freeze_count() != 0:
			leaked = true
	_check(not leaked, "repro: drop claims released to 0")
	_check(lob._ball.process_mode == Node.PROCESS_MODE_INHERIT, "repro: lob sprite animation resumed")
	await _frames(10)
	_check(is_instance_valid(lob) and (lob._landed or lob.global_position.distance_to(pos) > 1.0), "repro: lob resumes after release")
	_check(rain.drops > n_drops, "repro: rain resumes dropping (%d -> %d)" % [n_drops, rain.drops])
	await _wait(1.6)
	_check(not is_instance_valid(lob) or lob._landed, "repro: lob lands after release")
	_check(e.hp < hp0, "repro: enemy takes damage after release (%d -> %d)" % [hp0, e.hp])
	await _clear()

## Attacks spawned inside an already-expanded bubble are claimed on their
## first physics step, before moving.
func _check_spawned_inside() -> void:
	var b := _bubble(Vector2(600, 300), 300.0, 1.0)
	await _wait(0.4)
	var lob := WaterSplash.spawn(_area, _spell("water_splash"), _player, Vector2(500, 300), Vector2(700, 300), 70.0, 1.0)
	var rain := WaterRain.spawn(_area, _spell("heavy_rain"), _player, Vector2(650, 300))
	var drop := WaterSplash.spawn(_area, _spell("heavy_rain"), _player, Vector2(620, 320), Vector2(620, 320), 140.0, 0.3)
	await _frames(1)
	_check(lob.freeze_count() == 1, "inside: new lob claimed on first step")
	_check(rain.freeze_count() == 1, "inside: new rain zone claimed on first step")
	_check(drop.freeze_count() == 1, "inside: new drop claimed on first step")
	await _frames(20)
	_check(lob.global_position == Vector2(500, 300) and lob._t == 0.0, "inside: lob never moved")
	_check(rain.drops == 0 and rain._elapsed == 0.0, "inside: rain never ticked")
	_check(drop._t == 0.0 and not drop._landed, "inside: drop never fell")
	await _wait_release(b)
	await _frames(1)
	_check(lob.freeze_count() == 0 and rain.freeze_count() == 0 and drop.freeze_count() == 0, "inside: claims released")
	await _wait(0.4)
	_check(lob._t > 0.0 and rain.drops > 0 and (not is_instance_valid(drop) or drop._landed), "inside: all resume after release")
	await _clear()

## Overlapping bubbles: 2 claims, 1 after the first releases (still held),
## 0 after the second.
func _check_overlap() -> void:
	var b1 := _bubble(Vector2(600, 300), 300.0, 0.6)
	var b2 := _bubble(Vector2(620, 300), 300.0, 1.4)
	await _wait(0.35)
	var lob := WaterSplash.spawn(_area, _spell("water_splash"), _player, Vector2(550, 300), Vector2(700, 300), 70.0, 1.0)
	var rain := WaterRain.spawn(_area, _spell("heavy_rain"), _player, Vector2(600, 300))
	await _frames(2)
	_check(lob.freeze_count() == 2 and rain.freeze_count() == 2, "overlap: two bubbles hold two claims (%d, %d)" % [lob.freeze_count(), rain.freeze_count()])
	await _wait_release(b1)
	await _frames(3)
	_check(lob.freeze_count() == 1 and rain.freeze_count() == 1, "overlap: first release leaves one claim")
	var pos := lob.global_position
	await _frames(10)
	_check(lob.global_position == pos and rain.drops == 0, "overlap: still held by the second bubble")
	await _wait_release(b2)
	await _frames(3)
	_check(lob.freeze_count() == 0 and rain.freeze_count() == 0, "overlap: second release clears the claims")
	await _frames(10)
	_check(lob.global_position != pos and rain.drops > 0, "overlap: all resume")
	await _clear()

func _land_lob(spell: Spell, targets: Array) -> void:
	WaterSplash.spawn(_area, spell, _player, Vector2(400, 300), Vector2(600, 300), 70.0, 0.2)
	await _wait(0.4)

func _check_relics_splash() -> void:
	var splash := _spell("water_splash")
	var own_before := _player.damage_modifiers.items().size()
	# Matching relic, three enemies in the splash.
	_set_relic(SpellTags.AOE)
	var enemies := [_enemy(Vector2(600, 300)), _enemy(Vector2(620, 300)), _enemy(Vector2(600, 320))]
	var logs := []
	for e in enemies:
		logs.append(_record(e))
	await _land_lob(splash, enemies)
	var got := []
	for l in logs:
		got.append_array(l)
	_check(got == [32, 32, 32], "relic splash: matching AOE amp 1.0 -> %s (want [32, 32, 32])" % [got])
	# Repeated hits do not accumulate.
	await _land_lob(splash, enemies)
	got = []
	for l in logs:
		got.append_array(l)
	_check(got == [32, 32, 32, 32, 32, 32], "relic splash: repeated lobs stay 32 -> %s" % [got])
	_check(_player.damage_modifiers.items().size() == own_before, "relic splash: player's own modifier collection not mutated")
	await _clear()
	# Non-matching relic.
	_set_relic(SpellTags.MELEE)
	var e2 := _enemy(Vector2(600, 300))
	var l2 := _record(e2)
	await _land_lob(splash, [e2])
	_check(l2 == [16], "relic splash: non-matching relic -> %s (want [16])" % [l2])
	await _clear()
	# No provider.
	_set_relic(&"")
	var e3 := _enemy(Vector2(600, 300))
	var l3 := _record(e3)
	await _land_lob(splash, [e3])
	_check(l3 == [16], "relic splash: no relic provider -> %s (want [16])" % [l3])
	await _clear()
	# Matching relic + attacker crit x2 + receiver 50% reduction.
	_set_relic(SpellTags.AOE)
	var crit := DamageModifier.crit(1.0, 2.0)
	_player.damage_modifiers.add(crit)
	var e4 := _enemy(Vector2(600, 300))
	e4.damage_modifiers.add(DamageModifier.reduction(0.5))
	var l4 := _record(e4)
	await _land_lob(splash, [e4])
	_check(l4 == [32], "relic splash: relic + crit x2 + 50%% reduction -> %s (want [32])" % [l4])
	_player.damage_modifiers.remove(crit)
	_check(_player.damage_modifiers.items().size() == own_before, "relic splash: crit fixture removed cleanly")
	await _clear()

func _rain_damage(tag: StringName) -> Array:
	_set_relic(tag)
	var spell := _spell("heavy_rain").duplicate() as Spell
	spell.rain_radius = 0.0 # every drop on the enemy
	var e := _enemy(Vector2(600, 300))
	var l := _record(e)
	WaterRain.spawn(_area, spell, _player, Vector2(600, 300))
	await _wait(0.9)
	await _clear()
	return l

func _all_eq(a: Array, v: int) -> bool:
	if a.size() < 2:
		return false
	for x in a:
		if x != v:
			return false
	return true

func _check_relics_rain() -> void:
	var own_before := _player.damage_modifiers.items().size()
	var m := await _rain_damage(SpellTags.AOE)
	_check(_all_eq(m, 16), "relic rain: matching relic 16 per drop, no accumulation -> %s" % [m])
	var n := await _rain_damage(SpellTags.MELEE)
	_check(_all_eq(n, 8), "relic rain: non-matching relic 8 per drop -> %s" % [n])
	_check(_player.damage_modifiers.items().size() == own_before, "relic rain: player's modifier collection not mutated")

func _shield_damage(tag: StringName) -> Array:
	_set_relic(tag)
	var e := _enemy(_player.global_position + Vector2(30, 0))
	var l := _record(e)
	WaterShield.spawn(_player, _spell("water_bubble"))
	await _wait(1.2)
	await _clear()
	return l

func _check_relics_shield() -> void:
	var own_before := _player.damage_modifiers.items().size()
	var m := await _shield_damage(SpellTags.AOE)
	_check(_all_eq(m, 12), "relic shield: matching relic 12 per tick, no accumulation -> %s" % [m])
	var n := await _shield_damage(SpellTags.MELEE)
	_check(_all_eq(n, 6), "relic shield: non-matching relic 6 per tick -> %s" % [n])
	_check(_player.damage_modifiers.items().size() == own_before, "relic shield: player's modifier collection not mutated")
	_set_relic(&"")
