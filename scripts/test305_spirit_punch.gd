extends SceneTree
## #305 harness: Spirit Punch base spell (PR-A, data-only).
## Contract under test: the spell is a CLOSE-RANGE, HEAVY single hit that
## emerges from the player - a very short-range, fast, large projectile
## carrying the roster's heaviest single-hit damage, tagged melee (metadata
## only, #66 vocabulary), one punch per cast, one cooldown per cast.
## Run headless:
##   godot --headless --script scripts/test305_spirit_punch.gd

const SPELL_PATH := "res://resources/spells/spirit_punch.tres"

var _area: Node2D
var _player: Node2D
var _caster: SpellCaster
var _spell: Spell
var _checks := 0
var _failures := 0
var _casts: Array = []

func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if ok:
		print("PASS: %s" % msg)
	else:
		_failures += 1
		print("FAIL: %s" % msg)

func _make_enemy(at: Vector2, hp: int) -> Enemy:
	var e: Enemy = load("res://scenes/enemy.tscn").instantiate()
	e.max_hp = hp
	e.speed = 0.0 # stationary target: range assertions stay exact
	e.position = at
	_area.add_child(e)
	return e

func _projectile_count() -> int:
	var n := 0
	for c in _area.get_children():
		if c is Projectile:
			n += 1
	return n

func _initialize() -> void:
	print("test305: Spirit Punch base spell (#305)")
	_area = Node2D.new()
	get_root().add_child(_area)
	current_scene = _area
	_player = load("res://scenes/player.tscn").instantiate()
	_player.position = Vector2(400, 300)
	_area.add_child(_player)
	_caster = _player.get_node("SpellCaster")
	_caster.spell_cast.connect(func(s: Spell) -> void: _casts.append(s))

	# --- resource contract ------------------------------------------------
	_spell = load(SPELL_PATH)
	_check(_spell != null, "spirit_punch.tres loads")
	if _spell == null:
		quit(1)
		return
	_check(_spell.spell_name == "Spirit Punch", "spell is named Spirit Punch")
	_check(SpellTags.unknown_tags(_spell.tags).is_empty(), "every tag is in the #66 vocabulary")
	_check(_spell.tags.has(SpellTags.MELEE), "tagged melee")
	_check(not _spell.tags.has(SpellTags.PROJECTILE), "not tagged projectile (buff-match seam stays honest)")
	var heavy: Spell = load("res://resources/spells/bolt_heavy.tres")
	_check(_spell.damage > heavy.damage, "heavier than Heavy Bolt (%.0f > %.0f): the roster's hardest single hit" % [_spell.damage, heavy.damage])
	_check(_spell.range <= 120.0, "close range (%.0f px, enemy contact range is 40)" % _spell.range)
	var mana: Spell = load("res://resources/spells/mana_shot.tres")
	_check(_spell.range < mana.range / 4.0, "far shorter reach than Mana Shot (%.0f vs %.0f)" % [_spell.range, mana.range])
	_check(_spell.projectile_count == 1 and _spell.spread_degrees == 0.0, "one punch per cast")
	_check(_spell.cooldown > 0.0 and _spell.cooldown <= heavy.cooldown, "cooldown within roster bounds (%.2f)" % _spell.cooldown)

	# --- cast path: one punch, one cooldown, emerges from the player ------
	_caster.add_spell(_spell)
	# Aim where the caster aims (mouse), so the direction matches by construction.
	await physics_frame
	var aim := _caster.global_position.direction_to(_caster.get_global_mouse_position())
	if aim.length_squared() == 0.0:
		aim = Vector2.RIGHT
	var near := _make_enemy(_caster.global_position + aim * 60.0, 100) # inside 90px reach
	var far := _make_enemy(_caster.global_position + aim * 400.0, 100) # well outside
	await physics_frame
	_caster.cast()
	await physics_frame
	_check(_casts.size() == 1 and _casts[0] == _spell, "spell_cast emitted once for Spirit Punch")
	_check(_projectile_count() == 1, "exactly one punch projectile spawned")
	_check(_caster.cooldown_remaining(_spell) > 0.0, "cooldown started (%.2fs left)" % _caster.cooldown_remaining(_spell))

	# --- resolution: the close target takes the heavy hit, the far one does not
	for i in 30: # 0.5s at 60fps: 90px at 900px/s needs ~6 frames
		await physics_frame
	_check(near.hp < near.max_hp, "close enemy took the hit (hp %d/%d)" % [near.hp, near.max_hp])
	_check(near.max_hp - near.hp >= int(_spell.damage), "hit lands at full heavy damage (>= %.0f)" % _spell.damage)
	_check(far.hp == far.max_hp, "far enemy untouched (punch dies at range)")
	_check(_projectile_count() == 0, "punch projectile despawned")

	# --- #289 sprite wiring: the punch flies the opaque-fist art ------------
	var frames: SpriteFrames = load("res://resources/sprites/spell_upgrades_frames.tres")
	_check(frames != null and frames.has_animation(&"spirit_punch") and frames.has_animation(&"spirit_punch_start"),
		"sheet has spirit_punch_start + spirit_punch anims")
	_check(Projectile.SPELL_SPRITE_ANIMS.get("Spirit Punch") == &"spirit_punch", "SPELL_SPRITE_ANIMS maps Spirit Punch")
	var p: Projectile = load("res://scenes/projectile.tscn").instantiate()
	p.setup(_spell, Vector2.RIGHT, null)
	_area.add_child(p)
	await process_frame
	var sprite := p.get_node_or_null("Sprite") as AnimatedSprite2D
	_check(sprite != null, "punch projectile carries the Sprite child")
	if sprite != null:
		_check(sprite.animation == &"spirit_punch_start" and sprite.is_playing(), "plays spirit_punch_start on spawn")
	var shape := p.get_node("CollisionShape2D").shape as CircleShape2D
	_check(is_equal_approx(shape.radius, _spell.radius), "sprite swap leaves hit radius at spell.radius")
	p.queue_free()

	print("test305: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _physics_process(_dt: float) -> bool:
	return false
