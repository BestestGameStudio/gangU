extends SceneTree
## #449 rendered fixture (SHOP half): the relic row in the shop is icon
## only - one shared code-drawn amber diamond - and hovering it shows the
## relic's name + description as the real tooltip (mouse is warped over
## the icon; nothing is faked). Run under xvfb with --write-movie.

var _frame := 0
var _icon: RelicIcon
var _label: Label
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
	p.add_to_group("player")
	p.visible = false
	root.add_child(p)
	var wallet := CurrencyWallet.new()
	root.add_child(wallet)
	wallet.add(100)
	root.add_child(OwnedRelics.new())
	var panel: ShopPanel = preload("res://scenes/shop_panel.tscn").instantiate()
	root.add_child(panel)
	var shop := Shop.new()
	var catalog := ShopCatalog.new()
	var e_spell := ShopEntry.new()
	e_spell.good = load("res://resources/spells/fire_ball.tres")
	e_spell.price = 10
	var e_relic := ShopEntry.new()
	e_relic.good = load("res://resources/relics/twin_dash.tres")
	e_relic.price = 25
	catalog.entries = [e_spell, e_relic]
	shop.setup(catalog)
	root.add_child(shop)
	panel._shop = shop
	shop.purchased.connect(panel._on_purchased)
	shop.stock_refreshed.connect(panel._on_stock_refreshed)
	panel.open()
	var hud := CanvasLayer.new()
	hud.layer = 10
	root.add_child(hud)
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 30)
	_label.text = "#449 shop relic icon - icon only, name + desc on hover"
	hud.add_child(_label)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_setup()
	if _frame == 60:
		var panel := root.get_node_or_null("ShopPanel")
		var icons := panel.find_children("*", "RelicIcon", true, false)
		if not icons.is_empty():
			_icon = icons[0]
			var center := _icon.get_global_rect().get_center()
			Input.warp_mouse(center)
	if _frame >= END:
		quit(0)
	return false
