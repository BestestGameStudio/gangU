class_name Summon
extends CharacterBody2D
## #209: player summon entity (foundation). A damageable ally with the same
## documented contract as Enemy: died(), health_changed() and a single
## apply_damage() entry point that clamps HP and emits only from inside, so
## summon HP can never change silently.
## #212: optional behavior slot (definition.behavior, enemy.gd idiom). With a
## behavior assigned, the summon moves/fights via _physics_process delegation;
## with none it stays intentionally inert (the #209 foundation default).

signal died()
signal health_changed(current: int, max_hp: int)

var max_hp: int = 30
var hp: int
## DamageCalc receiver seam: enemy contact damage on a summon computes
## through the one standard damage path, same as the player.
var damage_modifiers := DamageModifiers.new()
var definition: SummonDefinition
## #212: the player this summon guards. Wired by SummonManager BEFORE
## add_child (player_path idiom); null in harnesses - behaviors tolerate it.
var player: Node2D = null
## #281: the area's terrain grid for pathfinding, wired by SummonManager
## BEFORE add_child (main.gd's player.terrain lookup idiom); null in
## harnesses without a Terrain node - behaviors then move exactly as #280.
var terrain: TerrainMap = null
## #212: per-entity damage rolls for behavior attacks, same idiom as Enemy.
var damage_rng := RandomNumberGenerator.new()

var _behavior = null

func setup(def: SummonDefinition) -> void:
	definition = def
	if definition != null:
		max_hp = definition.max_hp

func _ready() -> void:
	hp = max_hp
	add_to_group("summons")
	# #279: summons never physically block or push players or enemies, and
	# vice versa (ignore_pair excepts BOTH directions of the solver).
	# Deferred so same-frame actors have registered their groups; covers the
	# production spawn orders (persistent main.tscn $Player first, enemies
	# on either side of casts - enemy.gd pairs late spawns). A Player
	# entering the tree AFTER a summon exists is NOT covered; there is no
	# such production route (revive heals in place). Contact damage is
	# distance-based and projectiles are Area sweeps: both untouched.
	# Immediate pass for actors already in the tree (a deferred-only wiring
	# leaves one physics tick of solver push when a cast lands ON a body:
	# measured 22.7px on the player); deferred pass for same-frame spawns.
	ActorCollision.ignore_group(self, ActorCollision.PLAYER_GROUP)
	ActorCollision.ignore_group(self, ActorCollision.ENEMY_GROUP)
	ActorCollision.ignore_group.call_deferred(self, ActorCollision.PLAYER_GROUP)
	ActorCollision.ignore_group.call_deferred(self, ActorCollision.ENEMY_GROUP)
	damage_rng.randomize()
	# #212: each Summon instantiates its OWN behavior instance, so per-summon
	# state (contact cooldown) is never shared across summons.
	if definition != null and definition.behavior != null:
		_behavior = definition.behavior.new()

## #301: unpair on exit - a freed body otherwise leaves a stale entry in
## peers' collision exception lists, and the engine logs
## "Parameter \"body\" is null" the next time a peer reads its list.
func _exit_tree() -> void:
	for e in get_collision_exceptions():
		if is_instance_valid(e):
			e.remove_collision_exception_with(self)

func _physics_process(delta: float) -> void:
	if _behavior != null and hp > 0:
		_behavior.physics_step(self, player, delta)

func apply_damage(amount: int) -> void:
	if hp <= 0:
		return
	hp = clampi(hp - amount, 0, max_hp)
	health_changed.emit(hp, max_hp)
	if hp == 0:
		died.emit()
		queue_free()

## #256: friendly fire off - source-aware entry point used by the #248
## projectile dispatch (apply_damage kept unchanged for every other caller).
## A projectile from the player side never damages this summon: any actual
## Player source is player-side regardless of identity (production boundary:
## a single Player lives in main.tscn), and a Summon source is player-side
## only when it shares this summon's owner. The caller must be an actual
## Projectile before its source is trusted; enemy, null, unknown, and
## non-Projectile callers - and any ownerless summon target, which has no
## side to protect - fall through to the legacy damage path unchanged.
func apply_damage_from(amount: int, projectile: Node2D) -> void:
	if is_instance_valid(player) and player is Player and projectile is Projectile:
		var src: Node2D = projectile.source
		if is_instance_valid(src) and (src is Player or (src is Summon and src.player == player)):
			return
	apply_damage(amount)

## #245: local cosmetic halo only. An explicit Player owner is required:
## unowned fixtures or future non-player summons must not inherit this effect.
## Drawn on the root, behind the unchanged Body child, without environment bloom.
const GLOW_BLUE := Color(0.16, 0.48, 1.0)
const GLOW_PERIOD := 2.4
var _glow_time := 0.0

func _has_player_glow() -> bool:
	return is_instance_valid(player) and player is Player

func _glow_strength() -> float:
	return 0.88 + 0.12 * sin(_glow_time * TAU / GLOW_PERIOD)

func _process(delta: float) -> void:
	_glow_time = fmod(_glow_time + delta, GLOW_PERIOD)
	# Also redraw after ownership is lost, so no stale halo survives a freed owner.
	queue_redraw()

func _draw() -> void:
	if not _has_player_glow():
		return
	var strength := _glow_strength()
	# Low-alpha nested discs form a soft falloff around the 20px placeholder.
	for layer in range(5):
		var radius := 22.0 - layer * 2.0
		var tint := GLOW_BLUE
		tint.a = (0.018 + layer * 0.010) * strength
		draw_circle(Vector2.ZERO, radius, tint, true, -1.0, true)
