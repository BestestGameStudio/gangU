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

func _labels_without_suffix(hud: HUD) -> bool:
	for l: Label in hud.find_children("*", "Label", true, false):
		if l.text.find("[") != -1:
			return false
	return true

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

	# (a) no provider in tree: no suffix anywhere on the HUD.
	_check(_labels_without_suffix(hud), "(a) no HUD label carries a tier suffix without provider")

	# (b)-(c) #238: tier suffixes left the HUD; recorded tiers render nothing.
	var progress := SpellProgress.new()
	progress.name = "SpellProgress"
	root.add_child(progress)
	progress._tiers[spec] = 1
	progress._tiers[mast] = 2
	progress._tiers[sig] = 3
	# HUD discovers the provider on a 0.25s throttle; give it real frames.
	for i in range(120):
		await process_frame
	_check(_labels_without_suffix(hud), "(b) #238 recorded tiers add no HUD label suffix")
	_check(hud.find_children("*", "Label", true, false).size() == 2, "(c) #238 HUD text is only the HP and objective labels")

	# (d) slot icon identity survives the upgrade swap.
	var split := _spell("SplitBolt")
	var art := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	split.icon = ImageTexture.create_from_image(art)
	var slot_icon: SpellIcon = hud.get_node("Root/SpellGrid").get_child(0)
	_check(slot_icon.texture == SpellIcon.NO_ICON_TEXTURE and not slot_icon.get_node("Placeholder").visible, "(d) before swap the square shows the art-less spell (#257 placeholder sprite)")
	caster.fake_slots[0] = split
	caster.slot_assigned.emit(0, split)
	for i in range(5):
		await process_frame
	_check(slot_icon.texture == split.icon, "(d) square shows the upgraded spell's icon after swap")

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
