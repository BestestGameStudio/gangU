extends SceneTree
## RECORDING-ONLY gameplay driver for #443 (not a test, not loaded by the
## game). Replaces the synthetic record443_rock_throw.gd fixture as the
## review demo: boots production main.tscn, enters the production overworld
## and puts the hero inside the aggro radius of the real GuardsRed mustache
## men (production enemy.tscn running the branch cover AI + rock throw).
## Nothing about the enemies, rocks or terrain is scripted:
##   beat 1 - the guards hide behind the seeded overworld trees and throw
##            rocks that arc over the trees and hit the hero.
##   beat 2 - right after a rock is thrown, the hero casts the REAL Stone
##            Block spell (SpellCaster._cast_spell, aim_override) into its
##            path: the rock stops on the block and the block stays.
##   beat 3 - the overworld has no maze walls, so the recorder plants one
##            OBSTACLE cell (the maze-wall cell type, disclosed in the banner)
##            in a rock's path right after release: the rock stops on it.
## Driven by the script: the hero's aim (the guards hold while aimed at) and
## when the hero casts. A recording-only HP floor keeps the hero alive.
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 \
##     --path . --resolution 1920x1080 --write-movie /tmp/ci/443/f.png \
##     --fixed-fps 30 --script res://tools/showcase/record443_gameplay.gd

const FPS := 60.0 ## physics ticks per second (_wait counts physics frames)
const GUARD_POST := Vector2(822, 270) ## GuardsRed post (scenes/overworld.tscn)
## North of the seeded tree at (833,193), so it sits between the post and the hero.
const HERO_SPOT := Vector2(835, 62)
const STONE_BLOCK := preload("res://resources/spells/stone_block.tres")

var scene: Node
var p: Player
var caster: Node2D
var cam: Camera2D
var focus: Node2D
var terrain: TerrainMap
var frame := 0
var _beat := "setup"
var _beat_label: Label
var _stats_label: Label
var _seen_rocks := {}
var rocks_seen := 0
var rocks_hit := 0
var rocks_blocked := 0
var other_hits := 0 ## contact hits (not rocks)
var _hp_last := 0
var _new_rock: Projectile = null
var _block_cell: Variant = null
var _wall_cell: Variant = null
var _mob_labels := {}

func say(s: String) -> void:
	print("[443rec %5.2fs] %s" % [frame / FPS, s])

func _wait(sec: float) -> void:
	for i in int(sec * FPS):
		await physics_frame
		_tick()

func _guards() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in get_nodes_in_group(&"enemies"):
		if e is Enemy and is_instance_valid(e) and e.cover_seek and e.global_position.distance_to(GUARD_POST) < 320.0:
			out.append(e)
	return out

func _cov(e: Enemy) -> EnemyBehaviorCover:
	var beh = e.get("_behavior")
	return beh.get("_cover") if beh != null else null

func _flash(at: Vector2, color: Color) -> void:
	var l := Line2D.new()
	l.width = 3.0
	l.default_color = color
	l.z_index = 50
	for i in 17:
		var a := TAU * float(i) / 16.0
		l.add_point(at + Vector2(cos(a), sin(a)) * 14.0)
	scene.current_area.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)

