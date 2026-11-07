class_name RewardPool
extends Node
## Reward pool (track A, #59): run-scoped record of which reward entries have
## left the pool. Concurrent pin (lead, 2026-11-07): setup(table) /
## is_eligible(entry) -> bool / remove_on_grant(entry); grant-only removal;
## per-run reset comes free from the RunManager's full scene reload - no
## reset code here. Mounted ONCE on Main (ReviveSatchel pattern; production
## mount is the separate E window).
##
## Removal happens on GRANT (player actually picks the drop up), never on
## spawn. Re-eligibility of uncollected drops and duplicate floor copies are
## open human choices - no policy invented here.

signal pool_changed()

var _table: RewardTable
var _granted: Array[RewardEntry] = []

func _ready() -> void:
	add_to_group("reward_pool")

func setup(table: RewardTable) -> void:
	_table = table

func is_eligible(entry: RewardEntry) -> bool:
	return entry != null and not _granted.has(entry)

## Called by the reward drop when the player actually collects it.
func remove_on_grant(entry: RewardEntry) -> void:
	if _granted.has(entry):
		return
	_granted.append(entry)
	pool_changed.emit()
	print("[rewards] left pool on grant: ", entry.spell.spell_name if entry.spell != null else "(item)")

## Read-only copy for UI/debug consumers.
func granted() -> Array[RewardEntry]:
	return _granted.duplicate()
