extends SceneTree
## RECORDING-ONLY showcase driver for #406 (not a test, not loaded by the
## game). Boots main.tscn, jumps into the overworld and stages the Mustache
## Warrior cover behavior with the PRODUCTION scenes/scripts: the hero is
## placed south of the red dungeon guard post and the script drives only his
## aim direction (the same global_rotation contract the player script writes
## from the mouse) plus a recording-only HP floor. The guards themselves are
## untouched production enemies running the branch cover behavior.
##
## STAGED, LABELED: unless G406_PLANT=0, the recorder plants cover cells via
## the production TerrainMap (1 OBSTACLE non-tree + 2 destroyable TREE)
## between the post and the hero, and draws RECORDING-ONLY overlays (cover
## markers, aim arrow, per-mob state, aim-flip timer) so the video is
## reviewable. With G406_PLANT=0 + G406_SHORT=1 it records the unmodified
## seeded forest (the rejection-reason fixture).
## Usage:
##   xvfb-run -a godot --path . --write-movie out.avi --fixed-fps 60 \
##         --rendering-driver opengl3 --script res://tools/showcase/record406_cover.gd

const FPS := 60.0
## GuardsRed post from scenes/overworld.tscn (guard at (822,270)).
const GUARD_POST := Vector2(822, 270)
## Hero stands 190px south of the post (inside the 220px aggro radius).
const HERO_SPOT := Vector2(822, 460)
## [world_pos, TerrainTypes kind, label, color]
const PLANTED := [
	[Vector2(855, 340), TerrainTypes.OBSTACLE, "OBSTACLE cover (non-tree)", Color(1.0, 0.45, 0.2)],
	[Vector2(790, 345), TerrainTypes.TREE, "TREE cover (destroyable)", Color(1.0, 0.9, 0.2)],
	[Vector2(822, 388), TerrainTypes.TREE, "TREE cover (destroyable)", Color(1.0, 0.9, 0.2)],
]

var scene: Node
var p: Player
var caster: Node2D
var cam: Camera2D
var focus: Node2D
var frame := 0
var aim_dir := Vector2.UP
var auto_cast := false
var _last_states := {}
var _mob_labels := {}
var _aim_line: Line2D
var _beat_label: Label
var _beat := "setup"
var _aim_changed_at := 0.0

func say(s: String) -> void:
	print("[rec %5.2fs] %s" % [frame / FPS, s])

func _wait(sec: float) -> void:
	for i in int(sec * FPS):
		await physics_frame
		_tick()

func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	for e in get_nodes_in_group("enemies"):
		if is_instance_valid(e) and (best == null or p.global_position.distance_to(e.global_position) < p.global_position.distance_to(best.global_position)):
			best = e
	return best

func _cast_toward(target: Vector2) -> void:
	var spell: Spell = caster.equipped_spell
	if spell == null or caster.cooldown_remaining(spell) > 0.0:
		return
	var dir: Vector2 = caster.global_position.direction_to(target)
	for d in SpellFanout.directions(dir, spell.projectile_count, spell.spread_degrees):
		var pr: Projectile = caster.projectile_scene.instantiate()
		pr.setup(spell, d, p)
		current_scene.add_child(pr)
		pr.global_position = caster.global_position
	caster._cooldowns[spell] = spell.cooldown
	caster.cooldown_started.emit(spell, spell.cooldown)
	caster.spell_cast.emit(spell)
	preload("res://scripts/combat_effects.gd").muzzle(current_scene, caster.global_position, dir.angle(), spell.projectile_color)

# --- recording-only overlays -----------------------------------------------
func _ring(center: Vector2, radius: float, color: Color) -> void:
	var l := Line2D.new()
	l.width = 3.0
	l.default_color = color
	l.z_index = 50
	for i in 25:
		var a := TAU * float(i) / 24.0
		l.add_point(center + Vector2(cos(a), sin(a)) * radius)
	scene.current_area.add_child(l)

func _world_label(text: String, pos: Vector2, color: Color) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.position = pos
	lab.add_theme_font_size_override("font_size", 13)
	lab.add_theme_color_override("font_color", color)
	lab.z_index = 60
	scene.current_area.add_child(lab)
	return lab

func _screen_label(text: String, pos: Vector2, size: int, color: Color, layer: CanvasLayer) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.position = pos
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", color)
	layer.add_child(lab)
	return lab

func _build_overlays(planted: bool) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	scene.add_child(layer)
	var banner := "STAGED #406 SHOWCASE - cover planted by recorder (1 OBSTACLE non-tree + 2 TREE) - script-driven aim - HP floor on"
	if not planted:
		banner = "#406 FIXTURE - UNMODIFIED SEEDED FOREST (no planted cover) - script-driven aim - HP floor on"
	_screen_label(banner, Vector2(8, 32), 14, Color(1, 1, 1), layer)
	_beat_label = _screen_label("", Vector2(8, 56), 14, Color(0.5, 1.0, 0.5), layer)
	_aim_line = Line2D.new()
	_aim_line.width = 4.0
	_aim_line.default_color = Color(1.0, 0.25, 0.25)
	_aim_line.z_index = 55
	scene.current_area.add_child(_aim_line)
	if planted:
		var terrain = scene.current_area.get_node_or_null("Terrain")
		for item in PLANTED:
			var c: Vector2 = terrain.cell_to_world(terrain.world_to_cell(item[0]))
			_ring(c, 22.0, item[3])
			_world_label(item[2], c + Vector2(16, -46), item[3])

