extends SceneTree
## RECORDING-ONLY showcase driver for #433 (not a test, not loaded by the
## game). Boots main.tscn, jumps into the production overworld and stages the
## projectile-vs-terrain fix with PRODUCTION scenes/scripts: a wall of plain
## OBSTACLE cells is planted through the production TerrainMap (same call the
## generator uses), a production Enemy fires REAL head-bolt Projectiles at
## the hero, and the hero answers with real SpellCaster casts.
##
## STAGED, LABELED: the wall is planted by the recorder (banner says so), the
## enemy's aim/volleys and the hero's aim are script-driven, and a
## recording-only HP floor keeps the hero alive. Movement, terrain, spells
## and projectiles are untouched production code.
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 \
##     --path . --resolution 1920x1080 --write-movie /tmp/ci/433/demo.avi \
##     --fixed-fps 60 --script res://tools/showcase/record433_terrain_blocks.gd

const FPS := 60.0
## head bolt: the crimson enemy bolt the Head boss screams (production spell).
const ENEMY_SPELL := "res://resources/spells/head_bolt.tres"

var scene: Node
var p: Player
var caster: Node2D
var cam: Camera2D
var focus: Node2D
var enemy: Enemy
var terrain: TerrainMap
var frame := 0
var wall_cells: Array[Vector2i] = []
var _wall_marks: Array[Node] = [] ## recording-only wall overlay art
var _beat_label: Label
var _beat := "setup"

func say(s: String) -> void:
	print("[rec %5.2fs] %s" % [frame / FPS, s])

func _wait(sec: float) -> void:
	for i in int(sec * FPS):
		await physics_frame
		_tick()

## Real production projectile, enemy-sourced, aimed at the hero.
func _enemy_shot() -> void:
	var spell: Spell = load(ENEMY_SPELL)
	var pr: Projectile = load("res://scenes/projectile.tscn").instantiate()
	var dir: Vector2 = enemy.global_position.direction_to(p.global_position)
	pr.setup(spell, dir, enemy)
	scene.current_area.add_child(pr)
	pr.global_position = enemy.global_position + dir * 30.0
	pr.blocked.connect(func(): _flash(pr.global_position))

## A small recording-only impact ring where a shot dies on the wall.
func _flash(at: Vector2) -> void:
	var l := Line2D.new()
	l.width = 3.0
	l.default_color = Color(1.0, 0.9, 0.3, 0.9)
	l.z_index = 50
	for i in 17:
		var a := TAU * float(i) / 16.0
		l.add_point(at + Vector2(cos(a), sin(a)) * 14.0)
	scene.current_area.add_child(l)
	var tween := l.create_tween()
	tween.tween_property(l, "modulate:a", 0.0, 0.6)
	tween.tween_callback(l.queue_free)

func _hero_cast() -> void:
	var spell: Spell = caster.equipped_spell
	if spell == null:
		return
	var dir: Vector2 = caster.global_position.direction_to(enemy.global_position)
	for d in SpellFanout.directions(dir, spell.projectile_count, spell.spread_degrees):
		var pr: Projectile = caster.projectile_scene.instantiate()
		pr.setup(spell, d, p)
		scene.current_area.add_child(pr)
		pr.global_position = caster.global_position
		pr.blocked.connect(func(): _flash(pr.global_position))
	preload("res://scripts/combat_effects.gd").muzzle(scene.current_area, caster.global_position, dir.angle(), spell.projectile_color)

func _plant_wall() -> void:
	# 5-cell OBSTACLE wall one row of cells north of the hero (planted via
	# the production TerrainMap; disclosed in the banner). The recorder
	# draws filled squares over the cells: the overworld's tree canopies
	# can occlude the debug tile art, so the overlay keeps the wall
	# readable on video. The blocking itself is the production TerrainMap.
	var hero_cell := terrain.world_to_cell(p.global_position)
	for dx in range(-2, 3):
		var c := hero_cell + Vector2i(dx, -3)
		wall_cells.append(c)
		terrain.set_cell(c, TerrainTypes.OBSTACLE)
		var sq := Polygon2D.new()
		var ctr := terrain.cell_to_world(c)
		var h := float(terrain.cell_size) * 0.5
		sq.polygon = PackedVector2Array([ctr + Vector2(-h, -h), ctr + Vector2(h, -h), ctr + Vector2(h, h), ctr + Vector2(-h, h)])
		sq.color = Color(0.75, 0.4, 0.2, 0.85)
		sq.z_index = 49
		scene.current_area.add_child(sq)
		_wall_marks.append(sq)

