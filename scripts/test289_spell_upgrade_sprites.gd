extends SceneTree
## #289 harness: the supplied spell + upgrade sheet (spell_upgrades_frames.tres).
## Every spell and upgrade result flies its own row (a one-shot "_start" spawn-in
## then the looping flight), the sheet cells are transparent art, unmapped enemy
## spells stay code-drawn, and hitboxes stay on spell.radius. Summon Ally plays
## the one-shot circle on a successful cast only. Run headless:
##   godot --headless --path . --script res://scripts/test289_spell_upgrade_sprites.gd

const CombatEffects = preload("res://scripts/combat_effects.gd")
const CELL_W := 64
const CELL_H := 72
## Spell resource -> (sheet row, animation stem, expected art hue family).
const SPELLS := {
	"fire_ball": [0, &"fire_ball", "warm"],
	"fire_ball_split": [1, &"fire_ball_split", "warm"],
	"fire_ball_split_heavy": [2, &"fire_ball_split_heavy", "warm"],
	"fire_ball_split_wide": [3, &"fire_ball_split_wide", "warm"],
	"fire_ball_beam": [4, &"fire_ball_beam", "warm"],
	"fire_ball_beam_heavy": [5, &"fire_ball_beam_heavy", "warm"],
	"fire_ball_beam_homing": [6, &"fire_ball_beam_homing", "warm"],
	"fire_ball_beam_long": [7, &"fire_ball_beam_long", "warm"],
	"fire_ball_beam_piercing": [8, &"fire_ball_beam_piercing", "warm"],
	"mana_shot": [9, &"mana_shot", "cool"],
	"mana_shot_volley": [10, &"mana_volley", "cool"],
	"mana_shot_lance": [11, &"mana_lance", "cool"],
	"placeholder_bolt": [12, &"placeholder_bolt", "warm"],
}

var _checks := 0
var _failures := 0

func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if ok:
		print("PASS: %s" % msg)
	else:
		_failures += 1
		print("FAIL: %s" % msg)

func _spawn(spell_path: String) -> Projectile:
	var p: Projectile = load("res://scenes/projectile.tscn").instantiate()
	p.setup(load(spell_path), Vector2.RIGHT, null)
	root.add_child(p)
	return p

func _frame_region(frames: SpriteFrames, anim: StringName, idx: int) -> Rect2:
	return (frames.get_frame_texture(anim, idx) as AtlasTexture).region

func _check_animations(frames: SpriteFrames, image: Image) -> void:
	for key in SPELLS:
		var row: int = SPELLS[key][0]
		var stem: StringName = SPELLS[key][1]
		var start := StringName("%s_start" % stem)
		_check(frames.has_animation(start) and frames.has_animation(stem), "%s has start + flight animations" % stem)
		if not (frames.has_animation(start) and frames.has_animation(stem)):
			continue
		_check(frames.get_frame_count(start) == 3 and not frames.get_animation_loop(start), "%s start: 3 frames, one-shot" % stem)
		_check(frames.get_frame_count(stem) == 4 and frames.get_animation_loop(stem), "%s flight: 4 frames, loops" % stem)
		_check(_frame_region(frames, start, 0) == Rect2(0, row * CELL_H, CELL_W, CELL_H), "%s start reads sheet row %d col 0" % [stem, row])
		_check(_frame_region(frames, stem, 0) == Rect2(3 * CELL_W, row * CELL_H, CELL_W, CELL_H), "%s flight reads sheet row %d col 3" % [stem, row])
		_check_art(image, row, stem, SPELLS[key][2])
	var summon := &"summon_ally"
	_check(frames.has_animation(summon), "summon_ally animation exists")
	if frames.has_animation(summon):
		_check(frames.get_frame_count(summon) == 6 and not frames.get_animation_loop(summon), "summon_ally: 6 frames, one-shot")
		_check(_frame_region(frames, summon, 5) == Rect2(5 * CELL_W, 13 * CELL_H, CELL_W, CELL_H), "summon_ally final frame is sheet row 13 col 5")

