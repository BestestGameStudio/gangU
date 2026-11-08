extends CanvasLayer
class_name HUD
## gangU #11: player HUD - health, spells, cooldowns, objective.
## Objective slice consumes the merged #8 contract read-only: the production
## mount (main.gd) adds a node named "DungeonObjective" to the dungeon area
## AFTER the enemies. HUD boots before any objective exists and outlives area
## swaps, so it discovers that node lazily by exact name, connects its
## signals, and drops the reference when the swap frees it. No main.gd or
## dungeon_objective.gd changes; no fake objective data is rendered - the row
## stays hidden wherever no objective exists (hub, DungeonB).
##
## Isolated by design: this scene is self-contained and mounted by the scene
## that owns the player. Wiring into main.tscn is coordinated separately
## (Daniel's #6/#19/#20 scene windows) - mount by instancing scenes/hud.tscn
## and setting player_path, OR rely on the "player" group fallback.
##
## Consumed contracts (merged #3/#4/#5, no internals touched):
##   Player (scripts/player.gd): hp, max_hp, health_changed(current, max_hp),
##     died(), apply_damage() is the ONLY HP mutation point.
##   SpellCaster (scripts/spell_caster.gd): spells, equipped_spell,
##     cooldown_remaining(spell), cooldown_started(spell, duration),
##     spell_equipped(spell).
##   Spell (scripts/spell.gd): spell_name, cooldown.
##
## #10 slots slice (C): when the caster exposes the pinned slot API
## (get_slots(), size-6 nullable), renders six fixed slot rows (key 1-6,
## name, cooldown bar, state) under SlotRows. ADDITIVE and backward
## compatible: on a caster without get_slots() no slot rows are built and
## the HUD is byte-identical in behavior to the pre-slots version. Style
## (rows under the spell list, same fonts) is PROVISIONAL pending the open
## human style choice; no unlocked-inventory display here (panel scope).

## Set by the mounting scene. If unset, falls back to the "player" group.
@export var player_path: NodePath

var _player: Player
var _caster: SpellCaster
var _spell_rows := {} ## Spell -> {name: Label, bar: ProgressBar, state: Label}

@onready var _hp_label: Label = $Root/HPLabel
@onready var _hp_bar: ProgressBar = $Root/HPBar
@onready var _spell_rows_box: VBoxContainer = $Root/SpellRows
@onready var _slot_rows_box: VBoxContainer = $Root/SlotRows
@onready var _objective_label: Label = $Root/ObjectiveLabel
## #50: dark backing plate sized from the ACTUAL occupied rect of Root
## (runtime content: objective row, spell rows incl. long upgraded names,
## slot rows, viewport changes). Geometry under the plate is deliberately
## masked (lead UX choice); gates read reserved_rect() to keep their world
## labels out. Plate mouse_filter=IGNORE in the scene: click-through
## behavior in the HUD zone is unchanged.
@onready var _plate: ColorRect = $BackingPlate

var _objective: DungeonObjective
var _discover_elapsed := 0.0

## Upgrade-availability indicator (Daniel, 2026-11-07): an up arrow on
## the spell-name row when the provider reports a REAL qualified path.
## Read-only can_upgrade() polling inside the existing per-frame loop; the
## provider is discovered and validity-checked exactly like the objective
## node below. No provider changes, no new signals.
var _progress: Node = null
var _progress_elapsed := 0.0

## #10 slots slice (C): built only when the pinned slot API is present.
const PLATE_PAD := 8.0
## #93 visual identity: flat code-drawn styleboxes (no assets), neutral
## decoration + readable state colors. Labels, texts and data are unchanged.
const HP_GREEN := Color(0.35, 0.8, 0.4, 1.0)
const HP_AMBER := Color(0.95, 0.75, 0.25, 1.0)
const HP_RED := Color(0.9, 0.3, 0.25, 1.0)
const HP_AMBER_FRAC := 0.5
const HP_RED_FRAC := 0.25
const BAR_TRACK := Color(0.08, 0.08, 0.1, 0.9)
const BAR_READY := Color(0.8, 0.85, 0.95, 1.0)
const BAR_COOLING := Color(0.35, 0.45, 0.6, 0.9)
const FRAME_BG := Color(0.05, 0.05, 0.07, 0.55)
const FRAME_EQUIPPED := Color(0.85, 0.9, 1.0, 0.9)
const FRAME_ASSIGNED := Color(0.75, 0.8, 0.9, 0.8)
const FRAME_DIM := Color(0.45, 0.48, 0.55, 0.6)
const FRAME_EMPTY := Color(0.4, 0.42, 0.48, 0.6)
var _slots_supported := false
var _slot_widgets: Array = [] ## [{frame,key,name,bar,state,cooling}] x 6
var _style_track: StyleBoxFlat
var _style_ready: StyleBoxFlat
var _style_cooling: StyleBoxFlat
var _frame_cache := {} ## border Color -> StyleBoxFlat

