extends Node2D
## #132 DEMO driver (test-only): exercises the shop STOCK panel on screen
## for the PR evidence video - buy from a slot, two paid re-rolls with the
## Fibonacci price climbing (1c -> 2c -> 3c), a dungeon-victory free
## refresh resetting the price, then buying the stock out until every
## slot signs OUT OF STOCK and re-roll refuses. Content-free: demo-named
## harness spells/prices, NOT shipped catalog data.

var _shop: Shop
var _panel: ShopPanel
var _caster: SpellCaster
var _wallet: CurrencyWallet
var _steps: Array = [] # [time_seconds, Callable]
var _t := 0.0

func _ready() -> void:
	seed(7) # stable stock order for the recording
	var player := Player.new()
	player.name = "DemoPlayer"
	player.set_process(false)
	player.set_physics_process(false)
	var aim := Node2D.new()
	aim.name = "AimIndicator"
	player.add_child(aim)
	var bod := Polygon2D.new()
	bod.name = "Body"
	player.add_child(bod)
	var nose := Polygon2D.new()
	nose.name = "NoseEdge"
	player.add_child(nose)
	_caster = SpellCaster.new()
	_caster.name = "SpellCaster"
	player.add_child(_caster)
	add_child(player)

	var bag := Consumables.new()
	bag.player_path = NodePath("../DemoPlayer")
	add_child(bag)
	_wallet = CurrencyWallet.new()
	add_child(_wallet)
	_wallet.add(200)

	var names := ["Demo Bolt", "Demo Ember", "Demo Frost", "Demo Gale", "Demo Volt", "Demo Zephyr"]
	var prices := [10, 15, 20, 25, 30, 35]
	var catalog := ShopCatalog.new()
	for i in range(names.size()):
		var s := Spell.new()
		s.spell_name = names[i]
		var e := ShopEntry.new()
		e.good = s
		e.price = prices[i]
		catalog.entries.append(e)
	_shop = Shop.new()
	_shop.setup(catalog)
	add_child(_shop)
	_panel = preload("res://scenes/shop_panel.tscn").instantiate()
	add_child(_panel)

	_steps = [
		[0.5, Callable(self, "_open")],
		[2.5, Callable(self, "_buy_first")],
		[4.5, Callable(self, "_reroll")], # 1c
		[6.5, Callable(self, "_reroll")], # 2c
		[8.5, Callable(self, "_victory")], # free + price reset to 1c
		[10.5, Callable(self, "_buy_first")],
		[12.5, Callable(self, "_buy_first")],
		[14.5, Callable(self, "_buy_first")],
		[16.5, Callable(self, "_buy_first")],
		[18.5, Callable(self, "_buy_first")], # last good: all slots OUT OF STOCK
		[20.5, Callable(self, "_reroll")], # refused: nothing left to surface
	]

func _process(delta: float) -> void:
	_t += delta
	while not _steps.is_empty() and _t >= _steps[0][0]:
		var step = _steps.pop_front()
		step[1].call()

func _open() -> void:
	_panel.open()

func _buy_first() -> void:
	for row in _panel._rows.get_children():
		var btns := row.find_children("BuyButton", "Button", true, false)
		if not btns.is_empty():
			btns[0].pressed.emit()
			return

func _reroll() -> void:
	_panel._refresh_button.pressed.emit()

func _victory() -> void:
	_shop.on_dungeon_victory()
