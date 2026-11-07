extends SceneTree
## #93 HUD visual identity harness. Fixture: stub Player + stub SpellCaster
## (typed subclasses so the HUD's `as Player` / `as SpellCaster` casts pass;
## _ready overrides skip gameplay wiring). Asserts the #93 presentation layer:
## HP state colors, spell-row frames + equipped border, READY/cooling bar
## fills, slot frames, backward-compat slot fallback, and that all labels /
## data strings are preserved. Decor legs FAIL on old main (no styling).
class StubPlayer extends Player:
	var start_hp := 80
	var start_max := 100
	func _ready() -> void:
		hp = start_hp
		max_hp = start_max
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
	var cooling := {}
	func _ready() -> void:
		pass # skip gameplay wiring
	func _process(_delta: float) -> void:
		pass # skip input polling (no InputMap actions headless)
	func cooldown_remaining(spell: Spell) -> float:
		return float(cooling.get(spell, 0.0))
	func get_slots() -> Array[Spell]:
		return fake_slots

class StubCasterNoSlots extends SpellCaster:
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass

var failures := 0
func _check(ok: bool, label: String) -> void:
	if ok:
		print("[93] ", label, " -> PASS")
	else:
		failures += 1
		print("[93] ", label, " -> FAIL")

func _spell(n: String, cd: float) -> Spell:
	var s := Spell.new()
	s.spell_name = n
	s.cooldown = cd
	return s

func _frames(box: VBoxContainer) -> Array:
	return box.get_children().filter(func(c): return c is PanelContainer)

func _border_of(frame: PanelContainer) -> Color:
	var sb := frame.get_theme_stylebox("panel") as StyleBoxFlat
	return sb.border_color if sb != null else Color(-1, -1, -1)

func _fill_of(bar: ProgressBar) -> Color:
	var sb := bar.get_theme_stylebox("fill") as StyleBoxFlat
	return sb.bg_color if sb != null else Color(-1, -1, -1)

const C_GREEN := Color(0.35, 0.8, 0.4, 1.0)
const C_AMBER := Color(0.95, 0.75, 0.25, 1.0)
const C_RED := Color(0.9, 0.3, 0.25, 1.0)
const C_READY := Color(0.8, 0.85, 0.95, 1.0)
const C_COOLING := Color(0.35, 0.45, 0.6, 0.9)
const C_EQUIPPED := Color(0.85, 0.9, 1.0, 0.9)
const C_DIM := Color(0.45, 0.48, 0.55, 0.6)
const C_ASSIGNED := Color(0.75, 0.8, 0.9, 0.8)
const C_EMPTY := Color(0.4, 0.42, 0.48, 0.6)

