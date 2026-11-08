extends CanvasLayer
class_name HUD
## gangU #11 / #238: player HUD - a bare HP bar, a 3x2 grid of spell squares
## mirroring the six equip slots, and the objective row.
##
## Objective slice consumes the merged #8 contract read-only: the production
## mount (main.gd) adds a node named "DungeonObjective" to the dungeon area
## AFTER the enemies. HUD boots before any objective exists and outlives area
## swaps, so it discovers that node lazily by exact name, connects its
## signals, and drops the reference when the swap frees it. No fake objective
## data is rendered - the row stays hidden wherever no objective exists (the
## hub).
##
## Self-contained: mounted by the scene that owns the player, by instancing
## scenes/hud.tscn and setting player_path, OR via the "player" group
## fallback.
##
## Consumed contracts:
##   Player: hp, max_hp, health_changed(current, max_hp), died().
##   SpellCaster: get_slots(), cooldown_remaining(spell), polled every frame.
##   Spell: cooldown.
##   SpellProgress (discovered by name): can_upgrade(spell).

## Set by the mounting scene. If unset, falls back to the "player" group.
@export var player_path: NodePath

const RESERVED_PAD := 8.0
const SLOT_SIDE := 48.0
## #244: the fill texture stores brightness only, so these tint it directly.
## Green is the sheet art's own hue (median r/g and b/g).
const HP_GREEN := Color(0.17, 1.0, 0.14, 1.0)
const HP_AMBER := Color(0.95, 0.75, 0.25, 1.0)
const HP_RED := Color(0.9, 0.3, 0.25, 1.0)
const HP_AMBER_FRAC := 0.5
const HP_RED_FRAC := 0.25
const HP_TRACK_TEXTURE := preload("res://assets/sprites/hp_bar_track.png")
const HP_FILL_TEXTURE := preload("res://assets/sprites/hp_bar_fill.png")
const HP_TRACK_CAP := 42.0
const HP_FILL_CAP := 44.0 # transparent padding + the fill's tapered tip

var _player: Player
var _caster: SpellCaster
var _slot_icons: Array[SpellIcon] = []

var _objective: DungeonObjective
var _discover_elapsed := 0.0

## Discovered and validity-checked exactly like the objective node. Polled
## every frame because cast XP changes can_upgrade without any signal.
var _progress: Node = null
var _progress_elapsed := 0.0

@onready var _root: VBoxContainer = $Root
@onready var _hp_label: Label = $Root/HPBar/HPLabel
@onready var _hp_bar: ProgressBar = $Root/HPBar
@onready var _spell_grid: GridContainer = $Root/SpellGrid
@onready var _objective_label: Label = $Root/ObjectiveLabel

func _ready() -> void:
	_hp_bar.add_theme_stylebox_override("background", _hp_bar_style(HP_TRACK_TEXTURE, HP_TRACK_CAP))
	_hp_bar.add_theme_stylebox_override("fill", _hp_bar_style(HP_FILL_TEXTURE, HP_FILL_CAP))
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
		_build_slot_grid()

## Fixed end caps; the middle repeats so stars and stripes never stretch.
func _hp_bar_style(texture: Texture2D, cap: float) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = texture
	sb.texture_margin_left = cap
	sb.texture_margin_right = cap
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return sb

func _build_slot_grid() -> void:
	for i in SpellCaster.SLOT_COUNT:
		var icon := SpellIcon.new(SLOT_SIDE, true)
		_spell_grid.add_child(icon)
		_slot_icons.append(icon)
	_update_slot_icons()

func _update_slot_icons() -> void:
	# The caster can die with the run while signal timing races the reload.
	if not is_instance_valid(_caster):
		return
	var slots: Array = _caster.get_slots()
	for i in _slot_icons.size():
		var icon := _slot_icons[i]
		var spell: Spell = slots[i] if i < slots.size() else null
		icon.show_spell(spell)
		var remaining := 0.0
		if spell != null and spell.cooldown > 0.0:
			remaining = clampf(_caster.cooldown_remaining(spell) / spell.cooldown, 0.0, 1.0)
		icon.set_cooldown_fraction(remaining)
		icon.set_upgrade_available(_can_upgrade(spell))

func _can_upgrade(spell: Spell) -> bool:
	return spell != null and is_instance_valid(_progress) \
		and _progress.has_method("can_upgrade") and _progress.can_upgrade(spell)

func _process(delta: float) -> void:
	_update_objective(delta)
	_update_progress(delta)
	_update_slot_icons()

func _on_health_changed(current: int, max_hp: int) -> void:
	_hp_label.text = "%d/%d" % [current, max_hp]
	_hp_bar.max_value = max_hp
	_hp_bar.value = current
	# #93: HP state color - green -> amber -> red as the fraction drops.
	var fill := _hp_bar.get_theme_stylebox("fill") as StyleBoxTexture
	if fill != null:
		var frac := 0.0
		if max_hp > 0:
			frac = clampf(float(current) / float(max_hp), 0.0, 1.0)
		fill.modulate_color = HP_GREEN if frac > HP_AMBER_FRAC else (HP_AMBER if frac > HP_RED_FRAC else HP_RED)

func _on_player_died() -> void:
	# Run restart is #6's job; the HUD only reflects the death state.
	_hp_label.text = "DEAD"

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

## #50: screen-space rect other UI/world labels must keep clear of: the union
## of every visible Root descendant, extended for text that renders wider
## than its control box, plus padding. CanvasLayer space == screen space.
func reserved_rect() -> Rect2:
	if not is_node_ready():
		return Rect2()
	var rect := Rect2()
	var first := true
	for c: Control in _root.find_children("*", "Control", true, false):
		if not c.is_visible_in_tree():
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
	return rect.grow(RESERVED_PAD) if not first else rect
