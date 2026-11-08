class_name ShopPanel
extends CanvasLayer
## (#129, foundation C2) Shop choice panel. Hidden by default; the hub
## vendor opens it on walk-up and closes it on walk-away (Daniel,
## 2026-11-07). Shows only OFFERABLE entries - a spell the player already
## owns never appears (ownership exclusion), and buying one removes its
## row immediately. Wallet balance rides the #128 balance_changed signal.
##
## UI is code-built in the #94 flat identity (StyleBoxFlat, no assets).
## While visible the panel joins "modal_ui" so the caster skips casting on
## panel clicks (EquipPanel idiom). Found via the "shop_panel" group.

const PANEL_BG := Color(0.05, 0.05, 0.07, 0.92)
const ROW_BG := Color(0.08, 0.08, 0.1, 0.9)
const B_DIM := Color(0.45, 0.48, 0.55, 0.6)
const B_BUY := Color(0.95, 0.75, 0.25, 0.9)
const TEXT_DIM := Color(0.7, 0.72, 0.78, 1.0)

var _shop: Shop
var _wallet: CurrencyWallet
var _balance_label: Label
var _rows: VBoxContainer

func _ready() -> void:
	add_to_group("shop_panel")
	layer = 3
	_build_skeleton()
	_shop = get_tree().get_first_node_in_group("shop") as Shop
	_wallet = get_tree().get_first_node_in_group("currency_wallet") as CurrencyWallet
	if _wallet != null and not _wallet.balance_changed.is_connected(_on_balance_changed):
		_wallet.balance_changed.connect(_on_balance_changed)
	if _shop != null and not _shop.purchased.is_connected(_on_purchased):
		_shop.purchased.connect(_on_purchased)
	visible = false

func open() -> void:
	_render()
	visible = true
	add_to_group("modal_ui") # caster cast-guard hook (EquipPanel idiom)

func close() -> void:
	visible = false
	remove_from_group("modal_ui")

func _flat(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(6.0)
	return sb

func _build_skeleton() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = PANEL_BG
	backdrop.anchor_left = 0.5
	backdrop.anchor_top = 0.5
	backdrop.anchor_right = 0.5
	backdrop.anchor_bottom = 0.5
	backdrop.offset_left = -230.0
	backdrop.offset_top = -180.0
	backdrop.offset_right = 230.0
	backdrop.offset_bottom = 180.0
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
	_balance_label.add_theme_color_override("font_color", TEXT_DIM)
	_balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_balance_label)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", 6)
	vbox.add_child(_rows)
	var hint := Label.new()
	hint.text = "Walk away to close"
	hint.add_theme_color_override("font_color", TEXT_DIM * Color(1, 1, 1, 0.6))
	hint.add_theme_font_size_override("font_size", 11)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

func _render() -> void:
	_update_balance_text()
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	if _shop == null:
		return
	for entry in _shop.offerable_entries():
		_rows.add_child(_make_row(entry))
	if _rows.get_child_count() == 0:
		var empty := Label.new()
		empty.name = "EmptyHint"
		empty.text = "Nothing for sale right now"
		empty.add_theme_color_override("font_color", TEXT_DIM)
		_rows.add_child(empty)

func _make_row(entry: ShopEntry) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _flat(ROW_BG, B_DIM))
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)
	var name_label := Label.new()
	name_label.text = entry.good.spell_name if entry.good is Spell else (entry.good.consumable_name if entry.good is Consumable else "Item")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_label)
	var price_label := Label.new()
	price_label.text = "%dc" % entry.price
	price_label.add_theme_color_override("font_color", B_BUY)
	hbox.add_child(price_label)
	var buy_button := Button.new()
	buy_button.name = "BuyButton"
	buy_button.text = "BUY"
	buy_button.add_theme_stylebox_override("normal", _flat(ROW_BG, B_BUY))
	buy_button.pressed.connect(_on_buy_pressed.bind(entry))
	hbox.add_child(buy_button)
	return row

func _update_balance_text() -> void:
	_balance_label.text = "Wallet: %dc" % (_wallet.balance() if _wallet != null else 0)

func _on_balance_changed(_new_balance: int) -> void:
	_update_balance_text()

func _on_purchased(_entry: ShopEntry) -> void:
	if visible:
		_render()

func _on_buy_pressed(entry: ShopEntry) -> void:
	if _shop != null:
		_shop.buy(entry)
	_render() # re-render either way: success drops the row, failure is visible
