## Request and scope
Daniel requested the 100-enemy measurement, then approved a path-cost issue and clarified: path only for now. Investigate and reduce path/terrain-steering CPU cost with strict observable-behavior parity. No far-enemy sleep, simulation-rate change, migration/timer pause, aggro delay, light change or audio change.

Claimed by instinct-dc. Intended scope: game/world/terrain/terrain_path.gd, focused path tests, and measurement evidence. No overlap with the parked lighting investigation #832/#833.

## Measurement on main a22c1c8b46a6b28964dfcb6c320d392e280ec0e2
Native Godot 4.5.1; three fresh headless runs per population; 1,000 samples after 40 warmup callbacks; callbacks manually dispatched at delta 1/60 with 120 Hz wall pacing. Group totals, not per-enemy times:

| CPU work | 9 enemies | 100 enemies |
|---|---:|---:|
| Physics callback median | 0.232-0.247 ms | 2.064-2.174 ms |
| Physics callback p95 | 5.531-5.713 ms | 9.275-9.812 ms |
| Physics callback max | 8.903-8.917 ms | 22.589-23.197 ms |
| TerrainPath.steer median | 0.119-0.144 ms | 1.195-1.295 ms |
| TerrainPath.steer p95 | 5.415-5.579 ms | 8.418-8.956 ms |
| Sprite script median | 0.010 ms | 0.081-0.083 ms |

Rendered gate, Mesa llvmpipe software rendering, 1152x648, lights unchanged, two baseline/off/restored controls with 18 sampled frames per window:
- 9 enemies: neighboring on-control midpoint 193.99 / 195.02 ms -> physics off 192.42 / 192.44 ms.
- 100 enemies: 219.51 / 223.32 ms -> physics off 194.18 / 193.23 ms.

## Limits
100 ordinary living enemies: 44 roamers, 33 red mustaches, 23 Fishy, plus the unchanged 12 dormant statues. Extras spread around their existing spawn areas, not 100 visible fighting enemies. Player outside combat; arena dormant; no deaths. Cover picks were not seeded, so trajectories differ. TerrainPath.steer includes terrain checks and steering as well as route search; this does not isolate exclusive A* cost. Rendered frames may contain multiple catch-up physics steps. No browser, real GPU, active-fight or universal FPS claim. Collision-mask-zero runs overlap normal CPU timings, but do not remove TerrainMap queries or all collision bookkeeping. Sprite render trials were confounded by moving enemies and are not an isolated cost estimate.

## Candidate approach
Prefer exact memoization or reuse of query work whose complete inputs are unchanged, with explicit terrain/navigation invalidation and bounded memory. Keep existing route ordering, tie breaks, replan cadence, returned velocities, timers and movement unchanged. Throttling is permitted only if identical decisions can be demonstrated, not merely similar-looking behavior. Start with the smallest verified cache rather than changing scheduling.

## Acceptance
- Exact path and per-step velocity comparisons against baseline for unchanged and mutated terrain, swimmers, blocked/unreachable targets, moving endpoints and map changes.
- Baseline/candidate measurement with the same 9/100-enemy harness; medians, p95, max and controls, with the above caveats retained.
- Independent exact-head review and green CI before any merge.
- Draft PR immediately upon implementation start; no claim of a shipped fix until verified.

Far-enemy sleep is explicitly out of scope until Daniel decides separately. There is no open gameplay-design choice authorized by this issue.
