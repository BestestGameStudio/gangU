extends SceneTree
## #417 (Daniel, 2026-11-09): the Tab menu no longer shows the bottom
## "Selected: <spell>" / "Selected: none" status line. Everything else the
## selection drives is unchanged: the slot highlight, the stat grid title
## (spell name instead of "Stats"), the description and the upgrade section.
## Fixture: same stub Player / SpellCaster / upgrader shape as test375.
## Run: godot --headless --path . -s scripts/test417_no_selected_status.gd
## Rendered run: pass `-- --shot=<dir>` to save the open menu as PNGs.

class StubPlayer extends Player:
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass
	func _init() -> void:
		var aim := Node2D.new()
		aim.name = "AimIndicator"
		add_child(aim)
		var bod := Polygon2D.new()
		bod.name = "Body"
		add_child(bod)

class StubCaster extends SpellCaster:
	var fake_unlocked: Array[Spell] = []
	var fake_slots: Array[Spell] = [null, null, null, null, null, null]
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass
	func get_unlocked() -> Array[Spell]:
		return fake_unlocked.duplicate()
	func get_slots() -> Array[Spell]:
		return fake_slots.duplicate()

class StubUpgrader extends Node:
	signal upgrades_changed(spell)
	var upgradeable: Array[Spell] = []
	func can_upgrade(spell: Spell) -> bool:
		return upgradeable.has(spell)
	func get_upgrade_paths(_spell: Spell) -> Array:
		return [{"id": "p1", "display_name": "Path One"}]
	func apply_upgrade(_spell: Spell, _path_id) -> bool:
		return true

var failures := 0
var _shot_dir := ""

func _check(ok: bool, label: String) -> void:
	if ok:
		print("[417] ", label, " -> PASS")
	else:
		failures += 1
		print("[417] ", label, " -> FAIL")

## Every Label/Button text in the open panel that starts with "Selected".
func _selected_texts(panel: Node) -> Array:
	var found: Array = []
	for n in panel.find_children("*", "", true, false):
		var t := ""
		if n is Label:
			t = (n as Label).text
		elif n is Button:
			t = (n as Button).text
		if t.strip_edges().begins_with("Selected"):
			found.append(t)
	return found

func _shot(name: String) -> void:
	if _shot_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png(_shot_dir.path_join(name))
	print("[417] saved ", name)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_dir = arg.trim_prefix("--shot=")
	var player := StubPlayer.new()
	player.add_to_group("player")
	root.add_child(player)
	var caster := StubCaster.new()
	caster.name = "SpellCaster"
	player.add_child(caster)
	var upg := StubUpgrader.new()
	upg.name = "UpgraderStub"
	root.add_child(upg)
	var fire: Spell = load("res://resources/spells/fire_ball.tres") if ResourceLoader.exists("res://resources/spells/fire_ball.tres") else Spell.new()
	if fire.spell_name.is_empty():
		fire.spell_name = "AlphaBolt"
	var beta := Spell.new()
	beta.spell_name = "BetaBolt"
	caster.fake_unlocked = [fire, beta]
	caster.fake_slots = [fire, beta, null, null, null, null]
	upg.upgradeable = [beta]
	var panel: EquipPanel = load("res://scenes/equip_panel.tscn").instantiate()
	panel.upgrader_path = NodePath("../UpgraderStub")
	root.add_child(panel)
	for i in range(5):
		await process_frame
	panel.show_panel()
	for i in range(2):
		await process_frame

	var vbox: VBoxContainer = null
	for c in panel.find_children("*", "VBoxContainer", true, false):
		if c.get_parent() is PanelContainer:
			vbox = c
	var grid := panel.find_child("StatsBox", true, false) as StatGrid

	# (1) Nothing selected: no "Selected: none" line; the upgrade box is now
	# the last row of the panel (title, columns, upgrades).
	_check(_selected_texts(panel).is_empty(), "(1) no 'Selected' text with nothing selected (got %s)" % str(_selected_texts(panel)))
	_check(vbox != null and vbox.get_child_count() == 3, "(1) panel rows: title + columns + upgrades (got %d)" % (vbox.get_child_count() if vbox != null else -1))
	_check(vbox != null and vbox.get_child(vbox.get_child_count() - 1) == panel._upgrade_box, "(1) upgrade box is the last row")
	_check(grid.title() == "Stats", "(1) stat grid shows player stats")
	await _shot("tab_menu_nothing_selected.png")

	# (2) Select a slotted spell: still no status line, but the selection is
	# shown by the slot highlight and the stat grid title.
	panel._on_slot_pressed(0)
	await process_frame
	_check(panel._selected == fire, "(2) slot click selects its spell")
	_check(_selected_texts(panel).is_empty(), "(2) no 'Selected: <spell>' text (got %s)" % str(_selected_texts(panel)))
	_check(grid.title() == fire.spell_name, "(2) stat grid title is the spell name (got '%s')" % grid.title())
	_check(grid.description() == SpellDescription.for_spell(fire), "(2) spell description kept")
	_check(panel._slot_buttons[0].text == "LMB: %s" % fire.spell_name, "(2) slot label kept (got '%s')" % panel._slot_buttons[0].text)
	await _shot("tab_menu_spell_selected.png")

	# (3) Select an upgradeable spell: upgrade section still renders and is
	# still the last row; no status line under it.
	panel._on_slot_pressed(0) # deselect
	await process_frame
	panel._on_slot_pressed(1)
	await process_frame
	var uh := panel._upgrade_box.get_child(0) as Label if panel._upgrade_box.get_child_count() > 0 else null
	_check(uh != null and uh.text == "Upgrades", "(3) upgrade section still renders")
	_check(_selected_texts(panel).is_empty(), "(3) no 'Selected' text with upgrades shown")
	_check(vbox.get_child(vbox.get_child_count() - 1) == panel._upgrade_box, "(3) nothing below the upgrade section")

	# (4) Deselect: still no text.
	panel._on_slot_pressed(1)
	await process_frame
	_check(panel._selected == null and _selected_texts(panel).is_empty(), "(4) deselect leaves no 'Selected: none' text")

	print("[417] failures=%d" % failures)
	if failures > 0:
		print("[417] FAILURES PRESENT")
	else:
		print("[417] ALL PASS")
	quit(failures)