func _bar_style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	for corner in ["corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_right", "corner_radius_bottom_left"]:
		sb.set(corner, 3)
	return sb

func _frame_style(border: Color) -> StyleBoxFlat:
	if _frame_cache.has(border):
		return _frame_cache[border]
	var sb := StyleBoxFlat.new()
	sb.bg_color = FRAME_BG
	sb.border_color = border
	for side in ["border_width_left", "border_width_top", "border_width_right", "border_width_bottom"]:
		sb.set(side, 1)
	for corner in ["corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_right", "corner_radius_bottom_left"]:
		sb.set(corner, 3)
	for m in ["content_margin_left", "content_margin_top", "content_margin_right", "content_margin_bottom"]:
		sb.set(m, 3.0)
	_frame_cache[border] = sb
	return sb

## #38: compact ASCII tier suffix for HUD spell rows. Reads the progression
## provider's get_tier() (#36 source of truth, recorded on successful apply);
## no provider, no accessor, or a Base tier (0) renders nothing. Display-only.
func _tier_suffix(spell: Spell) -> String:
	if not is_instance_valid(_progress) or not _progress.has_method("get_tier"):
		return ""
	match int(_progress.get_tier(spell)):
		1:
			return " [S]"
		2:
			return " [M]"
		3:
			return " [G]"
	return ""

func _apply_bar_state(bar: ProgressBar, cooling: bool) -> void:
	if _style_ready == null:
		return
	bar.add_theme_stylebox_override("background", _style_track)
	bar.add_theme_stylebox_override("fill", _style_cooling if cooling else _style_ready)

func _ready() -> void:
	if player_path != NodePath(""):
		_player = get_node_or_null(player_path) as Player
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null:
		push_warning("HUD: no player found (player_path unset, no 'player' group); HUD idle.")
		return
	_caster = _player.get_node_or_null("SpellCaster") as SpellCaster
	_style_track = _bar_style(BAR_TRACK)
	_style_ready = _bar_style(BAR_READY)
	_style_cooling = _bar_style(BAR_COOLING)
	_player.health_changed.connect(_on_health_changed)
	_player.died.connect(_on_player_died)
	_on_health_changed(_player.hp, _player.max_hp)
	get_viewport().size_changed.connect(_update_plate)
	if _caster != null:
		_caster.cooldown_started.connect(_on_cooldown_started)
		_caster.spell_equipped.connect(_on_spell_equipped)
		_caster.spell_added.connect(_add_spell_row) # #10: rows follow runtime pickups
		if _caster.has_signal(&"spell_replaced"):
			_caster.spell_replaced.connect(_on_spell_replaced) # rows track upgrades (#67)
		for s in _caster.spells:
			_add_spell_row(s)
		# #10 slots slice (C): six fixed rows only when the pinned API exists.
		_slots_supported = _caster.has_method(&"get_slots")
		if _slots_supported:
			_build_slot_rows()
			if _caster.has_signal(&"slot_assigned"):
				_caster.slot_assigned.connect(func(_i, _s): _update_slot_rows())
			if _caster.has_signal(&"slot_cleared"):
				_caster.slot_cleared.connect(func(_i): _update_slot_rows())

