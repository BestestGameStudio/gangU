extends SceneTree
## #449 rendered fixture (TAB-MENU half): the Tab menu's relics section
## lists owned relics as icon-only placeholders; hovering one shows the
## real tooltip with name + description (mouse is warped over the icon;
## nothing is faked). Run under xvfb with --write-movie.

var _frame := 0
const END := 300 # 5s at 60fps

func _setup() -> void:
	var p := Player.new()
	p.set_process(false)
	p.set_physics_process(false)
	for n in ["AimIndicator", "Body", "NoseEdge"]:
		var c := Polygon2D.new()
		c.name = n
		p.add_child(c)
	var caster := SpellCaster.new()
	caster.name = "SpellCaster"
	p.add_child(caster)
	p.visible = false
	root.add_child(p)
	var owned := OwnedRelics.new()
	root.add_child(owned)
	var twin: Relic = load("res://resources/relics/twin_dash.tres")
	var idol := Relic.new()
	idol.id = &"basalt_idol"
	idol.display_name = "Basalt Idol"
	idol.description = "A heavy idol."
	owned.add(twin)
	owned.add(idol)
	var panel: EquipPanel = preload("res://scenes/equip_panel.tscn").instantiate()
	root.add_child(panel)
	panel.show_panel()
	var hud := CanvasLayer.new()
	hud.layer = 10
	root.add_child(hud)
	var label := Label.new()
	label.position = Vector2(24, 24)
	label.add_theme_font_size_override("font_size", 30)
	label.text = "#449 tab menu relic icons - icon only, name + desc on hover"
	hud.add_child(label)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_setup()
	if _frame == 60:
		var panel := root.get_node_or_null("EquipPanel")
		if panel != null:
			var icons := panel.find_children("*", "RelicIcon", true, false)
			if not icons.is_empty():
				Input.warp_mouse((icons[0] as RelicIcon).get_global_rect().get_center())
	if _frame >= END:
		quit(0)
	return false
