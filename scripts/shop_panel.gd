class_name ShopPanel
extends ModalPanel
## (#129, foundation C2) Shop choice panel. Hidden by default; the hub
## vendor opens it on walk-up and closes it on walk-away (Daniel,
## 2026-11-07). Shows the shop's STOCK: a spell the player already owns
## never appears (ownership exclusion), and buying one removes its row
## immediately. Wallet balance rides the #128 balance_changed signal.
##
## (#132, foundation C5) The panel renders exactly Shop.stock_size slots
## (Daniel 2026-11-08: "show 4 slots for now"). A slot with no eligible
## item shows an OUT OF STOCK sign ("if theres no eligible item display
## an out of stock sign"). A RE-ROLL STOCK button buys a paid refresh at
## the shop's current schedule price (1, 2, 3, 5, 8... Fibonacci); it is
## disabled while Shop.can_paid_refresh() is false. Victory re-rolls and
## price resets arrive live through Shop.stock_refreshed.
##
## UI is code-built; the look comes from UiStyle.
## ModalPanel: no casting while open. Found via the "shop_panel" group.

const ROW_PAD := 6.0
const OUT_OF_STOCK_TEXT := "OUT OF STOCK"
## (#428) Relics section. Daniel 2026-11-09: "add a section for relics in
## the shop UI". Display only: relic goods already in the shop's stock
## render here instead of among the spell/consumable rows. Stock, prices
## and the buy flow are unchanged, and the slot total stays stock_size.
const RELICS_HEADER_TEXT := "RELICS"
const NO_RELICS_TEXT := "No relics for sale"

var _shop: Shop
var _wallet: CurrencyWallet
var _balance_label: Label
var _rows: VBoxContainer
var _relic_rows: VBoxContainer
var _refresh_button: Button

func _ready() -> void:
	add_to_group("shop_panel")
	layer = 3
	_build_skeleton()
	_shop = get_tree().get_first_node_in_group("shop") as Shop
	_wallet = Run.wallet()
	if _wallet != null and not _wallet.balance_changed.is_connected(_on_balance_changed):
		_wallet.balance_changed.connect(_on_balance_changed)
	if _shop != null:
		if not _shop.purchased.is_connected(_on_purchased):
			_shop.purchased.connect(_on_purchased)
		if not _shop.stock_refreshed.is_connected(_on_stock_refreshed):
			_shop.stock_refreshed.connect(_on_stock_refreshed)
	visible = false

func open() -> void:
	_render()
	_set_shown(true)

func close() -> void:
	_set_shown(false)

func _build_skeleton() -> void:
	var backdrop := Panel.new()
	backdrop.name = "Backdrop"
	backdrop.add_theme_stylebox_override("panel", UiStyle.panel())
	backdrop.anchor_left = 0.5
	backdrop.anchor_top = 0.5
	backdrop.anchor_right = 0.5
	backdrop.anchor_bottom = 0.5
	backdrop.offset_left = -230.0
	backdrop.offset_top = -215.0
	backdrop.offset_right = 230.0
	backdrop.offset_bottom = 215.0
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	backdrop.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	var title := Label.new()
	title.text = "SHOP"
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	_balance_label = Label.new()
	_balance_label.name = "BalanceLabel"
	_balance_label.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	_balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_balance_label)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", 6)
	vbox.add_child(_rows)
	var relic_header := Label.new()
	relic_header.name = "RelicHeader"
	relic_header.text = RELICS_HEADER_TEXT
	relic_header.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	relic_header.add_theme_font_size_override("font_size", 13)
	vbox.add_child(relic_header)
	_relic_rows = VBoxContainer.new()
	_relic_rows.name = "RelicRows"
	_relic_rows.add_theme_constant_override("separation", 6)
	vbox.add_child(_relic_rows)
	_refresh_button = Button.new()
	_refresh_button.name = "RefreshButton"
	UiStyle.style_button(_refresh_button, UiStyle.B_ACCENT, ROW_PAD)
	_refresh_button.pressed.connect(_on_refresh_pressed)
	vbox.add_child(_refresh_button)
	var hint := Label.new()
	hint.text = "Walk away to close"
	hint.add_theme_color_override("font_color", UiStyle.TEXT_DIM * Color(1, 1, 1, 0.6))
	hint.add_theme_font_size_override("font_size", 11)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

