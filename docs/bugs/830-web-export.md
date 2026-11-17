# Web release payload audit (#830)

Release export currently includes review screenshot resources under docs/evidence. No runtime res://docs/ references found in game/, data/ or project settings. Measure identical normal release exports before/after excluding docs and verify runtime/save smoke. Do not delete the source evidence or change gameplay content.

## Before/after (main 2d82a5f, Godot 4.5.1 release, identical settings)

- PCK 12,712,748 -> 10,357,748 decoded bytes (-2,355,000, 18.53%).
- Deterministic gzip6 11,639,405 -> 9,316,480 bytes (-2,322,925, 19.96% of pack transfer). CDN compression may differ; these are local controlled compression figures.
- 85 removed entries total: 44 docs screenshot import records + 41 imported screenshot textures (2,346,184 file bytes, plus index/padding). Every remaining exported file is byte-identical; zero changed/added pack entries. Test-only scripts remain excluded as before.
- No res://docs/ references in game, data, project settings. Source evidence stays in git, and future screenshots under docs no longer inflate the game download.
- Normal release, no injected bridge: real canvas/Space progression change + refresh byte-identical, no script/page errors, on both exports. Inspected trimmed-release screenshot: hub/art/HUD/restore notice intact.
- Full native suite 60/60 PASS in50.4s. Cold local boot first-save single trials 4022ms before /4026ms after: no demonstrated startup-speed gain in this environment; payload improvement is measured, not an FPS claim.
- Scripted Chrome/SwiftShader only, not Safari/mobile/manual full playthrough. Production deploy is post-merge work.
