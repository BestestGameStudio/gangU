extends SceneTree
## Every screen-space panel in the real game (HUD plate, equip panel, shop
## panel) draws with the shared UiStyle look: 2px grey-blue border, 8px
## corners and a drop shadow on panels; 1px / 4px-corner rows that thicken to
## 2px when highlighted. Values are literals so a drifting palette fails here.

const PANEL_BORDER := Color(0.55, 0.6, 0.72, 0.85)
const PANEL_BG := Color(0.05, 0.05, 0.07, 0.92)
const PLATE_BG := Color(0.02, 0.02, 0.03, 0.55)
const B_DIM := Color(0.45, 0.48, 0.55, 0.6)
const B_SELECTED := Color(0.85, 0.9, 1.0, 0.9)
const B_ACCENT := Color(0.95, 0.75, 0.25, 0.9)

var failures := 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("[191] ", label, " -> PASS")
	else:
		failures += 1
		print("[191] ", label, " -> FAIL")

func _check_panel(sb: StyleBox, bg: Color, who: String) -> void:
	var f := sb as StyleBoxFlat
	_check(f != null, "%s panel is a StyleBoxFlat" % who)
	if f == null:
		return
	_check(f.border_width_left == 2 and f.border_width_top == 2 and f.border_width_right == 2 and f.border_width_bottom == 2,
		"%s border 2px all sides" % who)
	_check(f.corner_radius_top_left == 8 and f.corner_radius_top_right == 8 and f.corner_radius_bottom_left == 8 and f.corner_radius_bottom_right == 8,
		"%s corners 8px" % who)
	_check(f.border_color == PANEL_BORDER, "%s border color (got %s)" % [who, str(f.border_color)])
	_check(f.bg_color == bg, "%s background (got %s)" % [who, str(f.bg_color)])
	_check(f.shadow_size == 6, "%s drop shadow 6px" % who)

func _check_row(sb: StyleBox, border: Color, width: int, who: String) -> void:
	var f := sb as StyleBoxFlat
	_check(f != null, "%s is a StyleBoxFlat" % who)
	if f == null:
		return
	_check(f.border_width_left == width and f.border_width_bottom == width, "%s border %dpx (got %d)" % [who, width, f.border_width_left])
	_check(f.corner_radius_top_left == 4 and f.corner_radius_bottom_right == 4, "%s corners 4px" % who)
	_check(f.border_color == border, "%s border color (got %s)" % [who, str(f.border_color)])

func _initialize() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 10:
		await process_frame

	var hud: Node = main.get_node("HUD")
	var plate := hud.get_node("BackingPlate") as Panel
	_check(plate != null, "HUD BackingPlate is a Panel")
	_check_panel(plate.get_theme_stylebox("panel"), PLATE_BG, "HUD plate")
	_check(PLATE_BG.a < 1.0, "HUD plate stays translucent")
	var frames: Array = hud.get_node("Root/SpellRows").get_children()
	_check(frames.size() >= 2, "HUD shows starting spell rows (got %d)" % frames.size())
	var widths: Array[int] = []
	for f: PanelContainer in frames:
		var sb := f.get_theme_stylebox("panel") as StyleBoxFlat
		widths.append(sb.border_width_left)
		_check(sb.corner_radius_top_left == 4, "HUD spell row corners 4px")
	_check(widths.count(2) == 1 and widths.count(1) == frames.size() - 1, "HUD: only the equipped row is highlighted (widths %s)" % str(widths))

	var equip: EquipPanel = main.get_node("EquipPanel")
	equip.show_panel()
	await process_frame
	var center: CenterContainer = equip.find_children("*", "CenterContainer", false, false)[0]
	var eplate := center.get_child(0) as PanelContainer
	_check_panel(eplate.get_theme_stylebox("panel"), PANEL_BG, "Equip panel")
	var cols := eplate.get_child(0).get_child(1) as HBoxContainer
	var unlocked_box := cols.get_child(0) as VBoxContainer
	var slots_box := cols.get_child(1) as VBoxContainer
	var first_row: Button = unlocked_box.get_child(1)
	var row_text := first_row.text
	_check_row(first_row.get_theme_stylebox("normal"), B_DIM, 1, "Equip unlocked row at rest")
	var hover := first_row.get_theme_stylebox("hover") as StyleBoxFlat
	var normal := first_row.get_theme_stylebox("normal") as StyleBoxFlat
	_check(hover.bg_color != normal.bg_color, "Equip row hover lightens the fill")
	_check_row(slots_box.get_child(1).get_theme_stylebox("normal"), B_DIM, 1, "Equip empty slot")
	first_row.pressed.emit()
	await process_frame
	var selected: Button = null
	for c in unlocked_box.get_children():
		if c is Button and c.text == row_text:
			selected = c
	_check_row(selected.get_theme_stylebox("normal"), B_SELECTED, 2, "Equip selected row highlighted")
	equip.hide_panel()

	var shop: ShopPanel = main.get_node("ShopPanel")
	shop.open()
	await process_frame
	var backdrop := shop.get_node("Backdrop") as Panel
	_check(backdrop != null, "Shop Backdrop is a Panel")
	_check_panel(backdrop.get_theme_stylebox("panel"), PANEL_BG, "Shop panel")
	var rows: Array = shop.get_node("Backdrop/Margin/VBox/Rows").get_children()
	_check(rows.size() == 4, "Shop renders 4 slots (got %d)" % rows.size())
	for r: PanelContainer in rows:
		_check_row(r.get_theme_stylebox("panel"), B_DIM, 1, "Shop row %s" % r.name)
	var buy := shop.find_children("BuyButton", "Button", true, false)
	_check(buy.size() >= 1, "Shop has a buy button")
	if buy.size() >= 1:
		_check_row(buy[0].get_theme_stylebox("normal"), B_ACCENT, 1, "Shop buy button")
	var reroll := shop.get_node("Backdrop/Margin/VBox/RefreshButton") as Button
	_check_row(reroll.get_theme_stylebox("normal"), B_ACCENT, 1, "Shop re-roll button")
	var disabled := reroll.get_theme_stylebox("disabled") as StyleBoxFlat
	_check(disabled.border_color.a < B_ACCENT.a, "Shop re-roll disabled state fades its border")

	print("[191] RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(1 if failures > 0 else 0)
