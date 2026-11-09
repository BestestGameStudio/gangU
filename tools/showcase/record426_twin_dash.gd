extends SceneTree
## #426 rendered fixture (synthetic, NOT natural gameplay): a Mustache Warlord
## boss dies with the relic roll forced to 100% (BossRelicDrop.drop_chance),
## leaving its Upgrade Token and the Twin Dash relic. The player walks onto
## the relic, then dashes twice back-to-back; the label shows dash charges.
## Run under xvfb with --write-movie; quits itself.

var _p: Player
var _relics: OwnedRelics
var _label: Label
var _phase := ""

func _initialize() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.16, 0.12)
	bg.position = Vector2(-200, -200)
	bg.size = Vector2(1600, 1200)
	stage.add_child(bg)
	_relics = OwnedRelics.new()
	stage.add_child(_relics)
	_p = load("res://scenes/player.tscn").instantiate()
	_p.name = "Player"
	stage.add_child(_p)
	_p.global_position = Vector2(300, 400)
	var boss: Enemy = load("res://scenes/mustache_warlord.tscn").instantiate()
	boss.player_path = NodePath("../Player")
	boss.add_to_group("boss")
	stage.add_child(boss)
	boss.global_position = Vector2(560, 400)
	boss.set_physics_process(false)
	var cam := Camera2D.new()
	cam.position = Vector2(560, 400)
	cam.zoom = Vector2(2.0, 2.0)
	stage.add_child(cam)
	cam.make_current()
	var hud := CanvasLayer.new()
	stage.add_child(hud)
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 36)
	hud.add_child(_label)
	BossRelicDrop.drop_chance = 1.0
	_phase = "boss alive"
	await _run_frames(15)
	boss.apply_damage(boss.max_hp * 10)
	_phase = "boss killed: Upgrade Token + Twin Dash relic dropped"
	await _run_frames(30)
	var relic_drop: RewardDrop = null
	for c in stage.get_children():
		if c is RewardDrop and c.entry.kind == RewardEntry.Kind.RELIC:
			relic_drop = c
	if relic_drop != null:
		_p.global_position = relic_drop.global_position + Vector2(0, 90)
		await _run_frames(5)
		_p.global_position = relic_drop.global_position
	_phase = "relic picked up"
	await _run_frames(20)
	_p.global_position = Vector2(380, 520)
	await _run_frames(5)
	_phase = "dash 1"
	_p.try_dash(Vector2.RIGHT)
	await _run_frames(10)
	_phase = "dash 2 (back-to-back)"
	_p.try_dash(Vector2.RIGHT)
	await _run_frames(10)
	_phase = "third dash refused: recharging"
	_p.try_dash(Vector2.RIGHT)
	await _run_frames(60)
	quit(0)

func _run_frames(n: int) -> void:
	for i in n:
		await physics_frame
		var owned := "Twin Dash" if _relics.has_id(&"twin_dash") else "none"
		_label.text = "%s\nrelics: %s   dash charges: %d / %d" % [_phase, owned, _p.dash_charges(), _p.dash_max_charges()]
		await process_frame