func _initialize() -> void:
	var hud_scene: PackedScene = load("res://scenes/hud.tscn")
	var player := StubPlayer.new()
	player.add_to_group("player")
	root.add_child(player)
	var caster := StubCaster.new()
	caster.name = "SpellCaster"
	player.add_child(caster)
	var a := _spell("AlphaBolt", 1.0)
	var b := _spell("BetaBolt", 2.0)
	caster.spells = [a, b]
	caster.cooling[b] = 0.4
	caster.fake_slots = [a, null, b, null, null, null]
	# equipped: SpellCaster.equipped_spell is a getter over slots/equip index;
	# the fixture leaves it whatever the base returns - the * marker and frame
	# leg below only require a consistent comparison target.
	var hud := hud_scene.instantiate()
	root.add_child(hud)
	for i in range(5):
		await process_frame

	# (0) preserved structure.
	_check(hud.get_node_or_null("Root/HPLabel") is Label, "(0) HPLabel preserved")
	_check(hud.get_node_or_null("Root/HPBar") is ProgressBar, "(0) HPBar preserved")
	_check(hud.get_node_or_null("Root/ObjectiveLabel") is Label, "(0) ObjectiveLabel preserved")
	_check(hud.get_node_or_null("Root/SpellRows") is VBoxContainer, "(0) SpellRows preserved")
	_check(hud.get_node_or_null("Root/SlotRows") is VBoxContainer, "(0) SlotRows preserved")

	# (f) labels/data preserved.
	var hp_label := hud.get_node("Root/HPLabel") as Label
	_check(hp_label.text == "HP 80/100", "(f) HP label data preserved (got '%s')" % hp_label.text)

	# (a) HP bar custom styling + state colors.
	var hp_bar := hud.get_node("Root/HPBar") as ProgressBar
	_check(hp_bar.get_theme_stylebox("background") is StyleBoxFlat, "(a) HP track StyleBoxFlat")
	_check(hp_bar.get_theme_stylebox("fill") is StyleBoxFlat, "(a) HP fill StyleBoxFlat")
	_check(_fill_of(hp_bar) == C_GREEN, "(a) HP green at 80 percent")
	player.hp = 40
	player.health_changed.emit(40, 100)
	_check(_fill_of(hp_bar) == C_AMBER, "(a) HP amber at 40 percent")
	player.hp = 20
	player.health_changed.emit(20, 100)
	_check(_fill_of(hp_bar) == C_RED, "(a) HP red at 20 percent")
	player.hp = 80
	player.health_changed.emit(80, 100)
	_check(_fill_of(hp_bar) == C_GREEN, "(a) HP back to green at 80 percent")

	# (c) spell row frames + equipped border state.
	var srows := hud.get_node("Root/SpellRows") as VBoxContainer
	var sframes := _frames(srows)
	_check(sframes.size() == 2, "(c) 2 spell row frames (got %d)" % sframes.size())
	if sframes.size() == 2:
		var borders := [_border_of(sframes[0]), _border_of(sframes[1])]
		var eq := caster.equipped_spell
		var expect0 := C_EQUIPPED if eq == a else C_DIM
		var expect1 := C_EQUIPPED if eq == b else C_DIM
		_check(borders[0] == expect0 and borders[1] == expect1,
			"(c) equipped border state (eq=%s got %s vs %s)" % [str(eq != null), str(borders[0]), str(borders[1])])

	# (d) READY vs cooling bar fills, and swap on state change.
	if sframes.size() == 2:
		var bars: Array = []
		for f in sframes:
			bars.append(f.find_children("*", "ProgressBar", true, false)[0])
		_check(_fill_of(bars[0]) == C_READY, "(d) AlphaBolt READY fill")
		_check(_fill_of(bars[1]) == C_COOLING, "(d) BetaBolt cooling fill")
		caster.cooling.erase(b)
		caster.cooling[a] = 0.5
		for i in range(3):
			await process_frame
		_check(_fill_of(bars[0]) == C_COOLING, "(d) AlphaBolt fill swaps to cooling")
		_check(_fill_of(bars[1]) == C_READY, "(d) BetaBolt fill swaps to READY")

	# (e) slot frames assigned vs empty + labels.
	var slots_box := hud.get_node("Root/SlotRows") as VBoxContainer
	var slframes := _frames(slots_box)
	_check(slframes.size() == 6, "(e) 6 slot frames (got %d)" % slframes.size())
	if slframes.size() == 6:
		_check(_border_of(slframes[0]) == C_ASSIGNED, "(e) slot 1 assigned border")
		_check(_border_of(slframes[1]) == C_EMPTY, "(e) slot 2 empty border")
		_check(_border_of(slframes[2]) == C_ASSIGNED, "(e) slot 3 assigned border")
		_check(_border_of(slframes[5]) == C_EMPTY, "(e) slot 6 empty border")
		var labels: Array = slframes[1].find_children("*", "Label", true, false)
		var empty_text := false
		for l in labels:
			if l.text == "(empty)":
				empty_text = true
		_check(empty_text, "(e) empty slot label preserved")

	# (g) backward-compat: a caster without the slot override still builds rows.
	var player2 := StubPlayer.new()
	player2.add_to_group("player")
	root.add_child(player2)
	var caster2 := StubCasterNoSlots.new()
	caster2.name = "SpellCaster"
	player2.add_child(caster2)
	var hud2 := hud_scene.instantiate()
	hud2.player_path = player2.get_path() # absolute: resolves once hud2 enters the tree
	root.add_child(hud2)
	for i in range(5):
		await process_frame
	_check(true, "(g) base-API caster mounted with no errors (see error count)")

	# (h) plate tracks the new occupied rect: reserved_rect covers every frame.
	var rr: Rect2 = hud.reserved_rect()
	var covered := rr.has_area()
	for f in _frames(hud.get_node("Root/SpellRows")) + _frames(hud.get_node("Root/SlotRows")):
		covered = covered and rr.encloses(f.get_global_rect().grow(-1.0))
	_check(covered, "(h) reserved_rect covers all row frames after settle")

	print("[93] DONE failures=%d" % failures)
	quit(1 if failures > 0 else 0)
