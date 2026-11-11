class_name DungeonModifierHost
extends Node
## (#222) Per-dungeon modifier host + event bridge.
##
## An area scene opts in by carrying ONE child named "DungeonModifiers" with
## this script and its `modifiers` list (same data-carrier idiom as the
## #100 "SpawnData" child). Main calls bind() at the END of every area
## mount, after spawns, objective and exit portal exist. An area without the
## child has no modifiers; no production area carries one yet, so the
## system is inert until modifier content lands.
##
## EVENT-AGNOSTIC TRIGGERS: bind() connects to signals that already exist
## and re-raises them as named events with a Dictionary payload. Every
## modifier whose trigger matches the event fires its effect. The emitting
## systems are untouched and never learn which modifiers are active. Other
## code can raise its own event names through emit_event().
##
## Built-in events and payload keys (every payload also has "dungeon_id"):
##   dungeon_entered      {"area"}
##   enemy_died           {"enemy", "enemy_scene", "is_boss"}
##   boss_spawned         {"boss", "enemy_scene"}
##   objective_progress   {"current", "target"}
##   objective_completed  {}
##   spell_cast           {"spell", "spell_name"}
##   run_restarting       {}
## "enemy_scene" is the enemy's scene_file_path (a String), so a trigger
## filter can pick out one specific enemy type.
##
## LIFETIME (current default, human-open): the host is a child of its area,
## so it is freed on the next area swap and its trigger counts reset on
## every entry. What an effect changes outside the area is the effect's own
## business.

signal triggered(modifier: DungeonModifier, event: StringName, payload: Dictionary)

const DUNGEON_ENTERED := &"dungeon_entered"
const ENEMY_DIED := &"enemy_died"
const BOSS_SPAWNED := &"boss_spawned"
const OBJECTIVE_PROGRESS := &"objective_progress"
const OBJECTIVE_COMPLETED := &"objective_completed"
const SPELL_CAST := &"spell_cast"
const RUN_RESTARTING := &"run_restarting"

## Effects may raise events themselves; this caps nested emit_event depth
## so two modifiers cannot trigger each other forever.
const MAX_EVENT_DEPTH := 8

@export var modifiers: Array[DungeonModifier] = []

var area: Node = null
var dungeon_id: StringName = &""

var _bound := false
var _fire_counts: Dictionary = {} # modifier index -> times fired
var _tracked_enemies: Dictionary = {} # instance id -> true
var _depth := 0

## Wire the bridge for a mounted area. caster / run_manager are optional
## (null skips their events). Raises dungeon_entered last, so effects see a
## fully mounted area. Safe to call once; later calls are ignored.
func bind(p_area: Node, caster: SpellCaster = null, run_manager: RunManager = null) -> void:
	if _bound or p_area == null:
		return
	_bound = true
	area = p_area
	var def := DungeonCatalog.for_area(area)
	dungeon_id = def.id if def != null else StringName(area.name)
	for child in area.get_children():
		_track_enemy(child)
	area.child_entered_tree.connect(_track_enemy)
	# Keep the existing modifier event vocabulary, sourced from the region
	# encounter rather than the retired global objective class.
	var encounter := area.get_node_or_null("RegionEncounterHost") as RegionEncounterHost
	if encounter != null:
		encounter.boss_spawned.connect(_on_boss_spawned)
		encounter.encounter_finished.connect(_on_encounter_finished)
		if encounter.defense != null:
			encounter.defense.progress_changed.connect(_on_objective_progress)
	if caster != null:
		caster.spell_cast.connect(_on_spell_cast)
	if run_manager != null:
		run_manager.run_restarting.connect(_on_run_restarting)
	for m in modifiers:
		if m == null or not m.is_valid_definition():
			push_warning("DungeonModifierHost: skipping an invalid modifier (needs id, trigger_event, effect).")
	emit_event(DUNGEON_ENTERED, {"area": area})

## The one routing point. Fires every valid modifier whose trigger matches.
## Returns how many modifiers fired.
func emit_event(event: StringName, payload: Dictionary = {}) -> int:
	if _depth >= MAX_EVENT_DEPTH:
		push_warning("DungeonModifierHost: event depth limit hit at '%s'; dropping it." % event)
		return 0
	var data := payload.duplicate()
	if not data.has("dungeon_id"):
		data["dungeon_id"] = dungeon_id
	var fired := 0
	_depth += 1
	for i in modifiers.size():
		var m := modifiers[i]
		if m == null or not m.is_valid_definition() or not m.matches(event, data):
			continue
		var n: int = _fire_counts.get(i, 0)
		if m.max_triggers > 0 and n >= m.max_triggers:
			continue
		_fire_counts[i] = n + 1
		m.effect.apply(event, data, self)
		triggered.emit(m, event, data)
		fired += 1
	_depth -= 1
	return fired

func fire_count(modifier_id: StringName) -> int:
	var total := 0
	for i in modifiers.size():
		if modifiers[i] != null and modifiers[i].id == modifier_id:
			total += _fire_counts.get(i, 0)
	return total

func _track_enemy(node: Node) -> void:
	if not node is Enemy:
		return
	var key := node.get_instance_id()
	if _tracked_enemies.has(key):
		return
	_tracked_enemies[key] = true
	(node as Enemy).died.connect(_on_enemy_died.bind(node))

func _on_enemy_died(enemy: Enemy) -> void:
	emit_event(ENEMY_DIED, {
		"enemy": enemy,
		"enemy_scene": enemy.scene_file_path,
		"is_boss": enemy.is_in_group("boss"),
	})

func _on_boss_spawned(boss: Node) -> void:
	emit_event(BOSS_SPAWNED, {"boss": boss, "enemy_scene": boss.scene_file_path})

func _on_objective_progress(current: int, target: int) -> void:
	emit_event(OBJECTIVE_PROGRESS, {"current": current, "target": target})

func _on_encounter_finished(_encounter_id: StringName, cleared: bool) -> void:
	if cleared:
		emit_event(OBJECTIVE_COMPLETED)

func _on_spell_cast(spell: Spell) -> void:
	emit_event(SPELL_CAST, {"spell": spell, "spell_name": spell.spell_name if spell else ""})

func _on_run_restarting() -> void:
	emit_event(RUN_RESTARTING)
