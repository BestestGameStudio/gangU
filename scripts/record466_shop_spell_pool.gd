extends SceneTree
## #466 rendered fixture: the production shop pool holds every PLAYER
## spell in the game (resources/shop/demo_catalog.tres, 39 spells, flat
## 10c; the enemy-only boss spells head_bolt/warlord_orb are excluded -
## Daniel 2026-11-09: "Do not keep enemy spells") and each stock shows 3
## random picks from it. Real production catalog + real ShopPanel; the
## RE-ROLL press goes through the panel's own button. Run under xvfb with
## --write-movie.

var _frame := 0
var _label: Label
const END := 420 # 7s at 60fps

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
	var wallet := CurrencyWallet.new()
	root.add_child(wallet)
	wallet.add(100)
	root.add_child(OwnedRelics.new())
	var panel: ShopPanel = preload("res://scenes/shop_panel.tscn").instantiate()
	root.add_child(panel)
	var shop := Shop.new()
	shop.setup(preload("res://resources/shop/demo_catalog.tres"))
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
	_label.text = "#466 shop pool: all 39 player spells, flat 10c - 3 random per stock"
	hud.add_child(_label)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_setup()
	if _frame == 180:
		# Paid re-roll through the panel's own button: a new random 3.
		var panel := root.get_node_or_null("ShopPanel")
		if panel != null:
			var btn := panel.find_children("RefreshButton", "Button", true, false)
			if not btn.is_empty():
				btn[0].pressed.emit()
				_label.text = "#466 paid re-roll: a new random 3 from the 39-spell pool"
	if _frame >= END:
		quit(0)
	return false