func _tick() -> void:
	frame += 1
	# Track every lobbed rock in flight (production Projectiles).
	for n in get_nodes_in_group(&"projectiles"):
		var pr := n as Projectile
		if pr == null or not pr.lobbed or _seen_rocks.has(pr.get_instance_id()):
			continue
		_seen_rocks[pr.get_instance_id()] = true
		rocks_seen += 1
		_new_rock = pr
		pr.blocked.connect(func():
			rocks_blocked += 1
			_flash(pr.global_position, Color(1.0, 0.85, 0.2))
			say("rock BLOCKED at %s" % str(pr.global_position.round())))
	if p.hp < _hp_last:
		if _hp_last - p.hp == int(preload("res://resources/spells/mustache_rock.tres").damage):
			rocks_hit += 1
		else:
			other_hits += 1
		say("hero hit: hp %d -> %d" % [_hp_last, p.hp])
	# RECORDING-ONLY: keep the hero alive (a death would reload the run).
	if p.hp < 40:
		p.heal(60)
	_hp_last = p.hp
	var gs := _guards()
	if frame % 60 == 0:
		for g in gs:
			var cv := _cov(g)
			if cv != null:
				say("  guard %s at %s %s rocks=%d" % [g.name, str(g.global_position.round()), EnemyBehaviorCover.State.keys()[cv._state], cv.rocks_thrown])
	var c := p.global_position
	for g in gs:
		c += g.global_position
	focus.global_position = c / float(gs.size() + 1)
	if p.sprite != null:
		p.sprite.global_rotation = 0.0
	for g in gs:
		var cov := _cov(g)
		if cov == null:
			continue
		var key := g.get_instance_id()
		var lab: Label = _mob_labels.get(key)
		if lab == null:
			lab = Label.new()
			lab.add_theme_font_size_override("font_size", 12)
			lab.add_theme_color_override("font_color", Color(0.4, 1.0, 1.0))
			lab.add_theme_color_override("font_outline_color", Color.BLACK)
			lab.add_theme_constant_override("outline_size", 4)
			lab.z_index = 60
			scene.current_area.add_child(lab)
			_mob_labels[key] = lab
		lab.text = "%s  rocks %d" % [EnemyBehaviorCover.State.keys()[cov._state], cov.rocks_thrown]
		lab.global_position = g.global_position + Vector2(-34, -52)
	if _beat_label != null:
		_beat_label.text = "%s   t=%5.2fs" % [_beat, frame / FPS]
		var blk := "-"
		if _block_cell != null:
			blk = "intact" if terrain.tile_type_at_cell(_block_cell) == TerrainTypes.BLOCK else "DESTROYED"
		_stats_label.text = "rocks thrown %d | rocks hit hero %d | rocks stopped %d | contact hits %d | hero hp %d/%d | stone block: %s" % [
			rocks_seen, rocks_hit, rocks_blocked, other_hits, p.hp, p.max_hp, blk]

## Sweeps the aim across the guards (0.6s each), like a player panning the
## mouse over them, so none is left un-aimed-at long enough to CHARGE.
func _aim_at_guards() -> void:
	var gs := _guards()
	if gs.is_empty():
		return
	var g: Enemy = gs[int(frame / (0.6 * FPS)) % gs.size()]
	p.rotation = (g.global_position - p.global_position).angle()

## A point on the rock's remaining path, about halfway to the hero, so the
## new cell is ahead of the rock (not its current cell).
func _ahead_of(rock: Projectile) -> Vector2:
	var from := rock.global_position
	var dist := from.distance_to(p.global_position)
	var here := terrain.world_to_cell(from)
	# Skip cells under a tree canopy (those are low cover by design).
	for f in [0.55, 0.45, 0.65, 0.35, 0.75]:
		var at: Vector2 = from + rock.direction * maxf(dist * f, 40.0)
		var c := terrain.world_to_cell(at)
		if c != here and terrain.is_walkable_at(at) and not terrain.is_low_cover_cell(c):
			return at
	return from + rock.direction * maxf(dist * 0.55, 40.0)

