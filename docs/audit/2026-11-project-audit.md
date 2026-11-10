# gangU project audit, November 2026

Audit of `main` at `4a0c057`, read-only. Four passes covered architecture, tests, performance, and data/docs. This file merges them. Principles cited are the pstack ones: subtract-before-you-add (SBA), sequence-verifiable-units (SVU), migrate-callers-then-delete-legacy-apis (MCD), model-the-domain (MTD), encode-lessons-in-structure (ELS), minimize-reader-load (MRL), fix-root-causes (FRC), prove-it-works (PIW), test-behavior-not-implementation (TBI), type-system-discipline (TSD), build-the-lever (BTL).

Status labels:
- **Verified** means re-checked by hand for this report.
- **Measured** means a worker timed or counted it with a script.
- **Suspected** means the conclusion comes from reading code only.

All local runs used Godot 4.7.2 (`/opt/homebrew/bin/godot`). The project pins 4.5.1. One worker's notes said 4.5.1; its logs show 4.7.2.

## TL;DR

- **`main` is red, and nothing would tell you.** `test348_cleared_dungeon` fails at HEAD (verified). No workflow runs any test harness. 16 harnesses exit 0 even when they fail, and only 42 of 191 print the `RESULT: ALL PASS` line the CI skill treats as the pass signal.
- **"A lot of scripts for each small thing" is mostly a layout problem, not a design problem.** `scripts/` is one flat directory: 149 production files beside 203 test and record files. About 45 of the small production files are small because GDScript allows one `class_name` per file (Resource schemas, pure helpers, single visuals). That is normal Godot and should stay. The real fragmentation is about 6 copy-paste clusters (boss behaviors, 3 identical station scripts, 6 modal panels, 5 freeze counters, 3 music players, fishy_guard).
- **The bigger extensibility cost is the opposite of fragmentation.** Five hub files (`main.gd` 815 lines, `spell_caster.gd`, `projectile.gd`, `spell.gd`, `spell_description.gd`) get edited by nearly every new enemy, spell or dungeon. `main.gd` decides dungeon behavior by area node name (verified).
- **Tests cost more than they protect.** Test code is 31.5k lines against 20.7k production. Each harness re-implements its own pass/fail contract, about 2,650 lines of boilerplate. 35% of recent test edits touched a test for an unrelated issue, mostly because tests pin content counts and tuning constants.
- **Performance is fine at today's scale except pathfinding.** Enemy A* costs 41-121 ms per call when the target is unreachable, and it replans every 0.25 s. The root cause is `TerrainMap.type_properties` allocating a Dictionary on every cell query, plus an O(n^2) open list.
- **Quick wins with no design debate:** fix test348, add a test runner with `--fixed-fps 60` (3-6x faster), stop shipping tests in the web export, name collision layers, and pick one player lookup.

## Key numbers

| Metric | Value | Source |
|---|---|---|
| Production scripts (`scripts/*.gd`, not test/record) | 149 files, 20,683 lines | measured |
| Test harnesses `scripts/test*.gd` | 191 files, 31,498 lines | verified count |
| Record scripts (`scripts/record*` + `tools/showcase`) | 12 + 19, about 3,350 lines | measured |
| Production files over 300 lines / under 40 lines | 19 / 33 | measured |
| `main.gd` | 815 lines, about 11 responsibilities | verified length |
| Comment share of production lines | 24% (1,068 `#NNN` issue refs) | measured |
| Group lookups in production code | 71 | verified |
| Harnesses printing `RESULT: ALL PASS` | 42 of 191 | verified |
| Harnesses that never `quit(code)` | 16 | measured |
| Duplicated harness boilerplate | about 2,650 lines (8.6%) | measured |
| Recent test edits touching another issue's test | 26 of 75 (35%) | measured |
| Harness wall time, real-time vs `--fixed-fps 60` | test461 3.5 s vs 0.55 s | measured |
| A* `_find_path`, p90 / capped far goal | 57-69 ms / 41-54 ms | measured |
| `TerrainMap.set_cell` (full rebuild) | 1.5-3.7 ms | measured |
| Var / return / param annotation coverage | 99.9% / 100% / 98.1% | measured |
| Bare `Dictionary` vs typed `Dictionary[...]` | 124 vs 1 | measured |
| `.gd` files in `scripts/` without a committed `.uid` | 67 (14 production) | verified |
| Web export `exclude_filter` | empty, ships 203 test/record scripts | verified |

