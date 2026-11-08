extends SceneTree
## #38 acceptance harness: HUD + equip-panel tier display (display-only slice).
## Fixture pattern follows test93: stub Player/Caster subclasses (typed so the
## HUD/panel casts pass; _ready/_process overrides skip gameplay wiring).
## Pins the lead UX call: compact ASCII suffix [S]/[M]/[G] for tiers 1/2/3,
## Base (0) shows nothing, read from SpellProgress.get_tier() (the #36 source
## of truth), rows keep their identity across the upgrade swap, and the
## equip-panel suffix appears in the UPGRADE CHANNEL ONLY (unlocked rows and
## slot buttons stay plain). Negative leg is run against the pre-change base
## by the reviewer (suffix assertions must FAIL there).

class StubPlayer extends Player:
	func _ready() -> void:
		hp = 100
		max_hp = 100
	func _process(_delta: float) -> void:
		pass # skip gameplay wiring
	func _init() -> void:
		# player.gd @onready lookups run even with _ready overridden.
		var aim := Node2D.new()
		aim.name = "AimIndicator"
		add_child(aim)
		var bod := Polygon2D.new()
		bod.name = "Body"
		add_child(bod)

class StubCaster extends SpellCaster:
	var fake_slots: Array[Spell] = []
	func _ready() -> void:
		pass # skip gameplay wiring
	func _process(_delta: float) -> void:
		pass # skip input polling (no InputMap actions headless)
	func cooldown_remaining(_spell: Spell) -> float:
		return 0.0
	func get_slots() -> Array[Spell]:
		return fake_slots

## Duck-typed upgrade provider for the panel leg (matches the panel's pinned
## contract: can_upgrade/get_upgrade_paths; no signals needed).
class StubUpgrader extends Node:
	var spell: Spell
	var paths: Array = []
	func can_upgrade(s: Spell) -> bool:
		return s == spell
	func get_upgrade_paths(s: Spell) -> Array:
		return paths if s == spell else []

var failures := 0
func _check(ok: bool, label: String) -> void:
	if ok:
		print("[38] ", label, " -> PASS")
	else:
		failures += 1
		print("[38] ", label, " -> FAIL")

func _spell(n: String) -> Spell:
	var s := Spell.new()
	s.spell_name = n
	s.cooldown = 1.0
	return s

func _row_label(hud: HUD, spell: Spell) -> Label:
	var rows: Dictionary = hud._spell_rows
	if not rows.has(spell):
		return null
	return rows[spell]["name"]

