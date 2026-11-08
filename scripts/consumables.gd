class_name Consumables
extends Node
## gangU #130 (foundation C3): generic carried consumables - a count per
## Consumable definition, run-scoped like the wallet (mounted once on Main;
## per-run reset comes free from RunManager's full scene reload).
##
## ReviveSatchel stays the AUTO-on-death revive path and is UNTOUCHED by
## design (accepted #6/#12 contract); this is the generic seam BESIDE it,
## not a replacement. Manual-use INPUT (dedicated keys vs panel) is a
## pending human choice; the use seam here is try_use(), input-agnostic.
##
## CONSUMPTION SAFETY: try_use decrements ONLY after the effect handler
## returns true. An unknown/unregistered hook or a REFUSED effect consumes
## NOTHING and returns false - inventory is never lost to a failed use.
##
## Effects are injectable (register_effect) so this foundation ships ZERO
## production effects; content PRs register real handlers, test harnesses
## register stubs.

signal carried_changed(consumable: Consumable, new_count: int)

## Dedicated-use key (manual use is a DEDICATED KEY, per the human input
## decision; the exact key was delegated, changeable later). E is free in
## the current controls: WASD move, Space/mouse-LMB cast, Tab equip panel,
## digits 1-6 spell slots, switch_spell unbound. Runtime registration,
## idempotent across reloads (InputMap is global); project.godot untouched.
const USE_ACTION := &"use_consumable"
const USE_KEY := KEY_E

## Explicit wiring convention (matches ReviveSatchel/SpellProgress): set
## before tree entry; no group fallback.
@export var player_path: NodePath

var _counts: Dictionary = {} ## Consumable -> int
var _effects: Dictionary = {} ## StringName -> Callable(player) -> bool
var _player: Player

func _ready() -> void:
	add_to_group("consumables")
	if player_path != NodePath(""):
		_player = get_node_or_null(player_path) as Player
	if _player == null:
		push_warning("Consumables: player_path unset or unresolved; effect handlers receive a null player.")
	if not InputMap.has_action(USE_ACTION):
		InputMap.add_action(USE_ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = USE_KEY
		InputMap.action_add_event(USE_ACTION, ev)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(USE_ACTION):
		try_use_dedicated_key()

## Dedicated-key policy: with EXACTLY ONE consumable type carried, use one
## of it. With SEVERAL types carried, which one the key means is an open
## human decision (selection mechanic), so the key refuses rather than
## guessing - nothing is consumed either way on refusal.
func try_use_dedicated_key() -> bool:
	var carried_types: Array = []
	for c in _counts:
		if _counts[c] > 0:
			carried_types.append(c)
	if carried_types.size() != 1:
		return false
	return try_use(carried_types[0])

func add(consumable: Consumable, amount: int = 1) -> void:
	if consumable == null or amount <= 0:
		return
	_counts[consumable] = count(consumable) + amount
	carried_changed.emit(consumable, _counts[consumable])

func count(consumable: Consumable) -> int:
	return _counts.get(consumable, 0)

## Register the effect behind a hook id. The handler receives the wired
## Player (possibly null) and returns true ONLY when the effect applied.
func register_effect(hook: StringName, handler: Callable) -> void:
	_effects[hook] = handler

## Use one carried consumable. Returns true only when an effect actually
## applied; the count decrements ONLY on success (never before).
func try_use(consumable: Consumable) -> bool:
	if consumable == null or count(consumable) <= 0:
		return false
	if not _effects.has(consumable.effect_hook):
		return false ## unknown hook: refuse WITHOUT consuming
	var handler: Callable = _effects[consumable.effect_hook]
	if not handler.is_valid():
		return false
	if not handler.call(_player):
		return false ## refused effect: consume nothing
	_counts[consumable] -= 1
	carried_changed.emit(consumable, _counts[consumable])
	return true