## (#132) Exactly stock_size slot rows: stocked entries first, then one
## OUT OF STOCK sign per unfillable slot. The re-roll button always shows
## the CURRENT paid price and disables when no re-roll could surface a
## new good.
func _render() -> void:
	_update_balance_text()
	for box in [_rows, _relic_rows]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	if _shop == null:
		return
	# (#428) Relic goods go to the RELICS section; the general rows keep
	# the remaining slots, so both sections together show stock_size slots.
	var goods: Array[ShopEntry] = []
	var relics: Array[ShopEntry] = []
	for e in _shop.stock_entries():
		if e.good is Relic:
			relics.append(e)
		else:
			goods.append(e)
	for i in range(maxi(_shop.stock_size - relics.size(), 0)):
		if i < goods.size():
			_rows.add_child(_make_row(goods[i]))
		else:
			_rows.add_child(_make_out_of_stock_row())
	for e in relics:
		_relic_rows.add_child(_make_row(e))
	if relics.is_empty():
		_relic_rows.add_child(_make_no_relics_row())
	_refresh_button.text = "RE-ROLL STOCK (%dc)" % _shop.paid_refresh_price()
	_refresh_button.disabled = not _shop.can_paid_refresh()

func _make_row(entry: ShopEntry) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UiStyle.row(UiStyle.B_DIM, ROW_PAD))
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)
	# #449: relic rows are ICON ONLY - the relic's name and description
	# live in the icon's hover tooltip (Daniel, 2026-11-09). Spells and
	# consumables keep the existing SpellIcon + name label.
	if entry.good is Relic:
		var relic_icon := RelicIcon.new()
		relic_icon.show_relic(entry.good as Relic)
		hbox.add_child(relic_icon)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(spacer)
	else:
		var icon := SpellIcon.new()
		icon.show_spell(entry.good as Spell)
		hbox.add_child(icon)
		var name_label := Label.new()
		name_label.text = _good_name(entry.good)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(name_label)
	var price_label := Label.new()
	price_label.text = "%dc" % entry.price
	price_label.add_theme_color_override("font_color", UiStyle.B_ACCENT)
	hbox.add_child(price_label)
	var buy_button := Button.new()
	buy_button.name = "BuyButton"
	buy_button.text = "BUY"
	UiStyle.style_button(buy_button, UiStyle.B_ACCENT, ROW_PAD)
	buy_button.pressed.connect(_on_buy_pressed.bind(entry))
	hbox.add_child(buy_button)
	return row

## (#132) The OUT OF STOCK sign for a slot with no eligible item: dimmed,
## no buy button, no price.
func _make_out_of_stock_row() -> Control:
	var row := PanelContainer.new()
	row.name = "OutOfStockRow"
	row.add_theme_stylebox_override("panel", UiStyle.row(UiStyle.B_DIM, ROW_PAD))
	var label := Label.new()
	label.name = "OutOfStockLabel"
	label.text = OUT_OF_STOCK_TEXT
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", UiStyle.TEXT_DIM * Color(1, 1, 1, 0.7))
	row.add_child(label)
	return row

## (#428) Honest empty state for the RELICS section: dimmed, no buy button.
func _make_no_relics_row() -> Control:
	var row := PanelContainer.new()
	row.name = "NoRelicsRow"
	row.add_theme_stylebox_override("panel", UiStyle.row(UiStyle.B_DIM, ROW_PAD))
	var label := Label.new()
	label.name = "NoRelicsLabel"
	label.text = NO_RELICS_TEXT
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", UiStyle.TEXT_DIM * Color(1, 1, 1, 0.7))
	row.add_child(label)
	return row

static func _good_name(good: Resource) -> String:
	if good is Spell:
		return (good as Spell).spell_name
	if good is Consumable:
		return (good as Consumable).consumable_name
	if good is Relic and (good as Relic).display_name != "":
		return (good as Relic).display_name
	return "Item"

func _update_balance_text() -> void:
	_balance_label.text = "Wallet: %dc" % (_wallet.balance() if _wallet != null else 0)

func _on_balance_changed(_new_balance: int) -> void:
	_update_balance_text()

func _on_purchased(_entry: ShopEntry) -> void:
	if visible:
		_render()

func _on_stock_refreshed() -> void:
	if visible:
		_render()

func _on_buy_pressed(entry: ShopEntry) -> void:
	if _shop != null:
		_shop.buy(entry)
	_render() # re-render either way: success drops the row, failure is visible

## (#132) Paid re-roll. buy_paid_refresh refuses (and charges nothing)
## when unaffordable or when no new good could surface; the re-render
## shows the unchanged stock and price either way.
func _on_refresh_pressed() -> void:
	if _shop != null:
		_shop.buy_paid_refresh()
	_render()
