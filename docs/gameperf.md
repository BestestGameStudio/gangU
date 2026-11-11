# Opt-in gameperf diagnostics (Refs #548)

This is a bounded instrumentation slice, not completion of #548, #550 or #551.
No threshold, FPS certificate, browser-combat acceptance, hosting or #549 closure.

## Contract

- OFF by default. With no `--gameperf` argument no probe node, sampling callback,
  output file or counter traversal is installed. No gameplay or visual change.
- Enabled collection uses monotonic microseconds between process callbacks, not
  clamped game delta. Those samples are callback cadence, not pure render time.
- Counts are periodically observed: SceneTree nodes, living Enemy instances in
  the current area, `can_process()` eligible/disabled enemies, region active
  flags and observed false-to-true activation transitions since probe attachment.
  Initial region state is separate. Process-disabled is not physics-body sleep.
- Renderer object/draw-call counters are never called "nodes drawn". Headless or
  unavailable renderer values are null. Pre-fold region counters are null, not
  invented comparable zeroes.
- Every diagnostic output carries commit SHA, Godot version, backend, seed and
  frame schedule. A seed does not guarantee identical engine physics timing.

## Two distinct workloads

A. Natural overworld arrival, the same script/frame schedule on pre-fold
`20be5d885bcccee0a020909b0b83f15f32ea678f` and the selected current commit.
Entity counts and layouts differ. This is not matched combat.

B. An isolated identical common-system workload using production Player/Enemy
assets, the same positions, seed and frame schedule. This is not the folded
world, activation savings or representative browser combat.

Run both on the same machine, Godot version and backend. Headless/software
renderer results are diagnostics only. The prior hosted browser's blank control
had roughly 40ms RAF cadence (~25Hz), which prevents an ordinary-laptop60fps
claim and cannot calibrate a combat regression gate.

Implementation and default-off verification evidence will be added before review.
Combined engineering acceptance stays open: controlled representative browser
combat, matched pre-fold browser baseline and a calibrated regression threshold.

## Run without hosting

```sh
python3 tools/benchmarks/run_gameperf.py \
  --prefold /path/to/20be5d8-checkout --current /path/to/current-checkout \
  --godot /path/to/godot-4.5.1 --output /tmp/gameperf-pair.json
```

Use clean checkouts when recording review evidence. The runner copies each
project into a temporary directory, overlays the SAME probe/benchmark bytes,
imports there, isolates user state per run, and captures engine output inside
metadata envelopes. It does not edit either checkout, launch a server, install a
web adapter, or change CI. A dependency-directory SHA256 comparison reports
common-asset differences rather than assuming B remains identical forever.
Dirty source status and tool hashes are retained. The JSON carries the exact
revision, version, backend, machine, seed and frame schedule for every run.

`--fixed-fps 60` gives identical simulation-step scheduling, NOT60 real FPS.
Raw microsecond intervals are measured wall-clock process-callback cadence while
Godot runs that artificial schedule. Do not compare them to a16.67ms budget.
A is stationary arrival, not a scripted kill demonstration. B uses8 production
contact enemies64px around a stationary player, no terrain, and100000HP fixture
endurance to avoid truncating the workload on death. Damage RNGs are explicitly
seeded in B. A uses production RNGs, including local randomize() calls, so a
shared global seed does not make its worlds identical. No actor is killed,
frozen or skipped by the benchmark to create a performance result.

For passive native observation only:

```sh
godot --path . -- --gameperf --gameperf-sha=THE_EXACT_CHECKOUT_SHA
```

That creates a probe after normal Main boot, records600 process callbacks,
snapshots counts every30 callbacks and writes `user://gameperf.json` plus a
`GAMEPERF_JSON` console envelope. It changes no seed, input, timestep, gameplay
stats or graphics. Missing SHA is explicitly `unknown:not-supplied`, passive seed
is null. Do not present an unknown/dirty source as qualified exact-head evidence.
There is no browser query-string adapter in this change.

## Counter and verification limits

Region transition counts are OBSERVED false-to-true changes between periodic
snapshots. Brief toggles between snapshots can be missed; initial awake state
and regions already awake at attachment are not counted as activations. This is
not an exhaustive signal-event count. Enemy eligibility uses `can_process()`
and does not establish AI execution, physics sleep, visibility or actual ticks.
Tree node totals include instrumentation and UI; renderer counters are not nodes.
All sampling has observer overhead, including the periodic tree/group traversal.

The runner's OFF case boots normal Main WITHOUT the flag, inspects absence of
`GamePerfProbe`, absence of the output file and Main child names. Its ON smoke
case checks current bootstrap actually installs the probe. Source inspection of
the single flag guard establishes no script load/node/callback/traversal/export
on the flag-absent path. These structural checks do not prove pixel/timing
identity by themselves. Review evidence must distinguish them from any rendered
comparison and retain warnings/errors from the raw engine output.