## Waits (aiming at the guards) until a fresh rock has left a guard.
func _wait_for_throw(max_sec: float) -> Projectile:
	_new_rock = null
	for i in int(max_sec * FPS):
		_aim_at_guards()
		await physics_frame
		_tick()
		if _new_rock != null and is_instance_valid(_new_rock):
			return _new_rock
	return null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")
	p.set_process(false) # aim is driven here instead of the OS mouse
	caster = p.get_node("SpellCaster")
	cam = scene.get_node("FollowCamera")
	focus = Node2D.new()
	scene.add_child(focus)
	cam.target = focus
	cam.follow_speed = 3.5
	cam.zoom = Vector2(1.5, 1.5)
	await _wait(0.4)
	scene.enter_overworld()
	await _wait(0.8)
	terrain = scene.current_area.get_node_or_null("Terrain")
	var layer := CanvasLayer.new()
	layer.layer = 100
	scene.add_child(layer)
	for i in 3:
		var lab := Label.new()
		# Bottom-left, clear of the HUD (the canvas is stretched from the base size).
		lab.position = Vector2(10, root.get_visible_rect().size.y - 76 + 22 * i)
		lab.add_theme_font_size_override("font_size", 15)
		lab.add_theme_color_override("font_outline_color", Color.BLACK)
		lab.add_theme_constant_override("outline_size", 6)
		layer.add_child(lab)
		if i == 0:
			lab.text = "#443 GAMEPLAY: production overworld, real GuardsRed mustache men, seeded trees. Script-driven: hero aim + casts, HP floor"
		elif i == 1:
			_beat_label = lab
			lab.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
		else:
			_stats_label = lab
			lab.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
	p.global_position = HERO_SPOT # staging: walk-in skipped
	_hp_last = p.hp
	focus.global_position = p.global_position
	cam.global_position = p.global_position
	say("hero at %s; guards: %d" % [str(HERO_SPOT), _guards().size()])

	# --- Beat 1: guards hide behind the trees and lob rocks over them -------
	_beat = "beat 1: guards hide behind overworld trees -> rocks arc OVER the trees"
	for i in int(8.0 * FPS):
		_aim_at_guards()
		await physics_frame
		_tick()
	for g in _guards():
		var cov := _cov(g)
		say("guard %s state=%s rocks=%d cover=%s" % [g.name, EnemyBehaviorCover.State.keys()[cov._state], cov.rocks_thrown, str(cov.get("_cover_cell"))])

	# --- Beat 2: real Stone Block cast into a rock's path -------------------
	_beat = "beat 2: hero casts STONE BLOCK into a rock's path -> rock stops, block stays"
	var rock := await _wait_for_throw(6.0)
	if rock != null:
		var at := _ahead_of(rock)
		caster.aim_override = at
		caster._cast_spell(STONE_BLOCK)
		caster.aim_override = null
		_block_cell = terrain.world_to_cell(at)
		if terrain.tile_type_at_cell(_block_cell) != TerrainTypes.BLOCK:
			say("stone block refused at %s" % str(at))
			_block_cell = null
		else:
			say("stone block placed at cell %s" % str(_block_cell))
	for i in int(4.0 * FPS):
		_aim_at_guards()
		await physics_frame
		_tick()
	if _block_cell != null:
		say("stone block after beat 2: %s" % terrain.tile_type_at_cell(_block_cell))

	# --- Beat 3: a maze-wall (OBSTACLE) cell planted in a rock's path -------
	_beat = "beat 3: recorder plants an OBSTACLE (maze-wall type) cell in a rock's path -> rock stops"
	var blk_cell = _block_cell # the stone block stays; the label keeps reporting it
	rock = await _wait_for_throw(6.0)
	if rock != null:
		var at2 := _ahead_of(rock)
		_wall_cell = terrain.world_to_cell(at2)
		terrain.set_cell(_wall_cell, TerrainTypes.OBSTACLE)
		var sq := Polygon2D.new()
		var ctr := terrain.cell_to_world(_wall_cell)
		var h := float(terrain.cell_size) * 0.5
		sq.polygon = PackedVector2Array([ctr + Vector2(-h, -h), ctr + Vector2(h, -h), ctr + Vector2(h, h), ctr + Vector2(-h, h)])
		sq.color = Color(0.5, 0.48, 0.45, 0.95)
		sq.z_index = 49
		scene.current_area.add_child(sq)
		say("wall planted at cell %s" % str(_wall_cell))
	for i in int(4.0 * FPS):
		_aim_at_guards()
		await physics_frame
		_tick()
	say("done: rocks %d hit %d blocked %d (prev block cell %s)" % [rocks_seen, rocks_hit, rocks_blocked, str(blk_cell)])
	quit()
