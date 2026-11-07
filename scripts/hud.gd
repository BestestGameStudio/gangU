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

var _objective: DungeonObjective
var _discover_elapsed := 0.0

## #10 slots slice (C): built only when the pinned slot API is present.
var _slots_supported := false
var _slot_widgets: Array = [] ## [{key,name,bar,state}] x 6

func _ready() -> void:
	if player_path != NodePath(""):
		_player = get_node_or_null(player_path) as Player
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null:
		push_warning("HUD: no player found (player_path unset, no 'player' group); HUD idle.")
		return
	_caster = _player.get_node_or_null("SpellCaster") as SpellCaster
	_player.health_changed.connect(_on_health_changed)
	_player.died.connect(_on_player_died)
	_on_health_changed(_player.hp, _player.max_hp)
	if _caster != null:
		_caster.cooldown_started.connect(_on_cooldown_started)
		_caster.spell_equipped.connect(_on_spell_equipped)
		_caster.spell_added.connect(_add_spell_row) # #10: rows follow runtime pickups
		for s in _caster.spells:
			_add_spell_row(s)
		# #10 slots slice (C): six fixed rows only when the pinned API exists.
		_slots_supported = _caster.has_method(&"get_slots")
		if _slots_supported:
			_build_slot_rows()

func _add_spell_row(spell: Spell) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
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
	_spell_rows_box.add_child(row)
	_spell_rows[spell] = {"name": name_label, "bar": bar, "state": state}

func _build_slot_rows() -> void:
	for i in 6:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
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
		_slot_rows_box.add_child(row)
		_slot_widgets.append({"key": key_label, "name": name_label, "bar": bar, "state": state})

func _update_slot_rows() -> void:
	var slots: Array = _caster.get_slots()
	for i in _slot_widgets.size():
		var w: Dictionary = _slot_widgets[i]
		var spell: Spell = slots[i] if i < slots.size() else null
		if spell == null:
			w["name"].text = "(empty)"
			w["bar"].value = 0.0
			w["state"].text = ""
			continue
		var rem: float = _caster.cooldown_remaining(spell)
		var frac := 1.0
		if spell.cooldown > 0.0:
			frac = 1.0 - clampf(rem / spell.cooldown, 0.0, 1.0)
		w["name"].text = spell.spell_name
		w["bar"].value = frac
		w["state"].text = "READY" if rem <= 0.0 else "%.1fs" % rem

func _process(delta: float) -> void:
	_update_objective(delta)
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
		row["name"].text = s.spell_name + (" *" if s == _caster.equipped_spell else "")
		row["bar"].value = frac
		row["state"].text = "READY" if rem <= 0.0 else "%.1fs" % rem

func _on_health_changed(current: int, max_hp: int) -> void:
	_hp_label.text = "HP %d/%d" % [current, max_hp]
	_hp_bar.max_value = max_hp
	_hp_bar.value = current

func _on_player_died() -> void:
	# Run restart is #6's job; the HUD only reflects the death state.
	_hp_label.text = "DEAD"

func _on_cooldown_started(_spell: Spell, _duration: float) -> void:
	pass # Bars update every frame in _process; hook kept for future flair.

func _on_spell_equipped(_spell: Spell) -> void:
	pass

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
