# Hook reward save-load regression (#818)

## Root cause and fix
Fishy death drops `fishy_hook_table.tres::hook`. Collecting it records this embedded RewardEntry in RewardPool, alongside unlocking Hook Shot. On a fresh exported-browser boot, the save decoder checked `ResourceLoader.exists(owner::hook)` before loading its owner. That check fails while the owner is not cached, converts the saved entry to null and rejects the entire snapshot. Native and same-session direct-spell roundtrips missed it.

Load the allowlisted `.tres` owner before resolving the embedded resource. No format change: existing valid version-1 saves can load. Previously overwritten data cannot be reconstructed.

Rejected saves now leave the original key unchanged and suspend ALL writes, including death/unload/autosave. A visible reason, download-original button and confirmed start-new flow replace the old overwrite-on-boot behavior. Starting new first saves a recovery copy; an existing backup or storage failure blocks replacement rather than destroying either copy.

## Validation
- Actual exported Chrome Fishy reward-drop pickup, no casts, save and cold page refresh reproduced failure before fix, restored Hook + reward exclusion after fix.
- Every source Spell independently saved and cold-refreshed: 34/34, including upgraded and enemy-only resources (a superset of player unlockables). Inventory/slot/cast count checked, not merely no-error codec calls.
- Expanded browser suite: previous progression, beforeunload/hidden/reopen, death pause, quota/blocked, corrupt/future original preservation across reload and explicit new-save backup flow.
- Native suite 60/60 includes test818 cold embedded RewardEntry resolution, all 34 spell codec + actual restore checks and rejection diagnostics.
- Visually inspected actual exported-game screenshots: restored Hook slot and readable rejected-save warning/download/new-save controls.
- Based on main ff4cdb0, including water/tide/day-night. Those effects are transient presentation, not progression; existing map explored/color data stays in the existing capture schema. No #817 changes/review.

Evidence: ../evidence/818/. Chrome scripted only, not Safari/mobile or a full manual playthrough. Published deployment remains a post-merge check. The original #815 browser fixture only seeded Rock fishing, not Fishy's drop-grant record or all spells.