func _clear_wall() -> void:
	for c in wall_cells:
		terrain.set_cell(c, TerrainTypes.GROUND)
	for m in _wall_marks:
		m.queue_free()
	_wall_marks.clear()

func _ring(center: Vector2, radius: float, color: Color) -> void:
	var l := Line2D.new()
	l.width = 3.0
	l.default_color = color
	l.z_index = 50
	for i in 25:
		var a := TAU * float(i) / 24.0
		l.add_point(center + Vector2(cos(a), sin(a)) * radius)
	scene.current_area.add_child(l)

func _screen_label(text: String, pos: Vector2, size: int, color: Color, layer: CanvasLayer) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.position = pos
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", color)
	layer.add_child(lab)
	return lab

func _world_label(text: String, pos: Vector2, color: Color) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", 14)
	lab.add_theme_color_override("font_color", color)
	lab.z_index = 60
	scene.current_area.add_child(lab)
	lab.global_position = pos
	return lab

func _set_beat(b: String) -> void:
	_beat = b
	say(b)

func _tick() -> void:
	frame += 1
	# RECORDING-ONLY: keep the hero alive (a death would reload the run).
	if p.hp < 40:
		p.heal(60)
	focus.global_position = p.global_position.lerp(enemy.global_position, 0.4) if is_instance_valid(enemy) else p.global_position
	if _beat_label != null:
		_beat_label.text = "%s | t=%5.2fs" % [_beat, frame / FPS]

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")
	p.set_process(false) # recording drives placement, not OS input
	caster = p.get_node("SpellCaster")
	cam = scene.get_node("FollowCamera")
	focus = Node2D.new()
	scene.add_child(focus)
	cam.target = focus
	cam.follow_speed = 3.5
	cam.zoom = Vector2(0.85, 0.85) # frame the enemy, the wall and the hero
	say("hub booted")
	await _wait(0.3)
	if not scene.has_method("enter_overworld"):
		push_error("record433: main scene has no enter_overworld()")
		quit(1)
		return
	scene.enter_overworld()
	await _wait(1.0) # settle at the overworld spawn
	terrain = scene.current_area.get_node_or_null("Terrain")
	if terrain == null:
		push_error("record433: overworld has no Terrain node")
		quit(1)
		return

	# A production enemy across the wall (aim/volleys driven by this script).
	enemy = load("res://scenes/enemy.tscn").instantiate()
	scene.current_area.add_child(enemy)
	enemy.terrain = terrain
	enemy.set_physics_process(false)
	enemy.global_position = p.global_position + Vector2(0, -64.0 * 4.6)
	enemy.max_hp = 100000
	enemy.hp = 100000
	_world_label("enemy shooter (script-driven)", enemy.global_position + Vector2(-110, -40), Color(1.0, 0.4, 0.4))
	_plant_wall()
	_world_label("planted OBSTACLE wall (recorder)", p.global_position + Vector2(-190, -64.0 * 3.0 - 34.0), Color(1.0, 0.45, 0.2))
	var layer := CanvasLayer.new()
	layer.layer = 100
	scene.add_child(layer)
	_screen_label("STAGED #433 DEMO - OBSTACLE wall planted by recorder - script-driven aim - HP floor on", Vector2(8, 32), 14, Color(1, 1, 1), layer)
	_beat_label = _screen_label("", Vector2(8, 56), 14, Color(0.5, 1.0, 0.5), layer)
	focus.global_position = p.global_position
	cam.global_position = p.global_position

	# --- Beat 1: enemy volleys die on the wall face ------------------------
	_set_beat("beat1: enemy shots vs wall (BLOCKED)")
	for i in 4:
		_enemy_shot()
		await _wait(0.7)

	# --- Beat 2: the hero's own cast is blocked too (symmetric) ------------
	_set_beat("beat2: hero cast vs wall (BLOCKED)")
	for i in 2:
		_hero_cast()
		await _wait(0.7)

	# --- Beat 3: wall removed - the same enemy shot lands ------------------
	_set_beat("beat3: wall cleared -> enemy shot reaches the hero")
	_clear_wall()
	await _wait(0.3)
	var hp0 := p.hp
	_enemy_shot()
	await _wait(1.8) # head bolt: 270 px/s over ~414 px needs ~1.55s
	say("hero hp after clear-wall shot: %d -> %d" % [hp0, p.hp])
	await _wait(0.5)
	say("done")
	quit()