func _set_aim(dir: Vector2, beat: String) -> void:
	aim_dir = dir
	_beat = beat
	_aim_changed_at = frame / FPS
	say("%s: aim %s" % [beat, "AT guards" if dir == Vector2.UP else "AWAY"])

func _tick() -> void:
	frame += 1
	# RECORDING-ONLY: keep the hero alive (a death would reload the run).
	if p.hp < 40:
		p.heal(60)
	var e0 := _nearest_enemy()
	focus.global_position = p.global_position.lerp(e0.global_position, 0.45) if e0 != null and p.global_position.distance_to(e0.global_position) < 700.0 else p.global_position
	if aim_dir.length_squared() > 0.0:
		p.rotation = aim_dir.angle()
	if p.sprite != null:
		p.sprite.global_rotation = 0.0
	if auto_cast and e0 != null and p.global_position.distance_to(e0.global_position) < 400.0:
		_cast_toward(e0.global_position)
	# Overlays: aim arrow, per-mob state, beat/timer readout (after build).
	if _aim_line == null:
		return
	_aim_line.points = PackedVector2Array([p.global_position, p.global_position + aim_dir * 130.0])
	for e in get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not e.get("cover_seek"):
			continue
		var beh = e.get("_behavior")
		var cov = beh.get("_cover") if beh != null else null
		if cov == null:
			continue
		cov.set("debug_trace", true)
		var st: int = cov.get("_state")
		var key := e.get_instance_id()
		var lab: Label = _mob_labels.get(key)
		if lab == null:
			lab = _world_label("", Vector2.ZERO, Color(0.4, 1.0, 1.0))
			_mob_labels[key] = lab
		lab.text = EnemyBehaviorCover.State.keys()[st]
		lab.global_position = e.global_position + Vector2(-26, -56)
		if _last_states.get(key, -1) != st:
			_last_states[key] = st
			say("mob %s -> %s" % [e.name, EnemyBehaviorCover.State.keys()[st]])
	_beat_label.text = "%s | t since aim flip: %4.2fs (charge at 3.00s)" % [_beat, frame / FPS - _aim_changed_at]

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")
	p.set_process(false) # aim is driven here instead of from the OS mouse
	caster = p.get_node("SpellCaster")
	cam = scene.get_node("FollowCamera")
	focus = Node2D.new()
	scene.add_child(focus)
	cam.target = focus
	cam.follow_speed = 3.5
	say("hub booted")
	await _wait(0.5) # let the SceneTree finish setup before Main swaps areas

	# --- Setup: jump into the overworld at the guard post -------------------
	if not scene.has_method("enter_overworld"):
		push_error("record406_cover: main scene has no enter_overworld()")
		quit(1)
		return
	scene.enter_overworld()
	say("after enter_overworld: area=%s" % (scene.current_area.name if scene.current_area else "null"))
	# Enable scan logging BEFORE the hero teleports into aggro range, so the
	# guards' first cover scan is captured.
	for e in get_nodes_in_group("enemies"):
		if e.get("cover_seek"):
			var cov0 = e.get("_behavior").get("_cover")
			if cov0 != null:
				cov0.set("debug_trace", true)
	var plant := OS.get_environment("G406_PLANT") != "0"
	# RECORDING-ONLY staging, disclosed: plant cover between the post and the
	# hero (one OBSTACLE non-tree + two destroyable TREE cells) so the guards
	# have eligible cover toward the hero (tests plant cover the same way).
	var terrain = scene.current_area.get_node_or_null("Terrain")
	if terrain != null and plant:
		for item in PLANTED:
			var planted_ok: bool = terrain.set_cell(terrain.world_to_cell(item[0]), item[1])
			say("plant %s at %s -> set_cell=%s" % [item[1], str(item[0]), planted_ok])
	elif terrain == null:
		say("WARNING: no Terrain node in overworld")
	else:
		say("G406_PLANT=0: unmodified seeded forest (no planted cover)")
	_build_overlays(plant and terrain != null)
	await _wait(1.0) # settle with the hero at the overworld spawn (out of aggro)
	p.global_position = HERO_SPOT # RECORDING-ONLY staging, disclosed
	focus.global_position = p.global_position
	cam.global_position = p.global_position
	say("hero teleported 190px south of GuardsRed post (aggro trip)")

	# --- Beat 1: aim AT the guards -> seek cover toward the hero, then HOLD -
	_set_aim(Vector2.UP, "beat1 aim AT -> seek cover, then HOLD (4s)")
	await _wait(4.0)

	if OS.get_environment("G406_SHORT") == "1":
		say("done (short fixture)")
		quit()
		return

	# --- Beat 2: aim AWAY -> after ~3s the guards CHARGE --------------------
	_set_aim(Vector2.DOWN, "beat2 aim AWAY -> CHARGE at 3.0s (5s)")
	await _wait(5.0)

	# --- Beat 3: aim back AT -> any still-seeking mob holds again -----------
	_set_aim(Vector2.UP, "beat3 aim AT again (2s)")
	await _wait(2.0)

	# --- Beat 4: fight the mobs under the cover behavior --------------------
	auto_cast = true
	_beat = "beat4 fighting"
	say("beat4: fighting (3s)")
	await _wait(3.0)
	say("done")
	quit()
