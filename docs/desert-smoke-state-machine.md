# Desert squad smoke cycles

Follow-up to #882. Player exit now rearms a throw instead of permanent refuge.
Only the local squad controller owns the shared state. Member behavior reads it
for movement/contact; Enemy still owns damage, freeze, stun, force and terrain.

| State | Allowed exits | Guard / effect |
| --- | --- | --- |
| TRAVEL | SPREAD | Visible living target within360px; cooldown clear |
| SPREAD | THROW, TRAVEL | 1.8s spread, cooldown clear, eligible thrower; target loss aborts |
| THROW | WAIT_SMOKE, SPREAD, TRAVEL | 0.4s uninterrupted windup; disabled/dead thrower replaced with clock reset; none eligible returns to spread |
| WAIT_SMOKE | CHARGE, TRAVEL | Only current-generation real landing charges; missing landing times out after3s; target loss aborts |
| CHARGE | SMOKE_HOLD, SPREAD, SCATTER | Player exits cloud, sustained exit rearms, or smoke actually ends |
| SMOKE_HOLD | CHARGE, SPREAD, SCATTER | Return inside, sustained exit rearms, or smoke actually ends |
| SCATTER | SPREAD, TRAVEL | 3s scatter; visible target within760px rearms, otherwise travel |

All transitions use `_enter`, which rejects edges outside the table and resets
actions/clocks. A target outside live smoke for1s can rearm only after the3s
minimum launch-to-launch cooldown. Returning inside resets the exit clock.
Each rethrow goes through spread and windup, never straight to charge.
Hidden/dead/disengaged players do not receive new throws. Existing smoke remains
area-owned and expires normally; SmokeCloud's existing global cap still applies.

Throw choice rotates through stable original scene slots, skipping dead, frozen
or stunned members. Leadership is only a surviving travel anchor. Disable/death
during windup selects the next eligible member and restarts windup. Release
advances the round-robin cursor and starts cooldown. After release, death or
disable does not destroy the area-owned grenade or block its landing callback.
Stale/aborted callbacks cannot advance a later cycle. No eligible survivors means
wait in spread; no living survivors means remove the controller.

Timing is placeholder balance. Tests cover all-five eligibility, pruning,
freeze/death handoff, repeated exit/expiry cycles, target loss, debounce/cooldown,
illegal edges, missing grenades and stale callbacks. A scripted demo stages
player position/HP only, with no state, timer or cloud-lifetime override. It is
not manual balance testing or browser-play qualification.

## Inside-smoke charge follow-up

A new draft tracks continuous charging while the player shares the squad smoke.
Current per-puff containment and newest-cloud-only tracking are under review;
no change to gameplay semantics is made by this draft-start note.