## The flight frame must have soft art inside and a clean transparent edge (no
## grid line or neighbouring-cell bleed).
func _check_art(image: Image, row: int, stem: StringName, hue: String) -> void:
	var cell := Rect2i(4 * CELL_W, row * CELL_H, CELL_W, CELL_H)
	var warm := 0
	var cool := 0
	var solid := 0
	for y in range(cell.position.y, cell.end.y):
		for x in range(cell.position.x, cell.end.x):
			var px := image.get_pixel(x, y)
			if px.a < 0.5:
				continue
			solid += 1
			if px.r > px.b + 0.1:
				warm += 1
			elif px.b > px.r + 0.1:
				cool += 1
	_check(solid > 40, "%s flight cell has art (%d solid px)" % [stem, solid])
	_check((warm > cool) if hue == "warm" else (cool > warm), "%s art reads %s" % [stem, hue])
	var edge_alpha := 0.0
	for x in range(cell.position.x, cell.end.x):
		edge_alpha = maxf(edge_alpha, image.get_pixel(x, cell.position.y).a)
		edge_alpha = maxf(edge_alpha, image.get_pixel(x, cell.end.y - 1).a)
	_check(edge_alpha < 0.05, "%s cell top/bottom edge is transparent" % stem)

func _initialize() -> void:
	print("test289: spell + upgrade sprites (#289)")
	var frames: SpriteFrames = load("res://resources/sprites/spell_upgrades_frames.tres")
	_check(frames != null, "spell_upgrades_frames.tres loads")
	var image: Image = (load("res://assets/sprites/spell_upgrades.png") as Texture2D).get_image()
	_check(image.get_width() == 6 * CELL_W and image.get_height() == 14 * CELL_H, "sheet is 6x14 cells")
	if image.is_compressed():
		image.decompress()
	_check_animations(frames, image)

	# Warm up: the first node added to the root readies only once the tree settles.
	var warmup := _spawn("res://resources/spells/fire_ball.tres")
	await process_frame
	warmup.queue_free()

	# Every sheet spell flies its own row at runtime.
	for key in SPELLS:
		var stem: StringName = SPELLS[key][1]
		var p := _spawn("res://resources/spells/%s.tres" % key)
		var sprite := p.get_node_or_null("Sprite") as AnimatedSprite2D
		_check(sprite != null, "%s has a Sprite" % key)
		if sprite == null:
			p.queue_free()
			continue
		_check(sprite.animation == StringName("%s_start" % stem) and sprite.is_playing(), "%s starts on %s_start" % [key, stem])
		_check(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "%s uses nearest filter" % key)
		var want_scale := clampf(p.spell.radius / Projectile.SPRITE_RADIUS_DIVISOR, Projectile.SPRITE_SCALE_MIN, Projectile.SPRITE_SCALE_MAX)
		_check(is_equal_approx(sprite.scale.x, want_scale) and is_equal_approx(sprite.scale.y, want_scale), "%s sprite scale follows radius, clamped" % key)
		sprite.animation_finished.emit()
		_check(sprite.animation == stem and sprite.is_playing(), "%s moves on to looping %s" % [key, stem])
		_check(not p.get_node("Dart").visible and not p.get_node("Visual").visible, "%s hides code-drawn visuals" % key)
		var shape := p.get_node("CollisionShape2D").shape as CircleShape2D
		_check(is_equal_approx(shape.radius, p.spell.radius), "%s collision radius is still spell.radius" % key)
		p.queue_free()

	# Every upgrade's result spell is on the sheet.
	var dir := DirAccess.open("res://resources/upgrades")
	for f in dir.get_files():
		var path := f.trim_suffix(".remap")
		if not path.ends_with(".tres"):
			continue
		var up: Resource = load("res://resources/upgrades/" + path)
		var result: Spell = up.get(&"result_spell")
		_check(result != null and Projectile.SPELL_SPRITE_ANIMS.has(result.spell_name), "upgrade %s maps to a sheet animation" % path)
		if result != null:
			_check(result.glow and result.trail_length > 0, "upgrade %s result has a glow and trail" % path)
			_check(result.glow_tint.a > 0.0, "upgrade %s result sets an art-matched glow tint" % path)
			_check_upgrade_effects(result, path)

	# Off-sheet enemy spells keep their code-drawn visuals.
	for key in ["warlord_orb", "head_bolt"]:
		var off := _spawn("res://resources/spells/%s.tres" % key)
		_check(off.get_node_or_null("Sprite") == null and off.get_node("Dart").visible, "%s stays code-drawn" % key)
		off.queue_free()

	# Mana Shot's halo matches its cyan art; the muzzle colour stays purple.
	var mana: Spell = load("res://resources/spells/mana_shot.tres")
	_check(mana.glow_tint.b > mana.glow_tint.r and mana.glow_tint.a > 0.0, "Mana Shot glow tint is cyan-blue")
	_check(mana.projectile_color == Color(0.6, 0.45, 1, 1), "Mana Shot projectile_color is unchanged")

	await _check_summon()

	print("test289 done: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

## The upgrade's halo and trail spawn in its art tint, and visual_scale leaves
## the sprite and hit radius alone.
func _check_upgrade_effects(result: Spell, path: String) -> void:
	var p: Projectile = load("res://scenes/projectile.tscn").instantiate()
	p.setup(result, Vector2.RIGHT, null)
	root.add_child(p)
	var glow := p.get_node_or_null("Glow") as Polygon2D
	var trail := p.get_node_or_null("Trail") as Line2D
	_check(glow != null and trail != null, "%s spawns Glow and Trail" % path)
	if trail != null:
		var head_alpha := trail.gradient.get_color(trail.gradient.get_point_count() - 1).a
		_check(is_zero_approx(head_alpha) if result.trail_head_fade > 0.0 else is_equal_approx(head_alpha, 0.7),
			"%s trail head end matches trail_head_fade" % path)
	if glow != null:
		var c := glow.vertex_colors[0]
		_check(is_equal_approx(c.r, result.glow_tint.r) and is_equal_approx(c.g, result.glow_tint.g) and is_equal_approx(c.b, result.glow_tint.b), "%s halo uses glow_tint" % path)
	var sprite := p.get_node("Sprite") as AnimatedSprite2D
	var want := clampf(result.radius / Projectile.SPRITE_RADIUS_DIVISOR, Projectile.SPRITE_SCALE_MIN, Projectile.SPRITE_SCALE_MAX)
	_check(is_equal_approx(sprite.scale.x, want), "%s visual_scale does not change the sprite size" % path)
	_check(is_equal_approx((p.get_node("CollisionShape2D").shape as CircleShape2D).radius, result.radius), "%s hit radius unchanged" % path)
	p.queue_free()

func _circles(parent: Node) -> Array:
	return parent.get_children().filter(func(c): return c is AnimatedSprite2D and c.is_in_group(&"combat_fx"))

func _check_summon() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var p: Player = load("res://scenes/player.tscn").instantiate()
	stage.add_child(p)
	var manager := SummonManager.new()
	manager.caster_path = NodePath("../Player/SpellCaster")
	stage.add_child(manager)
	await process_frame
	var spell: Spell = load("res://resources/spells/summon_ally.tres")
	manager._on_spell_cast(spell)
	await process_frame
	_check(manager.live_count() == 1, "summon cast spawns the ally")
	var circles := _circles(stage)
	_check(circles.size() == 1, "summon cast plays one circle")
	if circles.size() == 1:
		var fx: AnimatedSprite2D = circles[0]
		_check(fx.animation == CombatEffects.SUMMON_ANIM and fx.is_playing(), "circle plays summon_ally")
		_check(fx.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "circle uses nearest filter")
		fx.animation_finished.emit()
		await process_frame
		_check(_circles(stage).is_empty(), "circle frees itself when finished")
	manager.base_cap = 1
	manager._on_spell_cast(spell)
	await process_frame
	_check(manager.live_count() == 1 and _circles(stage).is_empty(), "refused cast (at cap) shows no circle")