func _initialize() -> void:
	var hud_scene: PackedScene = load("res://scenes/hud.tscn")
	var player := StubPlayer.new()
	player.add_to_group("player")
	root.add_child(player)
	var caster := StubCaster.new()
	caster.name = "SpellCaster"
	player.add_child(caster)
	var base := _spell("BaseBolt")
	var spec := _spell("SpecBolt")
	var mast := _spell("MastBolt")
	var sig := _spell("SigBolt")
	caster.spells = [base, spec, mast, sig]
	caster.unlocked = [base, spec, mast, sig]
	caster.fake_slots = [spec, null, null, null, null, null]

	var hud := hud_scene.instantiate()
	root.add_child(hud)
	for i in range(5):
		await process_frame

	# (a) no provider in tree: names render plain (backward compatible).
	for s in [base, spec, mast, sig]:
		var l := _row_label(hud, s)
		_check(l != null, "(a) row exists for %s" % s.spell_name)
		if l != null:
			_check(l.text.find("[") == -1, "(a) no suffix without provider (got '%s')" % l.text)

	# (b) provider mounted: suffix per tier, Base shows nothing.
	var progress := SpellProgress.new()
	progress.name = "SpellProgress"
	root.add_child(progress)
	progress._tiers[spec] = 1
	progress._tiers[mast] = 2
	progress._tiers[sig] = 3
	# HUD discovers the provider on a 0.25s throttle; give it real frames.
	for i in range(120):
		await process_frame
	var lb := _row_label(hud, base)
	var ls := _row_label(hud, spec)
	var lm := _row_label(hud, mast)
	var lg := _row_label(hud, sig)
	_check(lb != null and lb.text.find("[") == -1, "(b) Base tier 0 shows nothing (got '%s')" % (lb.text if lb else "null"))
	_check(ls != null and ls.text.begins_with("SpecBolt [S]"), "(b) Specialization suffix [S] (got '%s')" % (ls.text if ls else "null"))
	_check(lm != null and lm.text.begins_with("MastBolt [M]"), "(b) Mastery suffix [M] (got '%s')" % (lm.text if lm else "null"))
	_check(lg != null and lg.text.begins_with("SigBolt [G]"), "(b) Signature suffix [G] (got '%s')" % (lg.text if lg else "null"))

	# (c) slot rows carry the same suffix (HUD spell rows are slot-keyed).
	var slot1_text: String = hud._slot_widgets[0]["name"].text
	_check(slot1_text.begins_with("SpecBolt [S]"), "(c) slot row carries tier suffix (got '%s')" % slot1_text)

	# (d) row survives the upgrade swap: same Label, suffix follows the
	# upgraded spell's recorded tier, no duplicate rows.
	var split := _spell("SplitBolt")
	var rows_before: int = hud._spell_rows.size()
	var label_before := ls
	progress._tiers.erase(spec)
	progress._tiers[split] = 2
	caster.spells[caster.spells.find(spec)] = split
	caster.spell_replaced.emit(spec, split)
	for i in range(5):
		await process_frame
	_check(not hud._spell_rows.has(spec), "(d) old spell key dropped after swap")
	_check(hud._spell_rows.has(split), "(d) row re-keyed to upgraded spell")
	_check(hud._spell_rows.size() == rows_before, "(d) row count unchanged (no duplicate)")
	if hud._spell_rows.has(split):
		var lnew := _row_label(hud, split)
		_check(lnew == label_before, "(d) stable row identity (same Label instance)")
		_check(lnew.text.begins_with("SplitBolt [M]"), "(d) suffix follows upgraded tier (got '%s')" % lnew.text)

	# (e) equip panel: tier suffix in the UPGRADE CHANNEL ONLY.
	var up1 := SpellUpgrade.new()
	up1.id = &"spec_split"
	up1.display_name = "Split shot"
	up1.source_spell = base
	up1.tier = 1
	var up2 := SpellUpgrade.new()
	up2.id = &"mast_beam"
	up2.display_name = "Beam"
	up2.source_spell = base
	up2.tier = 2
	var upgrader := StubUpgrader.new()
	upgrader.name = "StubUpgrader"
	upgrader.spell = base
	upgrader.paths = [up1, up2]
	root.add_child(upgrader)
	var panel: EquipPanel = load("res://scripts/equip_panel.gd").new()
	panel.upgrader_path = upgrader.get_path()
	root.add_child(panel)
	for i in range(5):
		await process_frame
	panel._on_spell_pressed(base)
	var buttons: Array = []
	for c in panel._upgrade_box.get_children():
		if c is Button:
			buttons.append(c)
	_check(buttons.size() == 2, "(e) two upgrade-channel buttons (got %d)" % buttons.size())
	if buttons.size() == 2:
		_check(buttons[0].text == "Split shot [S]", "(e) upgrade button carries [S] (got '%s')" % buttons[0].text)
		_check(buttons[1].text == "Beam [M]", "(e) upgrade button carries [M] (got '%s')" % buttons[1].text)
	# Unlocked rows stay plain: the suffix is upgrade-channel-only.
	var unlocked_plain := true
	for c in panel._unlocked_box.get_children():
		if c is Button and (c as Button).text.find("[") != -1:
			unlocked_plain = false
	_check(unlocked_plain, "(e) unlocked rows carry NO tier suffix")
	# Slot buttons stay plain too.
	var slots_plain := true
	for b in panel._slot_buttons:
		if (b as Button).text.find("[") != -1:
			slots_plain = false
	_check(slots_plain, "(e) slot buttons carry NO tier suffix")

	print("[38] DONE failures=%d" % failures)
	quit(1 if failures > 0 else 0)
