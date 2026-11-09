extends SceneTree
## RECORDING-ONLY showcase driver for #414 (not a test, not loaded by the
## game). Boots main.tscn, jumps into the overworld and stages the branch
## behavior with PRODUCTION scenes/scripts:
##   beat1 pursuit:  a slime patroller (plain chase) engages the hero and
##                   keeps chasing PAST the old 520px leash (new: 900).
##   beat2 give-up:  past 900px the patroller gives up and RETURNS TO ITS
##                   OLD ROUTE (Daniel, 2026-11-09: "return to its old route").
##   beat3 relocate: a moustache man holding cover over 5s DASHes to a
##                   DIFFERENT nearby cover, even while aimed at.
##   beat4 charge:   once CHARGE begins, re-aiming at the mob never stops
##                   it; only contact ends it.
## The script drives only the hero's aim direction (the same global_rotation
## contract the player script writes from the mouse), teleports the hero
## between staged spots, and keeps a recording-only HP floor. Enemies run
## untouched production behaviors. Cover for beats 3-4 is planted via the
## production TerrainMap (tests plant cover the same way) and disclosed on
## the banner.
## Usage:
##   xvfb-run -a godot --path . --write-movie out.avi --fixed-fps 60 \
##         --rendering-driver opengl3 --script res://tools/showcase/record414_pursuit.gd

const FPS := 60.0
## GuardsRed post from scenes/overworld.tscn (guard at (822,270)).
const GUARD_POST := Vector2(822, 270)
## Hero stands 190px south of the post (inside the 220px aggro radius).
const HERO_SPOT := Vector2(822, 460)
## Slime patroller loop (Normal entrance): (370,340),(420,310),(400,240),(330,260).
const SLIME_TRIP := Vector2(390, 390)
## [world_pos, TerrainTypes kind, label, color] - same staging as record406.
const PLANTED := [
	[Vector2(855, 340), TerrainTypes.OBSTACLE, "cover A", Color(1.0, 0.45, 0.2)],
	[Vector2(790, 345), TerrainTypes.TREE, "cover B", Color(1.0, 0.9, 0.2)],
]

var scene: Node
var p: Player
var cam: Camera2D
var focus: Node2D
var frame := 0
var aim_dir := Vector2.ZERO
var _last_states := {}
var _mob_labels := {}
var _aim_line: Line2D
var _beat_label: Label
var _beat := "setup"
var _beat_started := 0.0

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

func _build_overlays() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	scene.add_child(layer)
	_screen_label("STAGED #414 SHOWCASE - cover A/B planted by recorder - script-driven aim + teleports - HP floor on", Vector2(8, 32), 14, Color(1, 1, 1), layer)
	_beat_label = _screen_label("", Vector2(8, 56), 14, Color(0.5, 1.0, 0.5), layer)
	_aim_line = Line2D.new()
	_aim_line.width = 4.0
	_aim_line.default_color = Color(1.0, 0.25, 0.25)
	_aim_line.z_index = 55
	scene.current_area.add_child(_aim_line)
	var terrain = scene.current_area.get_node_or_null("Terrain")
	for item in PLANTED:
		var c: Vector2 = terrain.cell_to_world(terrain.world_to_cell(item[0]))
		_ring(c, 22.0, item[3])
		_world_label(item[2], c + Vector2(16, -46), item[3])

func _set_beat(beat: String) -> void:
	_beat = beat
	_beat_started = frame / FPS
	say(beat)

func _state_text(e: Enemy) -> String:
	var beh = e.get("_behavior")
	if beh == null:
		return ""
	if e.get("cover_seek"):
		var cov = beh.get("_cover")
		if cov != null:
			cov.set("debug_trace", true)
			return EnemyBehaviorCover.State.keys()[cov.get("_state")]
	if beh is EnemyBehaviorPatrol:
		return "PATROL%s wp=%d" % [" ENGAGED" if beh.engaged else "", beh.waypoint]
	if beh is EnemyBehaviorGuard:
		return "GUARD%s" % [" ENGAGED" if beh.engaged else ""]
	return ""

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
	if _aim_line != null:
		_aim_line.points = PackedVector2Array([p.global_position, p.global_position + aim_dir * 130.0]) if aim_dir.length_squared() > 0.0 else PackedVector2Array()
	for e in get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Enemy):
			continue
		var txt := _state_text(e)
		if txt == "":
			continue
		var key := e.get_instance_id()
		var lab: Label = _mob_labels.get(key)
		if lab == null:
			lab = _world_label("", Vector2.ZERO, Color(0.4, 1.0, 1.0))
			_mob_labels[key] = lab
		lab.text = txt
		lab.global_position = e.global_position + Vector2(-40, -56)
		if _last_states.get(key, "") != txt:
			_last_states[key] = txt
			say("mob %s -> %s" % [e.name, txt])
	if _beat_label != null:
		_beat_label.text = "%s | beat t=%4.2fs" % [_beat, frame / FPS - _beat_started]

func _hop(pos: Vector2, note: String) -> void:
	p.global_position = pos # RECORDING-ONLY staging, disclosed
	focus.global_position = pos
	cam.global_position = pos
	say(note)

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")
	p.set_process(false) # aim is driven here instead of from the OS mouse
	cam = scene.get_node("FollowCamera")
	focus = Node2D.new()
	scene.add_child(focus)
	cam.target = focus
	cam.follow_speed = 3.5
	say("hub booted")
	await _wait(0.5)
	scene.enter_overworld()
	say("after enter_overworld: area=%s" % (scene.current_area.name if scene.current_area else "null"))
	var terrain = scene.current_area.get_node_or_null("Terrain")
	if terrain != null:
		for item in PLANTED:
			terrain.set_cell(terrain.world_to_cell(item[0]), item[1])
	_build_overlays()
	await _wait(1.0)

	# --- Beat 1: the slime patroller engages and chases ----------------------
	_set_beat("beat1: slime patroller engages (plain chase, no cover)")
	_hop(SLIME_TRIP, "hero trips the slime patrol loop near Normal")
	await _wait(2.5)

	# --- Beat 1b: ~570px from where the chase began: PAST the old 520 leash -
	_set_beat("beat1b: hero ~570px out - past the OLD 520 leash, still chased (new: 900)")
	_hop(Vector2(390, -220), "hero hops to ~570px from chase start")
	await _wait(2.5)

	# --- Beat 2: past 900 the patroller gives up and returns to its route ---
	_set_beat("beat2: past 900px the patroller gives up and RETURNS TO ITS OLD ROUTE")
	_hop(Vector2(390, -660), "hero hops past the 900px chase distance")
	await _wait(2.0) # give-up registers
	_hop(Vector2(700, 500), "hero steps aside; camera back on the patrol loop")
	await _wait(6.0) # production walk-back speed, unmodified

	# --- Beat 3: moustache man holds cover, relocates after 5s while aimed --
	_set_beat("beat3: aim AT - holds cover; over 5s it finds a DIFFERENT cover (aimed at or not)")
	_hop(HERO_SPOT, "hero 190px south of GuardsRed post (aggro trip)")
	aim_dir = Vector2.UP
	await _wait(6.5)

	# --- Beat 4: aim away -> charge; re-aim AT -> the charge does not stop --
	_set_beat("beat4: aim AWAY 3s -> CHARGE; re-aim AT - the charge does not stop")
	aim_dir = Vector2.DOWN
	await _wait(3.4)
	aim_dir = Vector2.UP
	say("re-aimed AT the charging mob")
	await _wait(2.5)
	say("done")
	quit()
