# Path-only cache measurements

Base: a22c1c8b46a6b28964dfcb6c320d392e280ec0e2. Candidate functional source: fbb4851 (later commits strengthen tests/evidence only).

No sleep, simulation-rate, replan cadence, light or audio change. TerrainPath memoizes one exact A* result per mover by map identity/revision, start/goal cell and swim mode. Navigation cell flags share a bounded 16,384-cell cache for one weak map identity/revision; switching maps or any supported cell/palette/trunk write clears it. Full paths and returned arrays are separately copied to avoid caller mutation. Map resources are not retained. Existing terrain API does not observe in-place palette-resource mutations without reassignment; this patch does not add that support. Interleaved maps and full-cache clears may reduce hit rate, never answer correctness.

## CPU trials
Native Godot 4.5.1, three fresh interleaved runs per source, 100 ordinary enemies (44 roamers,33 red mustaches,23 Fishy) plus12 dormant statues. Player outside combat. Manually dispatched callback groups at delta1/60, 120Hz wall pacing,40 warmup samples and1,000 measured samples. Same harness as the original measurement; cover choices are not deterministic between independent scenes. No whole-scene replay equivalence claim. Runtime trajectory hashes in the raw records differ even between base runs.

Group totals, milliseconds:

| Work | Base range | Candidate range |
|---|---:|---:|
| All100 physics median |2.043-2.124|1.860-1.917|
| All100 physics p95 |9.281-9.304|6.927-7.283|
| All100 physics max |21.686-24.943|17.582-18.101|
| TerrainPath.steer median |1.170-1.249|1.008-1.033|
| TerrainPath.steer p95 |8.403-8.434|6.081-6.401|

Representative median-of-run-medians: physics2.052 ->1.905ms (~7%); physics p959.295 ->7.214ms (~22%). These are noisy scene distributions, not a universal gain.

## Same-input correctness oracle
The paired wrapper calls optimized and uncached reference steering with identical live map/position/velocity/target/delta inputs on every real enemy call. It compares exact returned velocity, complete path, waypoint index, replan timer and plan count.
-100-enemy run: zero mismatches, roughly83 calls/sample. Candidate steer median1.082ms,p956.474ms; reference1.248ms,p958.346ms.
-9-enemy run: zero mismatches. Candidate median0.110ms versus reference0.104ms (small median overhead), p950.151ms versus5.500ms (repeated blocked queries saved).

Paired wrapper runs both implementations, so its aggregate physics timings are NOT production callback costs. Wrapper always times candidate first; absolute timings can have order/cache effects. Focused test836 also checks4,834 assertions covering per-step positions, swim modes, map changes, equal-revision opposite maps, populated blocking/falling palette overrides, mutations, eviction and weak lifetime. Existing test511 independently compares A* paths with its historical reference.

## Rendered control
Native llvmpipe software renderer,1152x648, gate camera,100 enemies distributed near original world spawn regions, NOT100 visible fighting enemies. All lights unchanged. Two baseline/off/restored sandwiches,18frames/window,3settle frames. Neighboring on-control midpoint -> physics-off median:
-Base219.51 ->194.18ms and223.32 ->193.23ms.
-Candidate212.97 ->193.86ms and212.71 ->192.96ms.

Suggests a smaller simulation contribution (~19-20ms vs25-30ms) in this render-bound setup. Independent trials have movement/visibility/control drift, so no precise FPS claim. Multiple physics ticks may catch up in a rendered frame. Sprite/collision toggles are retained raw, not independent cost estimates. No browser, real GPU, active fight, large crowd-on-screen or visual performance claim. Screenshots were inspected separately; no visible art change intended.

## Reproduction
Run the checked-in harnesses via Godot --headless --path . --script res://docs/evidence/path-cost/path-bench.gd -- 100. Run both base and candidate with the same harness files. path-paired.gd uses paired-terrain-path.gd, whose uncached reference methods exist in the candidate. crowd-render.gd needs a display and -- gate 100 arguments. Drivers write raw JSON under /downloads. For a local machine, change that output directory first.

Teardown emitted resource-in-use notices in some runs; no gameplay script errors. Xvfb wrapper sometimes returned1 during cleanup after all result and FINAL rows had completed.
