class_name SpellProgress
extends Node
## Spell progression provider (for F's panel, #62; upgrades per Daniel
## 2026-11-07: manual, via the shared Tab panel, no pause). F consumes this
## API; a missing provider leaves F inert (pinned interop).
##
## READ/API ONLY: no caster array mutation anywhere. apply_upgrade is a
## refusal-bool and stays REFUSING until B's replace_spell follow-up (Mitra,
## post-#63) lands with its final edge semantics; then it delegates to the
## caster atomically. XP is observed READ-ONLY from the caster's spell_cast
## signal - no XP spending or qualification policy is invented here.

signal upgrades_changed()

## Explicit caster wiring (no-group convention from #34).
@export var caster_path: NodePath
## Available upgrade paths. Contents beyond the approved placeholder paths
## are human-open.
@export var upgrades: Array[SpellUpgrade] = []

var _cast_counts: Dictionary = {} # Spell -> int, read-only XP observation
var _caster: Node

func _ready() -> void:
	add_to_group("spell_progress")
	_caster = get_node_or_null(caster_path) if not caster_path.is_empty() else null
	if _caster != null and _caster.has_signal("spell_cast"):
		_caster.spell_cast.connect(_on_spell_cast)

func _on_spell_cast(spell: Spell) -> void:
	_cast_counts[spell] = int(_cast_counts.get(spell, 0)) + 1

## Read-only XP observation for one spell (casts this run).
func cast_count(spell: Spell) -> int:
	return int(_cast_counts.get(spell, 0))

## Upgrade paths offered for a spell: [{id, name}] per the pinned provider
## shape; returns full SpellUpgrade resources, F reads id/display_name.
func get_upgrade_paths(spell: Spell) -> Array[SpellUpgrade]:
	var out: Array[SpellUpgrade] = []
	for u in upgrades:
		if u != null and u.source_spell == spell:
			out.append(u)
	return out

func can_upgrade(spell: Spell) -> bool:
	if _caster == null or not _caster.has_method("get_unlocked"):
		return false
	if spell not in _caster.get_unlocked():
		return false
	for u in get_upgrade_paths(spell):
		if u.result_spell != null and int(_cast_counts.get(spell, 0)) >= u.xp_threshold:
			return true
	return false

## Refusal-bool. Currently ALWAYS refuses: the replace_spell caster seam is
## Mitra's post-#63 follow-up and has not landed. Once it lands this
## delegates: _caster.replace_spell(u.source_spell, u.result_spell), then
## upgrades_changed.emit(). No direct array mutation here ever.
func apply_upgrade(spell: Spell, upgrade_id: StringName) -> bool:
	for u in get_upgrade_paths(spell):
		if u.id == upgrade_id:
			if _caster == null or not _caster.has_method("replace_spell"):
				push_warning("SpellProgress: replace_spell seam not landed yet (Mitra post-#63 follow-up); refusing.")
				return false
			if u.result_spell == null:
				push_warning("SpellProgress: placeholder upgrade has no result_spell content yet; refusing.")
				return false
			var ok: bool = _caster.replace_spell(u.source_spell, u.result_spell)
			if ok:
				upgrades_changed.emit()
			return ok
	push_warning("SpellProgress: unknown upgrade id '%s' for %s." % [upgrade_id, spell])
	return false
