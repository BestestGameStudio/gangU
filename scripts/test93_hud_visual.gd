extends SceneTree
## #93 / #238 HUD visual identity harness. Fixture: stub Player + stub
## SpellCaster (typed subclasses so the HUD's `as Player` / `as SpellCaster`
## casts pass; _ready overrides skip gameplay wiring). Asserts the HP state
## colors and live text inside a bare bar, the bare 3x2 slot grid, removal of
## the old rows/plate, and the geometry pins.
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

func _fill_of(bar: ProgressBar) -> Color:
	var sb := bar.get_theme_stylebox("fill") as StyleBoxTexture
	return sb.modulate_color if sb != null else Color(-1, -1, -1)

const C_GREEN := Color(0.17, 1.0, 0.14, 1.0)
const C_AMBER := Color(0.95, 0.75, 0.25, 1.0)
const C_RED := Color(0.9, 0.3, 0.25, 1.0)

func _initialize() -> void:
	var hud_scene: PackedScene = load("res://scenes/hud.tscn")
	var player := StubPlayer.new()
	player.add_to_group(PhysicsLayers.PLAYER_GROUP)
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

	# (0) #238 structure.
	_check(hud.get_node_or_null("Root/HPBar/HPLabel") is Label, "(0) HPLabel inside HPBar")
	_check(hud.get_node_or_null("Root/HPBar") is ProgressBar, "(0) HPBar preserved")
	_check(hud.get_node_or_null("Root/ObjectiveLabel") is Label, "(0) ObjectiveLabel preserved")
	_check(hud.get_node_or_null("Root/SpellGrid") is GridContainer, "(0) SpellGrid present")
	for removed in ["BackingPlate", "Root/SpellRows", "Root/SlotRows"]:
		_check(hud.get_node_or_null(removed) == null, "(0) %s removed" % removed)

	# (f) live current/max text, no prefix.
	var hp_label := hud.get_node("Root/HPBar/HPLabel") as Label
	_check(hp_label.text == "80/100", "(f) HP label is live current/max (got '%s')" % hp_label.text)

	# (a) HP bar custom styling + state colors.
	var hp_bar := hud.get_node("Root/HPBar") as ProgressBar
	var track_style := hp_bar.get_theme_stylebox("background") as StyleBoxTexture
	var fill_style := hp_bar.get_theme_stylebox("fill") as StyleBoxTexture
	_check(track_style != null and track_style.texture != null, "(a) HP track is textured")
	_check(fill_style != null and fill_style.texture != null, "(a) HP fill is textured")
	_check(track_style.get_margin(SIDE_LEFT) > 0.0 and fill_style.get_margin(SIDE_RIGHT) > 0.0, "(a) HP track and fill keep fixed end caps")
	_check(track_style.axis_stretch_horizontal == StyleBoxTexture.AXIS_STRETCH_MODE_TILE and fill_style.axis_stretch_horizontal == StyleBoxTexture.AXIS_STRETCH_MODE_TILE, "(a) HP track and fill tile their middles")
	var fill_image := fill_style.texture.get_image()
	if fill_image.is_compressed():
		fill_image.decompress()
	var fill_sample := fill_image.get_pixel(fill_image.get_width() / 2, fill_image.get_height() / 2)
	_check(fill_sample.a > 0.9 and is_equal_approx(fill_sample.r, fill_sample.b) and fill_sample.g > 0.4, "(a) fill art is a bright untinted value map (got %s)" % str(fill_sample))
	var hp_frame := hud.get_node_or_null("Root/HPBar/HPFrame") as NinePatchRect
	_check(hp_frame != null and hp_frame.texture != null and hp_frame.patch_margin_left > 0 and hp_frame.patch_margin_right > 0, "(a) HP frame is a nine-patch with fixed ends")
	_check(hp_frame != null and hp_frame.mouse_filter == Control.MOUSE_FILTER_IGNORE, "(a) HP frame ignores the mouse")
	_check(hud.get_node("Root/HPBar").get_children().find(hp_frame) < hud.get_node("Root/HPBar").get_children().find(hp_label), "(a) HP text draws above the frame")
	_check(_fill_of(hp_bar) == C_GREEN, "(a) HP green at 80 percent")
	player.hp = 40
	player.health_changed.emit(40, 100)
	_check(_fill_of(hp_bar) == C_AMBER, "(a) HP amber at 40 percent")
	_check(hp_label.text == "40/100", "(f) HP text follows damage (got '%s')" % hp_label.text)
	player.hp = 20
	player.health_changed.emit(20, 100)
	_check(_fill_of(hp_bar) == C_RED, "(a) HP red at 20 percent")
	player.hp = 80
	player.health_changed.emit(80, 100)
	_check(_fill_of(hp_bar) == C_GREEN, "(a) HP back to green at 80 percent")

	# (c) #238: squares are bare - nothing but the six icons in the grid.
	var grid := hud.get_node("Root/SpellGrid") as GridContainer
	_check(grid.columns == 3, "(c) grid is 3 columns")
	_check(grid.get_child_count() == 6, "(c) 6 squares built (got %d)" % grid.get_child_count())
	_check(grid.get_children().all(func(c): return c is SpellIcon), "(c) every square is a bare SpellIcon")
	_check(grid.find_children("*", "Label", true, false).is_empty(), "(c) no name/state/key text")
	_check(grid.find_children("*", "ProgressBar", true, false).is_empty(), "(c) no cooldown bars")
	_check(grid.find_children("*", "PanelContainer", true, false).is_empty(), "(c) no row frames")

	# (d) wipe state follows the caster's cooldown; empty squares never wipe.
	var squares := grid.get_children()
	_check(not squares[0].get_node("CooldownWipe").visible, "(d) AlphaBolt ready: no wipe")
	_check(squares[2].get_node("CooldownWipe").visible, "(d) BetaBolt cooling: wipe shown")
	_check(not squares[1].get_node("CooldownWipe").visible, "(d) empty square: no wipe")
	caster.cooling.erase(b)
	caster.cooling[a] = 0.5
	for i in range(3):
		await process_frame
	_check(squares[0].get_node("CooldownWipe").visible, "(d) AlphaBolt wipe appears on cooldown")
	_check(not squares[2].get_node("CooldownWipe").visible, "(d) BetaBolt wipe clears when ready")

	# (e) empty slots keep a placeholder square; assignments follow the caster.
	for i in [1, 3, 4, 5]:
		_check(squares[i].visible and squares[i].get_node("Placeholder").visible, "(e) empty square %d shows placeholder" % (i + 1))
	caster.fake_slots = [null, null, null, null, null, null]
	for i in range(3):
		await process_frame
	_check(squares.all(func(c): return c.visible and c.get_node("Placeholder").visible), "(e) zero assigned: all squares stay as placeholders")
	_check(not squares[0].get_node("CooldownWipe").visible, "(e) zero assigned: cooling spell's wipe is gone")
	caster.fake_slots = [a, null, b, null, null, null]
	for i in range(3):
		await process_frame
	_check(squares[0].get_node("CooldownWipe").visible, "(e) reassign: square follows the caster again")

	# (g) backward-compat: a caster without the slot override still builds rows.
	var player2 := StubPlayer.new()
	player2.add_to_group(PhysicsLayers.PLAYER_GROUP)
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

	# (h) reserved_rect is computed from the real content.
	var rr: Rect2 = hud.reserved_rect()
	var covered := rr.has_area()
	for c in [hp_bar] + squares:
		covered = covered and rr.encloses(c.get_global_rect())
	_check(covered, "(h) reserved_rect covers the HP bar and every square")

	# (i) #238 geometry pins.
	var root_box := hud.get_node("Root") as VBoxContainer
	_check(root_box.offset_right == 372.0, "(i) Root width 360 (offset_right got %s)" % str(root_box.offset_right))
	_check(root_box.get_theme_constant("separation") == 8, "(i) Root separation 8")
	_check(hp_label.get_theme_font_size("font_size") == 18, "(i) HPLabel font 18")
	_check(hp_bar.custom_minimum_size == Vector2(360, 60), "(i) HPBar 360x60 (got %s)" % str(hp_bar.custom_minimum_size))
	var obj_label := hud.get_node("Root/ObjectiveLabel") as Label
	_check(obj_label.get_theme_font_size("font_size") == 16, "(i) ObjectiveLabel font 16")
	_check(squares[0].custom_minimum_size == Vector2(48, 48), "(i) squares are 48x48")

	print("[93] DONE failures=%d" % failures)
	quit(1 if failures > 0 else 0)