func _add_spell_row(spell: Spell) -> void:
	var frame := PanelContainer.new() # #93: flat border frame; border highlights equipped
	frame.add_theme_stylebox_override("panel", _frame_style(FRAME_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	frame.add_child(row)
	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.custom_minimum_size = Vector2(120, 0)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(140, 18)
	var state := Label.new()
	state.add_theme_font_size_override("font_size", 22)
	row.add_child(name_label)
	row.add_child(bar)
	row.add_child(state)
	_apply_bar_state(bar, false) # #93: track + READY fill at build
	_spell_rows_box.add_child(frame)
	_spell_rows[spell] = {"name": name_label, "bar": bar, "state": state, "frame": frame, "cooling": false, "equipped": false}
	_update_plate.call_deferred() # #93: settle containers, then re-mask (avoids one-frame gate/HUD clip)

func _build_slot_rows() -> void:
	for i in 6:
		var frame := PanelContainer.new() # #93: flat border frame; border shows assigned vs empty
		frame.add_theme_stylebox_override("panel", _frame_style(FRAME_EMPTY))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		frame.add_child(row)
		var key_label := Label.new()
		key_label.add_theme_font_size_override("font_size", 22)
		key_label.custom_minimum_size = Vector2(24, 0)
		key_label.text = str(i + 1)
		var name_label := Label.new()
		name_label.add_theme_font_size_override("font_size", 22)
		name_label.custom_minimum_size = Vector2(120, 0)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = 0.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(140, 18)
		var state := Label.new()
		state.add_theme_font_size_override("font_size", 22)
		row.add_child(key_label)
		row.add_child(name_label)
		row.add_child(bar)
		row.add_child(state)
		_apply_bar_state(bar, false) # #93: track + READY fill at build
		_slot_rows_box.add_child(frame)
		_slot_widgets.append({"frame": frame, "key": key_label, "name": name_label, "bar": bar, "state": state, "cooling": false})
	_update_plate.call_deferred()

func _update_slot_rows() -> void:
	# Freed-instance safe: the caster can die with the run (reload rebuilds
	# the HUD, but signal timing can race); null slots are the normal empty
	# state. Mirrors the objective-discovery validity pattern.
	if not is_instance_valid(_caster):
		_slots_supported = false
		return
	var slots: Array = _caster.get_slots()
	for i in _slot_widgets.size():
		var w: Dictionary = _slot_widgets[i]
		var spell: Spell = slots[i] if i < slots.size() else null
		if spell != null and not is_instance_valid(spell):
			spell = null
		if spell == null:
			w["name"].text = "(empty)"
			w["bar"].value = 0.0
			w["state"].text = ""
			w["frame"].add_theme_stylebox_override("panel", _frame_style(FRAME_EMPTY))
			if w["cooling"]:
				w["cooling"] = false
				_apply_bar_state(w["bar"], false)
			continue
		var rem: float = _caster.cooldown_remaining(spell)
		var frac := 1.0
		if spell.cooldown > 0.0:
			frac = 1.0 - clampf(rem / spell.cooldown, 0.0, 1.0)
		w["name"].text = spell.spell_name + _tier_suffix(spell)
		w["bar"].value = frac
		w["state"].text = "READY" if rem <= 0.0 else "%.1fs" % rem
		w["frame"].add_theme_stylebox_override("panel", _frame_style(FRAME_ASSIGNED))
		var cooling := rem > 0.0
		if cooling != w["cooling"]:
			w["cooling"] = cooling
			_apply_bar_state(w["bar"], cooling)

func _process(delta: float) -> void:
	_update_objective(delta)
	_update_progress(delta)
	_update_plate()
	if _caster == null:
		return
	if _slots_supported:
		_update_slot_rows()
	for s in _spell_rows.keys():
		var row: Dictionary = _spell_rows[s]
		var rem: float = _caster.cooldown_remaining(s)
		var frac := 1.0
		if s.cooldown > 0.0:
			frac = 1.0 - clampf(rem / s.cooldown, 0.0, 1.0)
		var up_arrow := ""
		if _progress != null and _progress.has_method("can_upgrade") and _progress.can_upgrade(s):
			up_arrow = " ^"
		row["name"].text = s.spell_name + _tier_suffix(s) + (" *" if s == _caster.equipped_spell else "") + up_arrow
		row["bar"].value = frac
		row["state"].text = "READY" if rem <= 0.0 else "%.1fs" % rem
		var cooling := rem > 0.0
		if cooling != row["cooling"]:
			row["cooling"] = cooling
			_apply_bar_state(row["bar"], cooling)
		var equipped: bool = s == _caster.equipped_spell
		if equipped != row["equipped"]:
			row["equipped"] = equipped
			row["frame"].add_theme_stylebox_override("panel", _frame_style(FRAME_EQUIPPED if equipped else FRAME_DIM))

func _on_health_changed(current: int, max_hp: int) -> void:
	_hp_label.text = "HP %d/%d" % [current, max_hp]
	_hp_bar.max_value = max_hp
	_hp_bar.value = current
	# #93: HP state color - green -> amber -> red as the fraction drops.
	var fill := _hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null:
		var frac := 0.0
		if max_hp > 0:
			frac = clampf(float(current) / float(max_hp), 0.0, 1.0)
		fill.bg_color = HP_GREEN if frac > HP_AMBER_FRAC else (HP_AMBER if frac > HP_RED_FRAC else HP_RED)

func _on_player_died() -> void:
	# Run restart is #6's job; the HUD only reflects the death state.
	_hp_label.text = "DEAD"

func _on_cooldown_started(_spell: Spell, _duration: float) -> void:
	pass # Bars update every frame in _process; hook kept for future flair.

func _on_spell_equipped(_spell: Spell) -> void:
	pass

## Legacy rows follow replace_spell (#67): re-key the row to the new resource
## so the name, cooldown bar and equipped marker track the swap instead of
## going stale (review finding on the C fixture). Unlock-only replacements
## (old never in the legacy list) have no row to re-key and stay unlisted.
func _on_spell_replaced(old_spell: Spell, new_spell: Spell) -> void:
	if not _spell_rows.has(old_spell):
		return
	_spell_rows[new_spell] = _spell_rows[old_spell]
	_spell_rows.erase(old_spell)

## Upgrade indicator: cached discovery of the mounted SpellProgress provider.
## Mirrors _update_objective: is_instance_valid guard (freed providers compare
## non-null), throttled exact-name search, no per-frame tree scan.
func _update_progress(delta: float) -> void:
	if is_instance_valid(_progress):
		return
	_progress = null
	_progress_elapsed += delta
	if _progress_elapsed < 0.25:
		return
	_progress_elapsed = 0.0
	_progress = get_tree().root.find_child("SpellProgress", true, false)


## #11 objective slice: lazy discovery of the mounted DungeonObjective.
## Throttled search; the node only exists while a dungeon with an objective
## is the current area.
func _update_objective(delta: float) -> void:
	# Note: a freed objective compares == null in GDScript, so validity must
	# be checked with is_instance_valid, not a null comparison.
	if is_instance_valid(_objective):
		return
	_objective = null # never held, or the area swap freed it
	_objective_label.visible = false
	_discover_elapsed += delta
	if _discover_elapsed < 0.25:
		return
	_discover_elapsed = 0.0
	var found := get_tree().root.find_child("DungeonObjective", true, false) as DungeonObjective
	if found == null:
		return
	_objective = found
	_objective.objective_progress_changed.connect(_on_objective_progress)
	_objective.objective_completed.connect(_on_objective_completed)
	var p := _objective.progress()
	_show_objective(p.x, p.y)

func _show_objective(current: int, target: int) -> void:
	_objective_label.text = "Objective: CLEAR ALL %d/%d" % [current, target]
	_objective_label.visible = true

func _on_objective_progress(current: int, target: int) -> void:
	_show_objective(current, target)

func _on_objective_completed(_dungeon_id: StringName) -> void:
	_objective_label.text = "Objective: COMPLETE"
	_objective_label.visible = true

## #50: union of every visible Root descendant rect, extended for text that
## renders wider than its control box (long spell names), plus padding.
## Runs every frame after the row updates above; a handful of controls, no
## tree scan. CanvasLayer space == screen space.
func _update_plate() -> void:
	if _plate == null:
		return
	var rect := Rect2()
	var first := true
	for c: Control in $Root.find_children("*", "Control", true, false):
		if not c.visible:
			continue
		var r := c.get_global_rect()
		if c is Label:
			var font := c.get_theme_font("font")
			var fs := c.get_theme_font_size("font_size")
			if font != null and c.text != "":
				var ts := font.get_string_size(c.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				r.size.x = maxf(r.size.x, ts.x)
				r.size.y = maxf(r.size.y, ts.y)
		rect = r if first else rect.merge(r)
		first = false
	if first:
		rect = Rect2($Root.position, Vector2(388, 40))
	rect = rect.grow(PLATE_PAD)
	_plate.position = rect.position
	_plate.size = rect.size
	_plate.visible = true

## #50: screen-space rect other UI/world labels must keep clear of.
func reserved_rect() -> Rect2:
	if _plate == null:
		return Rect2()
	return Rect2(_plate.position, _plate.size)