## Findings, ranked

### 1. No test gate, and `main` is red (verified)

- **Evidence.**
  - `.github/workflows/` holds `claude.yml`, `claude-code-review.yml`, `deploy.yml`. None runs a harness. `deploy.yml:51-53` only imports and exports.
  - `test348_cleared_dungeon.gd` exits 1 at HEAD. Two runs disagreed on the count: one had 4 FAILs, the other 5. Both include `(B) 17 total ... (got 18)` and `(E) every entrance is guarded again, all 21 ... (got 22)`. The extra FAIL is `uncleared: 21 around the 5 entrances ... (got 22)`, so the initial guard count is also nondeterministic. 62abe4d (#492) updated these literals, and the next merge (#468, tall grass) broke them again.
  - 16 harnesses call bare `quit()` or end via `_process() -> true`, e.g. `test100_spawn_data.gd:192`, `test9_exit_flow.gd:142`, `test_spell_tags.gd:52`.
  - 14 `test*.gd` files have no assertion at all (debug maps, demo and movie drivers such as `test290_visual.gd`). A glob runner would hang on them or count them as passes.
  - README.md:76-88 asks people to compare against a remembered baseline of about 190 `SCRIPT ERROR`s.
- **Principles.** PIW, ELS, BTL.
- **Recommendation.** Fix test348 by deriving the expected counts from the scene's `EntranceGuards` data instead of literals, and find the source of the 21/22 nondeterminism. Add a GDScript runner (`tests/run.gd`). It must be GDScript because the `@claude` CI allowlist permits `godot` but not shell scripts. It globs harnesses, runs each as a child process with `--fixed-fps 60` and a timeout, runs N in parallel, accepts a filter, and exits non-zero on any failure. A human adds `test.yml`, since the CI app has no `workflows` permission.
- **Effort.** S (test348), M (runner + triage of whatever else is red).

### 2. Dungeon identity is keyed on area node names (verified)

- **Evidence.** `main.gd:498-547` is an `if area.name == "DungeonA" ... elif "DungeonE" or "DungeonMaze"` chain that sets `dungeon_id`, objective type, boss scene and boss spawn. More name checks: `:324` (`_area_is_red`), `:573` `BOSS_THEME_ARENAS`, `:607` exit-portal list, `:622` lock rule, `:626` Beast portal look, `:683` revive item. A second registry is `fast_travel_routes.gd:9-16`. A third rule is `dungeon_music.gd:31-32` (`begins_with("Dungeon")`). Each dungeon has three identities that must agree: node name, `&"dungeon_x"` id, and scene path. The header at `main.gd:15` claims "No area-name checks ... remain in code", which is false. The dungeon-creation skill is an 8-item checklist that works around the gap.
- **Principles.** MTD, ELS, MRL.
- **Recommendation.** Add a `DungeonDefinition` Resource (`id`, `label`, `scene`, objective sub-resource with `boss_scene`, `boss_spawn` or a `BossSpawn` Marker2D, wave config, `boss_theme`, `locks_portal`, `portal_look`, extras). Put one `.tres` per dungeon in `data/dungeons/`, and have the area root export it. `_mount_objective`, `_mount_exit_portal`, music and `FastTravelRoutes` read the definition. Delete every name branch in the same PR (MCD). Add a test asserting every `scenes/dungeon_*.tscn` has a definition. The data/docs pass called this `AreaConfig`; same design.
- **Effort.** M. Tests 9, 100, 349, 366, 396 and the gate-enumerating tests cover the flows.

### 3. `main.gd` and four other hub files absorb every feature

- **Evidence.** `main.gd` (815 lines) does service boot, area swap, gate cooldowns, offering rolls, location events, entrance guards, objective config, music policy, portal policy, revive item, and fast/map travel. The spell upgrade catalog is 30 `preload`s at `main.gd:139-195`. About 40% of the file is narrative comments. `projectile.gd:31-57` `SPELL_SPRITE_ANIMS` maps spell **display names** to art, so renaming a spell changes its sprite. `bestiary.gd:25-80` and `boss_relic_drop.gd:23` hold hand lists that every new enemy or relic must edit.
- **Principles.** MRL, MTD.
- **Recommendation.** After finding 2, split `main.gd` into `Main` (boot), `AreaLoader` (swap and mount from `DungeonDefinition`) and `TravelService` (gates, cooldowns, offerings, travel, `cleared_dungeons`). Merge `boss_music.gd`, `dungeon_music.gd`, `overworld_ambience.gd` into one `MusicDirector`. Load upgrades from `data/upgrades/`. Add `Spell.id` and `Spell.projectile_anim` and delete `SPELL_SPRITE_ANIMS`. Move bestiary fields onto `EnemyDefinition`. Keep thin forwarders for `main._swap` and friends for one wave, then migrate tests and delete them (MCD).
- **Effort.** S for `Spell.id`/anim and bestiary fields; M for the split.

### 4. Spell kind is implied by which of ~61 optional fields is non-zero

- **Evidence.** `spell.gd:8-174` holds projectile, `freeze_*`, `rain_*`, `shield_*`, 16 `hammer_*`, `summon` and `terrain_block` fields on one Resource. `spell_caster.gd:575-614` dispatches with `if spell.hammer_radius > 0 ... elif spell.shield_radius > 0 ...`. The same chain repeats in `spell_description.gd:12-40`, `stat_sheet.gd` and `hud.gd`. 42 spell and 30 upgrade `.tres` files depend on the shape.
- **Principles.** TSD, MTD, MCD.
- **Recommendation.** Add `Spell.effect: SpellEffect` with `cast()` and `describe()`, and subclasses per mode (projectile fan-out, hammer, shield, rain, splash, terrain block). Migrate one mode per PR with a `.tres` converter script, deleting that mode's branch and fields in the same PR. The two passes disagreed on timing: architecture said start now, data/docs said wait for the next mechanic. Resolution: land finding 3's `Spell.id` now, and start the effect migration with the PR that adds the next spell mechanic. That PR would otherwise grow the chain in four files.
- **Effort.** L in total, S-M per mode.

### 5. Every harness re-implements the test contract; tests live flat in `scripts/`

- **Evidence.** 152 files define their own `_check` with 7 signatures (22 take `(label, ok)`, reversed). 161 declare their own failure counter, and 44 define the same `_frames(n)`. `player.tscn` is instantiated in 65 tests, `enemy.tscn` in 58. 645 references to private members across 96 files, e.g. `_on_body_entered` called directly 78 times, which skips the physics wiring that actually breaks. 55 tests are `_process(delta) -> bool` phase machines. Issue-number filenames hide which system a test covers (#305 is split over 5 files).
- **Principles.** ELS, MRL, BTL, TBI.
- **Recommendation.** Write `tests/support/gang_test.gd` by hand (about 80 lines: `check`, `eq` printing expected vs got, `frames`, `until`, `boot_main`, a `stage` fixture builder, timeout watchdog, guaranteed exit code). Migrate all harnesses with a codemod and confirm pass counts match before and after. Then move to `tests/<feature>/<behavior>_test.gd` with an `## Issues: #461` header line (see appendix). Use an in-house base, not GUT or gdUnit4: process-per-test isolation matches the D10 reload model, and the gap is one base class plus one runner.
- **Effort.** M (base + codemod), M (scripted move).

### 6. Terrain queries allocate, which makes enemy pathfinding spike (measured)

- **Evidence.** `TerrainMap.type_properties` returns a fresh Dictionary and Array per call: 1.25-1.6 us vs 0.08 us for a plain lookup (`terrain_types.gd:186-200`, `terrain_palette.gd:41-49`). It sits inside nearly every hot path: `enemy.gd:170` concealment per frame, `terrain_motion.gd`, `flow_nav.gd:140`, `terrain_path.gd:87/94`. `terrain_path.gd:102-163` uses a plain Array open list with a linear `_pop_lowest_f` and `open.has`, about 20 allocations per expansion, capped at `MAX_EXPANSIONS = 2000`, replanned every 0.25 s (`:31`). Measured: p90 57-69 ms, max 91-121 ms, capped far goal 41-54 ms. Related: `FlowNav` (`flow_nav.gd:103-125`) wipes all 8 cached fields when full and on any cell change, 2.1-2.9 ms per rebuild. `TerrainMap.set_cell` rebuilds the whole presentation, 1.5-3.7 ms per changed cell. `TerrainBlockVisuals` polls `assigned_cells()` every physics tick, about 200 us.
- **Principles.** FRC (fix the allocating query once, not each caller), explain-the-number, PIW.
- **Recommendation.** In order: a precomputed per-type property table with allocation-free predicates (`is_walkable_cell`, `blocks_projectiles_cell`, `conceals_cell`); a binary-heap A* with an in-open Dictionary, `const` direction arrays, and backoff after hitting the cap; LRU eviction in FlowNav; a `cell_changed` signal on `TerrainMap` replacing the TerrainBlockVisuals poll; incremental `set_cell` that re-autotiles one cell and its 8 neighbours. Re-run the bench on 4.5.1 before and after, and capture in-game p50/p99 frame time with 8 chasers and the player in water. Do not raise `REPLAN_INTERVAL` to hide the cost.
- **Effort.** S-M (table), M (A*), S (FlowNav, signal), M (incremental set_cell).

### 7. The three boss behaviors are copies of one state machine

- **Evidence.** `enemy_behavior_warlord.gd` (280 lines), `_head.gd` (286), `_beast.gd` (263) share the `State` enum, `is_enraged` (`hp*2 <= max_hp`), identical `_pick_attack` history code (head:136-144, beast:126-134), `_start_windup`/`_enter_*`/`_face`, and the same `physics_step` prologue. Boss chase contact calls `player.apply_damage` directly, which bypasses DamageCalc and the D9 OnHit bus. All 10 enemy and boss scenes also re-declare the same node tree instead of inheriting `enemy.tscn`; `beast_boss.tscn` and `head_boss.tscn` differ only in numbers and colors.
- **Principles.** SBA, MTD, FRC.
- **Recommendation.** Add `BossBehavior` with the state machine, telegraph lifecycle, phase threshold, anti-repeat picker and contact damage routed through DamageCalc. Each boss supplies `attacks: Array[BossAttack]`. Keep constants identical so test177 and the Head/Beast timing tests pass unchanged. Add `enemy_base.tscn` / `boss_base.tscn` as inherited scenes, keeping node names (`Sprite`, `Telegraph`) that tests reference.
- **Effort.** M each.

### 8. Behavior variants are new script files instead of data

- **Evidence.** `EnemyDefinition.behavior: Script` (`enemy_definition.gd:31`); `enemy.gd:80-84` checks `has_method("physics_step")`. `enemy_behavior_fishy_guard.gd` (16 lines) exists only to change two constants. Stats live in both `enemy.gd:15-34` exports and `EnemyDefinition`, synced by hand. Spawning has 5 paths (`EnemySpawner`, `wolf_cave.gd:91-103`, `overworld_bird.gd:81`, `dungeon_objective.gd:164`, `enemy_slime.gd:104`), and behaviors get context through `set_meta` strings (`wolf_anchor`, `bird_manager`).
- **Principles.** MTD, TSD.
- **Recommendation.** `class_name EnemyBehavior extends Resource` with `@export` tuning, duplicated per instance. Delete `fishy_guard.gd` in favour of a `.tres`. Make `definition` required and remove the duplicate exports from `enemy.gd`. Route all spawns through `EnemySpawner.spawn(scene, pos, opts)` and pass typed owner fields instead of meta.
- **Effort.** M (14 behaviors, mechanical), M (spawner).

### 9. Player and service lookup: two group names, one dead (verified)

- **Evidence.** `player.gd:147` joins `ActorCollision.PLAYER_GROUP = &"players"` (`actor_collision.gd:16`). Eight scripts fall back to `get_first_node_in_group("player")`: `enemy.gd:90`, `hud.gd:89`, `equip_panel.gd:184`, `shop.gd:82`, `summon_manager.gd:33`, `spell_directory_panel.gd:58`, `overworld_bird.gd:113`, `run_manager.gd:51`. A ninth use is `terrain_block.gd:51`. Only 8 test scenes put a node in `"player"`. ARCHITECTURE.md D6 and several comments say the production player is in no group, which has been false since #290.
- **Does production break?** No path found. Main wires each consumer explicitly (`hud.player_path`, `rm.player`, `shop.caster_path`, `summon_manager.caster_path`, `../../Player` for area nodes and bosses), and `spell_directory.gd` hands the caster to the panel on open. `TerrainBlock.blockers_in` misses the player in the group loop but adds it as `caster_owner`, and only the player's caster calls it. The fallback is a compatibility layer kept alive for test fixtures.
- **Principles.** MCD, TSD, MRL.
- **Recommendation.** Pick one mechanism (`Player.GROUP` used everywhere, or a typed `Run` accessor). Change the 8 test scenes, delete the `"player"` fallbacks and the repeated "no group" comments, fix D6. A later step replaces the 71 string-group service lookups (`owned_relics`, `currency_wallet`, `reward_pool`, `modal_ui`) and 14 `NodePath("../Player")` literals with the same accessor.
- **Effort.** S (player), M (services).

### 10. One collision layer for everything (suspected)

- **Evidence.** No production `.tscn` or script sets `collision_layer`/`collision_mask` except `projectile.gd:576`; `project.godot` has no layer names. `actor_collision.gd` adds a collision exception per player-enemy pair at runtime. `projectile.gd:572-600` `intersect_shape(params, 8)` caps at 8 results, so in a crowd irrelevant bodies can fill the slots and a real hit is missed. That is a correctness risk, not only cost.
- **Principles.** MTD, FRC.
- **Recommendation.** Name layers (world, player, enemy, summon, player_projectile, enemy_projectile, pickup), set masks per scene, delete `ActorCollision`. Add a test with 8+ non-enemy bodies around a projectile that must still hit the enemy.
- **Effort.** M.

### 11. Web export ships all tests and record scripts (verified)

- **Evidence.** `export_presets.cfg:11` `exclude_filter=""` with `all_resources`. That packs 203 test/record scripts (1.7 MB source) and 18 test scenes into every web download.
- **Principles.** SBA, PIW.
- **Recommendation.** `exclude_filter="scripts/test*, scripts/record*, scenes/test*, scenes/record*, tools/*"`, updated to `tests/*` after the move. Verify by comparing `.pck` size before and after and booting the web build.
- **Effort.** S.

### 12. Tests pin content counts and tuning constants

- **Evidence.** test348 (finding 1). `test96_projectile_visual.gd:88-89` asserts `Projectile.SPIN_RATE == 12.0`; `test448_day_night.gd:18` pins `CYCLE_SECONDS == 600.0`; `test173_head_boss.gd:94` pins `max_hp == 320` labelled "PLACEHOLDER". 25 checks compare tuning values to literals. 63 tests boot full `main.tscn`, so any hub or overworld content change can shift their counts.
- **Principles.** TBI.
- **Recommendation.** Delete constant pins. Assert relations derived from data ("the cleared gate loses exactly its own group"). Prefer a small built stage over `main.tscn` unless the test is about wiring.
- **Effort.** M (30-40 sites).

### Smaller findings

| Finding | Evidence | Principle | Recommendation | Effort | Status |
|---|---|---|---|---|---|
| 3 byte-identical station scripts; 6 panels repeat open/close/`modal_ui` | `bestiary_station.gd`, `shop_vendor.gd`, `spell_directory.gd`; `shop_panel.gd:52-59` etc. | SBA, ELS | One `PanelStation` with `@export panel_group`; `ModalPanel` base | S | measured (diff) |
| Freeze counter re-implemented in 5 movers, pull scans per frame | `enemy.gd:269`, `projectile.gd:115-130`, `summon.gd`, `water_rain.gd:42-52`, `water_splash.gd:43-61` | MTD, SBA | `Freezable` component; `FreezeBubble` pushes `claim()` | S-M | suspected |
| Typing is enforced by habit only; shape data in untyped dicts | 124 bare `Dictionary`, 1 typed; `AreaSpawnData.entries: Array[Dictionary]` (`area_spawn_data.gd:11-20`); 34 `has_method` | TSD, ELS | Set `untyped_declaration=2`, unsafe access warnings; `SpawnEntry` Resource; typed `EnemyBehavior` | M | measured |
| 14 production scripts lack a committed `.uid` | `enemy.gd`, `hud.gd`, `projectile.gd`, `spell_caster.gd` ... | ELS | Commit all `.uid`s from 4.5.1; CI check; delete the skill's prose rule | S | verified |
| Hotkeys bypass the input map | `spell_caster.gd:77-78` Q/E/R/F, `consumables.gd:29`, `spirit_meter.gd:30`, `map_panel.gd:57`, `equip_panel.gd:177` | MTD | Add actions; derive slot labels from `InputMap` | S | suspected |
| Per-frame tree walks and polls | `hud.gd:223,241` `find_child` 4x/s; `gate.gd:211-240` label placement; `day_night_tint.gd:11-14` | FRC | Main hands HUD the objective node; cache lookups | S each | suspected |
| Overworld ground is one huge `_draw` item, never partially culled | `overworld_ground.gd:419-433`, about 5k draw commands | explain-the-number | `TileMapLayer` or 512 px chunks; measure draw calls on web | M | suspected |
| ARCHITECTURE.md stale and 40 KB | anchor 221 commits behind; D6, D17, D20 wrong; two `D23` headings | MRL, SBA | Trim to rule + `Where`; script that greps `Where:` symbols | S-M | suspected |
| README stale, `docs/plans` stub, no CLAUDE.md | `README.md:49`, `:14-19`; `docs/plans/132-shop-stock-refresh.md` | SBA, MRL | Refresh README; delete plan; add a short CLAUDE.md | S | suspected |
| Machine-specific screenshot paths in tests | `test245_visual.gd:64` `/downloads/`; `test315_upgrade_token.gd:37` `/tmp/ci/` | idempotency | `GangTest.shot(name)` to `GANGU_SHOTS` or `user://` | S | suspected |
| `project.godot` features say Forward Plus; renderer is gl_compatibility | `project.godot:12` | MRL | Resave in editor | S | verified |

Checked and fine (no action): projectile instancing (about 50 us, no pooling needed), runtime `load()` only on cold paths, texture imports, `gl_compatibility` with threads off, Resource-based game data, repo hygiene.

## Roadmap

Each unit is one PR that lands on its own and ends in a state you can check. Subtractions come before new structure.

### Phase 1: quick wins

| # | Unit | Done when |
|---|---|---|
| 1 | Fix test348: derive counts from `EntranceGuards`, find the 21/22 nondeterminism | 10 consecutive runs exit 0 |
| 2 | Fix the 16 harnesses that cannot fail; relocate the 14 no-assert files to `tools/capture/` | Every remaining `test*.gd` exits non-zero on a forced FAIL |
| 3 | `tests/run.gd` runner: `--fixed-fps 60`, `-j N`, filter, timeout, summary | Full suite runs in under 3 min locally; red list recorded in the PR |
| 4 | Human adds `.github/workflows/test.yml` calling the runner on `pull_request` | A PR that breaks test348 shows a red check |
| 5 | Export `exclude_filter` for test/record/tools | `.pck` smaller by the test payload; web build boots |
| 6 | Commit missing `.uid`s; CI check for `.gd` without `.uid` | `git status` clean after an editor open; check fails on a new bare `.gd` |
| 7 | One player lookup: change 8 test scenes, delete `"player"` fallbacks, fix D6 | `grep '"player"' scripts/` returns no production hits; suite green |
| 8 | Named collision layers and masks; delete `ActorCollision` | Crowd-projectile test passes; suite green |

### Phase 2: subtraction

| # | Unit | Done when |
|---|---|---|
| 9 | `PanelStation` and `ModalPanel` replace 3 stations and 6 panel copies | Hub opens all three panels; station tests green |
| 10 | Delete constant pins and content-count literals (finding 12) | No test asserts a tuning constant; suite green |
| 11 | Human decisions below (inert foundations, recorders) applied | Files deleted or moved; `main.gd` no longer mounts inert systems |

### Phase 3: structure

| # | Unit | Done when |
|---|---|---|
| 12 | `GangTest` base class + codemod over all harnesses | Per-file PASS counts identical before and after |
| 13 | Scripted move to `tests/<feature>/` (quiet window, one PR, no logic change) | Runner filter `-- terrain` runs only terrain tests; docs paths updated |
| 14 | Terrain property table + allocation-free predicates | Bench: `conceals_at` near dict-lookup cost; suite green |
| 15 | Heap A*, cap backoff; FlowNav LRU; `cell_changed` signal; incremental `set_cell` (one PR each) | Bench p90 for `_find_path` under 5 ms; frame-time capture with 8 chasers shows no spikes over 16 ms |
| 16 | `Spell.id` + `projectile_anim`; delete `SPELL_SPRITE_ANIMS`; bestiary fields on `EnemyDefinition` | Renaming a spell's display name changes nothing else |
| 17 | `DungeonDefinition` + `.tres` per dungeon; delete all `area.name` branches | `grep 'area.name ==' scripts/main.gd` is empty; dungeon-creation skill shrinks to 3 steps |
| 18 | Split `main.gd` into Main / AreaLoader / TravelService / MusicDirector; migrate test callers, delete forwarders | `main.gd` under 250 lines; suite green |
| 19 | `EnemyBehavior` Resource; delete `fishy_guard.gd`; single `EnemySpawner.spawn` path | No `set_meta` in behaviors; no `has_method("physics_step")` |
| 20 | `BossBehavior` base + inherited enemy/boss scenes | Each boss behavior under about 120 lines; boss timing tests unchanged |
| 21 | `SpellEffect`, one mode per PR, starting with the next new mechanic | Each PR removes one `elif` from all four dispatch sites |
| 22 | Feature-folder layout for production scripts (appendix), one mechanical PR | No file in `scripts/` root; all `res://` paths resolve; suite green |

Units 13 and 22 move files and conflict with every open PR. Land them back to back in a quiet window.

## Decisions for a human

1. **Delete 9 inert foundation scripts?** `dungeon_modifier.gd`, `dungeon_modifier_effect.gd`, `dungeon_modifier_host.gd` (wired at `main.gd:363-371`, no scene or `.tres` uses them); `location_trigger.gd`, `overworld_event.gd`, `overworld_event_context.gd`, `ambush_event.gd` (D22: no scene places one); `consumable.gd`, `consumables.gd` (`main.gd:88-96`, "the manager is inert"). These were approved foundation issues. Options: delete with their pinning tests (test222, test365, consumables tests), or move to `experimental/` and stop mounting them. Recommendation: delete; git keeps them.
2. **Delete about 30 per-issue record scripts?** The 12 `scripts/record*.gd` plus the numbered `tools/showcase/record4*.gd`, keeping `record_showcase.gd` and the reusable tours (`dungeon_terrain_tour`, `maze_*`, `record_boss_wave`, `record_defense_waves`). Nothing references them; the evidence lives in the PRs. Recommendation: delete, keep reusable drivers, and add a `Scenario` beat driver on top of the `GangTest` stage.
3. **Who adds `test.yml`?** The CI app cannot edit workflows.
4. **`Run` autoload vs `static var current: Main`** for typed service access. An autoload must not outlive a D10 reload.
5. **When to start the `SpellEffect` migration** (finding 4).
6. **Delete orphans:** `resources/enemies/slime_guard.tres`, `scenes/test10_pickup_arena.tscn`, `scenes/test_grid_scroll.tscn`, `scenes/background_grid.tscn` (production uses `BackgroundGrid.new()`), `docs/plans/`.
7. **A window for the two file moves** (units 13 and 22).

## Appendix: proposed layouts

### Production scripts (feature folders, scene next to script)

Move each `.gd.uid` with its `.gd`. `*` marks a new file from a finding.

```
game/
  core/        main.gd, area_loader.gd*, travel_service.gd*, run_manager.gd, run.gd*,
               camera_follow.gd, background_grid.gd, day_night_clock.gd, day_night_tint.gd
  combat/      damage_calc, damage_modifier(s), damage_result, hit_event, on_hit, combat_effects,
               damage_number, stat_modifier, freezable.gd*
  player/      player.gd/.tscn, player_stats, spirit_meter, revive_satchel, revive_item
  spells/      spell, spell_caster, spell_loadout*, spell_tags, spell_fanout, spell_upgrade,
               spell_progress, spell_description, projectile.gd/.tscn, spell_pickup
    effects/   spell_effect*, water_splash, water_rain, water_shield, freeze_bubble,
               stone_hammer, stone_hammer_state, hammer_vortex, hammer_dice, terrain_block(_visuals)
    summons/   summon, summon_manager, summon_behavior_guard, summon_definition
  enemies/     enemy.gd/.tscn, enemy_definition, enemy_sprite, enemy_spawner, enemy_slime,
               barricade, mustache_voice, fishing_line, rock_visual, warlord_orb_visual
    behaviors/ enemy_behavior* (base), chase_contact, guard, patrol, migrate, cover,
               barricader, wolf, bird, fishy
    bosses/    boss_behavior*, warlord, head, beast, boss_telegraph, boss_health_bar,
               boss_relic_drop + boss scenes
    spawners/  wolf_cave(s), overworld_bird
  world/       gate, gate_offering, exit_portal, area_spawn_data, entrance_guards,
               dungeon_definition*, dungeon_objective, defense_core, fast_travel_routes,
               world_map, hub_floor, overworld_ground, tall_grass, generated_dungeon,
               maze_defense_dungeon + area scenes
    terrain/   terrain_* (17 files), flow_nav, maze_gen
  economy/     reward_entry/table/pool/drop, shop, shop_catalog/entry/refresh_schedule,
               currency_wallet, relic, owned_relics, destroyable_container, container_definition
  ui/          hud, modal_panel*, panel_station*, equip_panel, shop_panel, bestiary_panel,
               bestiary, spell_directory_panel, map_panel, map_canvas, fast_travel_panel,
               defense_wave_bar, stat_grid, stat_icon, stat_sheet, spell_icon,
               spell_rank_border, relic_icon, upgrade_card, ui_style
  audio/       music_director* (boss_music + dungeon_music + overworld_ambience)
data/          today's resources/: spells/, upgrades/, enemies/, dungeons/*, relics/,
               rewards/, shop/, terrain_*/, sprites/
```

### Tests and capture tools

```
tests/
  run.gd                  runner
  support/gang_test.gd    base class and stage fixtures
  unit/                   no scene tree content (damage_calc, spell_tags, ...)
  terrain/ enemies/ spells/ ui/ world/ run/
  fixtures/               today's scenes/test*.tscn and their Node2D scripts
tools/capture/            reusable record drivers, *_visual, *_demo, showcase; never globbed by the runner
```

Name tests `<behavior>_test.gd` with an `## Issues: #NNN` header so `grep -r '#461' tests/` still works.

### Consolidation map

| Current | Target | Finding |
|---|---|---|
| `bestiary_station.gd`, `shop_vendor.gd`, `spell_directory.gd` | `ui/panel_station.gd`, 3 scene instances | small table |
| open/close/`modal_ui` code in 6 `*_panel.gd` | `ui/modal_panel.gd` base | small table |
| `_rank_tier` / `_can_upgrade` in `hud.gd` and `equip_panel.gd` | typed methods on `spell_progress.gd` | small table |
| `boss_music.gd`, `dungeon_music.gd`, `overworld_ambience.gd` + 6 `main.gd` call sites | `audio/music_director.gd` | 3 |
| `enemy_behavior_fishy_guard.gd` | `data/enemies/overworld_fishy.tres` | 8 |
| all `enemy_behavior_*.gd` (`RefCounted` + `has_method`) | `extends EnemyBehavior` (Resource) | 8 |
| shared parts of warlord/head/beast behaviors | `bosses/boss_behavior.gd` + 3 thin subclasses | 7 |
| freeze counters in 5 movers | `combat/freezable.gd` | small table |
| spawn code in wolf_cave, overworld_bird, dungeon_objective, enemy_slime + `set_meta` | `EnemySpawner.spawn(scene, pos, SpawnOptions)` | 8 |
| `main.gd` name branches + `FastTravelRoutes.DUNGEONS` + `DungeonMusic.is_dungeon_area` | `world/dungeon_definition.gd` + `data/dungeons/*.tres` | 2 |
| `main.gd` (815 lines) | `core/main.gd` + `area_loader.gd` + `travel_service.gd` | 3 |
| `main.gd:139-195` upgrade preloads | loaded from `data/upgrades/` | 3 |
| `projectile.gd` `SPELL_SPRITE_ANIMS` | `Spell.projectile_anim` | 3 |
| mode fields in `spell.gd` + elif chains in 4 files | `spells/effects/spell_effect.gd` + per-mode resources | 4 |
| `spell_caster.gd` slots and cooldowns | `spells/spell_loadout.gd` | 3 |
| string group lookups + `"player"` fallback | `core/run.gd` typed accessor | 9 |
| `bestiary.gd` hard-coded entries | fields on `EnemyDefinition` | 3 |
| dungeon modifiers, location events, consumables | delete, or `experimental/` unmounted | decision 1 |
| Resource schemas, pure helpers, single visuals, `wolf_cave` + `wolf_caves`, the three water effects | move to their folder only | keep |

Net effect: about 149 to about 135 production scripts. The count barely moves. What changes is that adding an enemy, spell or dungeon stops editing `main.gd`, `spell_caster.gd`, `projectile.gd`, `spell_description.gd` and `bestiary.gd`.
