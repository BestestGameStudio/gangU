class_name SummonManager
extends Node
## #209: player summons foundation - the ONE spawn entry point and the shared
## cap. "Summon cap can be 10 from any source (but modifiable by relics,
## etc)" (Daniel, 2026-11-08): every spawn from every source funnels through
## request_spawn(), which enforces effective_cap(); effective_cap() is the
## single read point later relics modify.
## "Separate system but be able to be casted from a spell" (Daniel,
## 2026-11-08): listens to the caster's existing spell_cast signal and spawns
## when the cast Spell carries a summon definition. No concrete summon spell
## ships here - #212 owns the first.

## Emitted when a spawn request is refused because the shared cap is reached.
signal spawn_refused(definition: SummonDefinition)
signal summoned(summon: Summon)

## Explicit wiring convention (matches Shop/SpellProgress): set before tree
## entry; the Player.find fallback applies otherwise.
@export var caster_path: NodePath
## Shared cap across ALL sources (Daniel, 2026-11-08). Human-tunable data,
## not a constant.
@export var base_cap: int = 10

const CombatEffects = preload("res://scripts/combat_effects.gd")

var _caster: SpellCaster

func _ready() -> void:
	add_to_group("summon_manager")
	if caster_path != NodePath(""):
		_caster = get_node_or_null(caster_path) as SpellCaster
	if _caster == null:
		var player := Player.find(get_tree())
		if player != null:
			_caster = player.get_node_or_null("SpellCaster") as SpellCaster
	if _caster != null:
		_caster.spell_cast.connect(_on_spell_cast)
	else:
		push_warning("SummonManager: no caster resolved; cast-driven summons disabled.")

## The single cap read point. Relics and other systems modify the cap HERE
## (foundation seam; no concrete relic exists yet - #209).
func effective_cap() -> int:
	return base_cap

func live_count() -> int:
	return get_tree().get_nodes_in_group("summons").size()

## THE one spawn entry point. Returns null and emits spawn_refused when the
## shared cap is reached. Summons parent into the current area, so area swap
## and run reload (main.gd _swap / RunManager) free them like any other area
## child - cap slots release automatically on death or teardown.
func request_spawn(definition: SummonDefinition, position: Vector2) -> Summon:
	if definition == null:
		return null
	if live_count() >= effective_cap():
		spawn_refused.emit(definition)
		return null
	var summon: Summon = preload("res://scenes/summon.tscn").instantiate()
	summon.setup(definition)
	# #212: wire the guarding player BEFORE tree entry (player_path idiom);
	# the caster's parent is the production Player. Null in harnesses.
	if _caster != null:
		summon.player = _caster.get_parent() as Node2D
	# #281: wire the area's terrain grid BEFORE tree entry (same idiom as
	# the player wiring above and main.gd's player.terrain lookup), so the
	# behavior can pathfind around unwalkable cells from its first physics
	# step. Null where the area has no Terrain node.
	summon.terrain = _spawn_parent().get_node_or_null("Terrain") as TerrainMap
	_spawn_parent().add_child(summon)
	summon.global_position = position
	summoned.emit(summon)
	return summon

func _on_spell_cast(spell: Spell) -> void:
	if spell == null or spell.summon == null:
		return
	var origin := Vector2.ZERO
	if _caster != null:
		origin = _caster.global_position
	var spawned := request_spawn(spell.summon, origin)
	# #289: cast art for the summon, visual only; refused casts show nothing.
	if spawned != null:
		CombatEffects.summon_circle(spawned.get_parent(), origin)

## Current area first (production Main), then the scene root (harnesses).
func _spawn_parent() -> Node:
	var main := get_parent()
	if main != null:
		var loader: Node = main.get("area_loader") # #512: areas are owned by Main's AreaLoader
		if loader != null and loader.get("current_area") != null:
			return loader.get("current_area")
		if main.get("current_area") != null:
			return main.get("current_area")
	if get_tree().current_scene != null:
		return get_tree().current_scene
	return get_tree().root
