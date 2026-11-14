class_name ProgressionCarry
extends Object
## #655 (Daniel, 2026-11-14: "make it so that dying does not reset your
## progression (spells, upgrades, relics) money is lost tho"): the one
## cross-run carry. RunManager snapshots progression at death; Main applies
## it to the fresh scene right after the reload. Statics survive the scene
## reload exactly like Run's service lists - here that is the point.
##
## This supersedes the #351 "no partial carryover" scope for progression
## ONLY. Coins, the world, dungeon cleared-state, the map, the revive
## satchel and consumables still reset with the reload, unchanged.

static var _pending := false
static var _unlocked: Array[Spell] = []
static var _spells: Array[Spell] = []
static var _slots: Array[Spell] = []
static var _progress: Dictionary = {}
static var _relics: Array[Relic] = []

## Called by RunManager the moment an unrevived death lands, BEFORE the
## reload wipes the run scene. Spell/Relic resources are shared data, so the
## references stay valid across the reload.
static func snapshot(tree: SceneTree) -> void:
	var p := Player.find(tree)
	if p == null:
		return
	var caster := p.get_node_or_null("SpellCaster") as SpellCaster
	if caster != null:
		_unlocked = caster.get_unlocked()
		_spells = caster.spells.duplicate()
		_slots = caster.get_slots()
	var progress := tree.get_first_node_in_group("spell_progress") as SpellProgress
	if progress != null:
		_progress = progress.capture_run_state()
	var relics := Run.relics()
	if relics != null:
		_relics = relics.all()
	_pending = true

## Called by Main at the end of _ready, after every run service is mounted.
## No-op on first boot (nothing pending).
static func apply_pending(main: Node) -> void:
	if not _pending:
		return
	_pending = false
	var caster := main.get_node_or_null("Player/SpellCaster") as SpellCaster
	if caster != null:
		caster.restore_run_state(_unlocked, _spells, _slots)
	var progress := main.get_node_or_null("SpellProgress") as SpellProgress
	if progress != null and not _progress.is_empty():
		progress.restore_run_state(_progress)
	var relics := main.get_node_or_null("OwnedRelics") as OwnedRelics
	if relics != null:
		for r in _relics:
			relics.add(r)
