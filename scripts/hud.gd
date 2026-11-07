extends CanvasLayer
class_name HUD
## gangU #11: player HUD - health, spells, cooldowns. (Objective display is
## intentionally NOT implemented here: it consumes #8's objective-state
## contract, which is still pending. See issue #11 body; no fake objective
## data is rendered.)
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

## Set by the mounting scene. If unset, falls back to the "player" group.
@export var player_path: NodePath

var _player: Player
var _caster: SpellCaster
var _spell_rows := {} ## Spell -> {name: Label, bar: ProgressBar, state: Label}

@onready var _hp_label: Label = $Root/HPLabel
@onready var _hp_bar: ProgressBar = $Root/HPBar
@onready var _spell_rows_box: VBoxContainer = $Root/SpellRows

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
		for s in _caster.spells:
			_add_spell_row(s)

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

func _process(_delta: float) -> void:
	if _caster == null:
		return
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
