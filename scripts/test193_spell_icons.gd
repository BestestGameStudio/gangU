extends SceneTree
## Spell icon areas in the real game UI: the HUD slot square, the equip
## panel's unlocked row and slot button each show Spell.icon when
## set and a same-size placeholder box when null, and follow slot changes.

var failures := 0
var tex: ImageTexture
var hud: Node
var equip: EquipPanel
var caster: SpellCaster

func _check(ok: bool, label: String) -> void:
	if ok:
		print("[193] ", label, " -> PASS")
	else:
		failures += 1
		print("[193] ", label, " -> FAIL")

func _spell(n: String, icon: Texture2D) -> Spell:
	var s := Spell.new()
	s.spell_name = n
	s.icon = icon
	return s

func _icon_in(n: Node) -> SpellIcon:
	var found := n.find_children("SpellIcon", "TextureRect", true, false)
	return found[0] as SpellIcon if found.size() == 1 else null

func _shows_texture(icon: SpellIcon) -> bool:
	return icon != null and icon.texture == tex and not icon.get_node("Placeholder").visible

func _shows_placeholder(icon: SpellIcon) -> bool:
	return icon != null and icon.texture == null and icon.get_node("Placeholder").visible

func _shows_no_icon_sprite(icon: SpellIcon) -> bool:
	return icon != null and icon.texture == SpellIcon.NO_ICON_TEXTURE and not icon.get_node("Placeholder").visible

func _equip_row(spell_name: String) -> Button:
	var cols := equip.find_children("*", "HBoxContainer", true, false)[0]
	for c in cols.get_child(0).get_children():
		if c is Button and c.text == spell_name and not c.is_queued_for_deletion():
			return c
	return null

func _equip_slot(i: int) -> Button:
	var cols := equip.find_children("*", "HBoxContainer", true, false)[0]
	return cols.get_child(1).get_child(i + 1) as Button

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.2, 0.6, 1.0))
	tex = ImageTexture.create_from_image(img)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(10)
	hud = main.get_node("HUD")
	equip = main.get_node("EquipPanel")
	caster = main.get_node("Player/SpellCaster")
	var lit := _spell("IconBolt", tex)
	var plain := _spell("PlainBolt", null)
	caster.add_spell(lit)
	caster.add_spell(plain)
	# #262: both grants auto-bind on arrival (lit -> slot 3, plain -> slot 4).
	# Clear those two bindings so the legs below drive their own loadout as
	# before. Cleared only AFTER both grants: clearing the boot slots first
	# would shift which slots the auto-binds take.
	caster.clear_slot(2)
	caster.clear_slot(3)
	await _frames(3)

	caster.clear_slot(0) # #238: boot seeds slot 1; this leg drives its own loadout
	caster.assign_slot(0, lit)
	await _frames(2)
	var slot_icon := hud.get_node("Root/SpellGrid").get_child(0) as SpellIcon
	_check(_shows_texture(slot_icon), "HUD slot 1 shows the assigned spell's icon")
	_check(slot_icon.size == Vector2(48, 48), "HUD slot square is 48x48 with art (%s)" % str(slot_icon.size))
	caster.clear_slot(0)
	caster.assign_slot(0, plain)
	await _frames(2)
	_check(_shows_no_icon_sprite(slot_icon), "HUD slot 1 icon follows reassignment to an icon-less spell (#257 sprite)")
	_check(slot_icon.size == Vector2(48, 48), "HUD slot square keeps its size across the swap")

	caster.clear_slot(0)
	caster.assign_slot(0, lit)
	equip.show_panel()
	await _frames(2)
	_check(_shows_texture(_icon_in(_equip_row("IconBolt"))), "Equip unlocked row shows the spell's icon")
	_check(_shows_no_icon_sprite(_icon_in(_equip_row("PlainBolt"))), "Equip unlocked row without icon shows the placeholder sprite (#257)")
	var eq_lit := _icon_in(_equip_row("IconBolt"))
	var eq_plain := _icon_in(_equip_row("PlainBolt"))
	_check(eq_lit.size == Vector2(22, 22) and eq_plain.size == Vector2(22, 22), "Equip row icon areas are 22x22 in both states")
	var slot_btn_icon := _icon_in(_equip_slot(0))
	_check(_shows_texture(slot_btn_icon), "Equip slot 1 shows the assigned spell's icon")
	_check(_shows_placeholder(_icon_in(_equip_slot(2))), "Equip empty slot 3 shows the placeholder")
	caster.clear_slot(0)
	await _frames(1)
	_check(_shows_placeholder(slot_btn_icon), "Equip slot 1 icon clears with the slot")
	_check(slot_btn_icon.size == Vector2(22, 22), "Equip slot icon area keeps its size when cleared")
	caster.assign_slot(0, lit)
	await _frames(1)
	_check(_shows_texture(slot_btn_icon), "Equip slot 1 icon returns on reassignment")
	equip.hide_panel()

	var shop: ShopPanel = main.get_node("ShopPanel")
	shop.open()
	await _frames(1)
	var stocked := shop.find_children("BuyButton", "Button", true, false)
	_check(stocked.size() >= 1, "Shop has a stocked row")
	if stocked.size() >= 1:
		var shop_icon := _icon_in(stocked[0].get_parent())
		_check(shop_icon != null and shop_icon.size == Vector2(22, 22), "Shop stocked row has a 22x22 icon area")

	print("[193] RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(1 if failures > 0 else 0)
