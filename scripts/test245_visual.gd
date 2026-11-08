extends SceneTree
## LOCAL fixture only: actual Player/caster/manager/guard, no production unlock claim.
var clock := 0.0
var p: Player
var screenshot_done := false
func _initialize() -> void:
	var stage := Node2D.new()
	stage.name = "LocalGlowFixture"
	root.add_child(stage)
	current_scene = stage
	RenderingServer.set_default_clear_color(Color(0.10, 0.12, 0.16))
	var backdrop := Polygon2D.new()
	backdrop.polygon = PackedVector2Array([Vector2(100, 150), Vector2(1050, 150), Vector2(1050, 550), Vector2(100, 550)])
	backdrop.color = Color(0.22, 0.25, 0.29)
	stage.add_child(backdrop)
	p = load("res://scenes/player.tscn").instantiate()
	stage.add_child(p)
	p.position = Vector2(450, 340)
	p.set_physics_process(false)
	var manager := SummonManager.new()
	manager.caster_path = NodePath("../Player/SpellCaster")
	stage.add_child(manager)
	await process_frame
	var spell: Spell = load("res://resources/spells/summon_ally.tres")
	var caster: SpellCaster = p.get_node("SpellCaster")
	# #262: default spells self-bind at caster._ready; clear BOTH default
	# slots BEFORE the grant so the fixture's slot-0 flow is unchanged.
	caster.clear_slot(0)
	caster.clear_slot(1)
	caster.unlock_spell(spell)
	caster.assign_slot(0, spell)
	caster.cast_slot(0)
	var ally: Summon = get_first_node_in_group("summons")
	ally.position = Vector2(600, 340)
	var unowned: Summon = load("res://scenes/summon.tscn").instantiate()
	stage.add_child(unowned)
	unowned.position = Vector2(870, 340)
	var title := Label.new()
	title.text = "LOCAL #245 fixture - subtle blue player-summon halo (not LIVE acquisition)"
	title.position = Vector2(100, 95)
	stage.add_child(title)
	var owned_label := Label.new()
	owned_label.text = "Player-owned: blue halo + gentle pulse"
	owned_label.position = Vector2(380, 450)
	stage.add_child(owned_label)
	var control_label := Label.new()
	control_label.text = "Unowned: unchanged body, no halo"
	control_label.position = Vector2(740, 450)
	stage.add_child(control_label)

func _process(delta: float) -> bool:
	clock += delta
	if p != null:
		p.position = Vector2(430 + sin(clock * 0.8) * 75, 340 + sin(clock * 1.1) * 30)
	if clock > 2 and not screenshot_done:
		screenshot_done = true
		capture.call_deferred()
	if clock > 8:
		quit()
	return false

func capture() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/downloads/245-local.png")
