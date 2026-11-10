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

## (#520) Reached through Run.reward_pool(), not a group lookup.
func _enter_tree() -> void:
	Run.register(self)

func _exit_tree() -> void:
	Run.unregister(self)

func setup(table: RewardTable) -> void:
	_table = table

func is_eligible(entry: RewardEntry) -> bool:
	return entry != null and not _granted.has(entry)

## Called by the reward drop when the player actually collects it.
func remove_on_grant(entry: RewardEntry) -> void:
	# #128: CURRENCY stays eligible after grant - drops can repeat within a
	# run (Daniel, 2026-11-07: "Currency should be eligible again"). Nothing
	# leaves the pool; the grant is only logged.
	if entry.kind == RewardEntry.Kind.CURRENCY:
		print("[rewards] currency grant: +", entry.currency_amount, "c (pool keeps entry eligible)")
		return
	# #315: the boss upgrade token repeats per boss kill (provisional).
	if entry.kind == RewardEntry.Kind.UPGRADE_TOKEN:
		print("[rewards] upgrade token grant (pool keeps entry eligible)")
		return
	# #426: relic uniqueness is OwnedRelics' job (its add() refuses owned
	# ids from every source), so the pool records nothing for relics.
	if entry.kind == RewardEntry.Kind.RELIC:
		return
	if _granted.has(entry):
		return
	_granted.append(entry)
	pool_changed.emit()
	print("[rewards] left pool on grant: ", entry.spell.spell_name if entry.spell != null else "(item)")

## Read-only copy for UI/debug consumers.
func granted() -> Array[RewardEntry]:
	return _granted.duplicate()
