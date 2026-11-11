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
