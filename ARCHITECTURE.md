# gangU - Key Architectural Decisions

Tracking issue: #39. Checked against main @ `d2108e9207608bf1203948a9480417c90c2fd232` (#521 refresh).
Each entry is the rule, then where it lives. History and quotes stay in the linked issues and in the
code comments. Status is one of:

- **Implemented** - merged and verifiable in the current source.
- **Provisional** - merged as a labeled default, explicitly not settled.
- **Open** - a human choice; no code may presume an answer.

---

## Implemented decisions

### D1. Platform and stack
Godot **4.5.1-stable** (pinned exactly) + GDScript. Web/HTML5 is a first-class target: renderer `gl_compatibility` (desktop and web) and thread support OFF so the build runs on plain static hosting without COOP/COEP headers.
*Where:* `project.godot`, `export_presets.cfg`, README.

### D2. Display contract
Viewport 1152x648, stretch mode `canvas_items`, aspect `expand`. Layout claims are checked at more than one window size before merge (#50 tracks a known cosmetic overlap).
*Where:* `project.godot`.

### D3. Input: shared actions, manual aim only
`move_up/down/left/right` (WASD), `cast` (Space) and `dash` (Shift) are defined once in `project.godot`. The six spell-slot keys (LMB, RMB, Q, E, R, F; #319) are registered at runtime by `SpellCaster`. `switch_spell` exists with **no key bound**. Manual aim only, no aim assist; keyboard + mouse, trackpad-friendly.
*Where:* `project.godot`, `game/spells/spell_caster.gd` (`SLOT_KEYCODES`), `game/player/player.gd`.

### D4. One Main scene; systems are code-mounted, not scene-edited
`game/core/main.tscn` stays minimal (Player + FollowCamera). `main.gd._ready()` mounts the run's services in code (BackgroundGrid, RunManager, HUD, ReviveSatchel, wallet, reward pool, shop, panels, WorldMap, settings...) and, since #512, three service children reached as public vars: `main.area_loader` (`AreaLoader`: `_swap()` mounts per-area content - spawns, entrance guards, triggers, objective, exit portal, revive item, modifiers - and keeps the run's clear/cooldown/offering/location-event records), `main.travel` (`TravelService`: #349/#366 fast and map travel) and `main.music` (`MusicDirector`: boss, dungeon and overworld music). Areas stay `Main/<Area>` children so relative NodePaths are unchanged. Keeps shared scene files out of merge contention and mount order explicit.
*Where:* `game/core/main.gd`, `game/core/area_loader.gd`, `game/core/travel_service.gd`, `game/audio/music_director.gd`.

### D5. The shared Player is never recreated during a run
Area swaps reposition the existing Player at the area's `PlayerSpawn`; HP, spells and items persist across travel. The only reset is RunManager's full scene reload on death (D10). Transport is deferred because it starts inside physics callbacks (D14).
*Where:* `game/core/area_loader.gd` (`_swap`, `_on_gate_entered`, `_on_exit_portal_entered`), `game/core/travel_service.gd` (fast/map travel commits).

### D6. Explicit wiring beats group lookups in production
Cross-node references are exported NodePaths (`player_path`, `objective_path`) set **before** the node enters the tree, resolved in `_ready`. Every Player joins the `players` group (`ActorCollision.PLAYER_GROUP`) in `_ready`; when a node has no explicit wiring (test fixtures), `Player.find(tree)` is the one fallback lookup. There is no other player group. ReviveSatchel has no fallback at all (accepted #6/#12 contract - a missing `player_path` is an error, not a silent idle).
*Where:* `game/player/player.gd` (`find`), `game/core/main.gd`, `game/ui/hud.gd`, `game/enemies/enemy.gd`, `game/core/run_manager.gd`, `game/player/revive_satchel.gd`; gap history in #34.

### D7. Single HP mutation entry points
`Player.apply_damage()` / `Player.heal()` and `Enemy.apply_damage()` are the only places HP changes. Each clamps and emits `health_changed`; `died()` fires exactly once at HP 0. `heal()` works from HP 0 (the revive path).
*Where:* `game/player/player.gd`, `game/enemies/enemy.gd`.

### D8. Spells are data; the caster owns collection, cooldowns and slots
Spell stats live on `Spell` resources (`data/spells/*.tres`), never in casting logic. `SpellCaster` owns the unlocked spells, the six equip slots, per-spell cooldowns and switching.
*Where:* `game/spells/spell.gd`, `game/spells/spell_caster.gd`.

### D9. Systems talk through signals, not reach-ins
Published contracts include `Player.health_changed/died`, `SpellCaster.spell_cast/cooldown_started/spell_equipped/spell_added`, `Enemy.died/health_changed`, `DungeonObjective.objective_progress_changed/objective_completed/objective_failed`, `Gate.entered`, `ExitPortal.entered`, `ReviveSatchel.revive_collected/revive_used`, `RunManager.run_restarting`. Producers never know their listeners.
**On-hit (#390):** every DamageCalc call site reports a landed hit on `OnHit.bus().hit_landed(HitEvent)`. Call sites wrap the apply in `OnHit.begin(target)` / `OnHit.end(receipt, target)`; receivers call `OnHit.record(self, hp_before, hp_after)` at their HP mutation point. A hit lands only if the receiver accepted it (an accepted 0-damage hit lands with `hp_lost` 0). `HitEvent` carries `attacker` (may be null), `spell` (null for contact), `target`, `result` (the roll), `hp_lost`, `killed`, `delivery`, `position`. Hits that bypass DamageCalc (boss lunge/pulse/spin/scream) do not report. `test390_on_hit` pins it.
*Where:* the scripts above; `game/combat/on_hit.gd`, `game/combat/hit_event.gd`.

### D10. Death means a full run restart; revive intercepts synchronously
On `died()`, RunManager first offers the satchel a synchronous `try_revive()`; a carried item cancels the restart. Otherwise it disables the player's casters and reloads the whole scene after a short delay. The satchel has **no** `died()` listener: the run manager owns interception order.
Death is a FULL reset (#351): world, cleared dungeons, spells, upgrades, coins and the map. Run state living outside the reloaded scene (autoloads, root-parked nodes) joins the `run_state` group (`RunManager.RUN_STATE_GROUP`) and implements `reset_run_state()`, called right before the reload. Cross-run meta records (Bestiary #325) are not run state. `test351_full_reset` pins it.
*Where:* `game/core/run_manager.gd`, `game/player/revive_satchel.gd`.

### D11. Objectives are data-driven, one node per dungeon, mounted after enemies
`DungeonObjective` types: `CLEAR_ALL_ENEMIES` (target 0 = every enemy present at ready), `DEFEAT_BOSS`, `ELIMINATION` (mobs, then a boss) and `DEFENSE` (protect a `DefenseCore` through waves the objective spawns; a destroyed core emits `objective_failed`). It scans the `enemies` group in `_ready`, so AreaLoader mounts it **after** the area's enemies. Completion emits `objective_completed(dungeon_id)`. Per dungeon: A CLEAR_ALL; B ELIMINATION (mobs + Mustache Warlord, O1); C and D ELIMINATION with zero mobs (Head, O6; Beast, O7); E and Maze DEFENSE (O10, O12, boss waves O14).
*Where:* `game/world/dungeon_objective.gd`, `game/core/area_loader.gd` (`_mount_objective`).

### D12. Exit portals: retreat-anytime on normal, clear-or-die on red
Normal-gate dungeons mount the portal **unlocked**; red-gate dungeons (by the type of the gate actually entered, #350) and the boss arenas (C, D) mount it **locked** until `objective_completed`. A locked portal also opens on `objective_failed` so a failed defense cannot soft-lock. Using a portal returns the player to that dungeon's overworld entrance in the same run (#378).
*Where:* `game/world/exit_portal.gd`, `game/core/area_loader.gd` (`_mount_exit_portal`).

### D13. Gates are typed transport only
`Gate` carries `gate_type` (NORMAL/RED/BOSS/TRAVEL), tint and label, and emits `entered`; it owns no lock-in rules. TRAVEL gates name their target by `target_path` (hub and overworld point at each other; PackedScene refs would be a cyclic load). There is **no rank system** (#350): a gate with a `GateOffering` rolls NORMAL vs RED once per run (Main's AreaLoader caches it per gate until death). BOSS gates never roll.
*Where:* `game/world/gate.gd`, `game/world/gate_offering.gd`, `game/core/area_loader.gd` (`offering_type_for`), `data/gate_offering.tres`.

### D14. Never mutate the tree synchronously inside physics callbacks
Scene swaps, pickup consumption and portal returns use `call_deferred` / `set_deferred`; nothing is freed or swapped inside `body_entered`.
*Where:* `game/core/area_loader.gd`, `game/core/travel_service.gd`, `game/spells/spell_pickup.gd`, `game/world/exit_portal.gd`.

### D15. Camera: smoothed follow on physics ticks
The follow camera uses frame-rate-independent exponential smoothing in `_physics_process` (render-frame sampling jittered, #29) and snaps only on ready.
*Where:* `game/core/camera_follow.gd`.

### D16. HUD is self-contained and discovers the objective lazily
The HUD connects to explicit player/caster signals, renders nothing it cannot source, and finds the area's `DungeonObjective` by throttled lazy search guarded by `is_instance_valid`. Its 3x2 spell grid mirrors the six equip slots (#238).
*Where:* `game/ui/hud.gd`.

### D17. Area enemies are scene data, mounted generically
Each area's enemies live in its own `SpawnData` child (`AreaSpawnData`) and AreaLoader's generic mounter (`_mount_area_spawns`, #100) spawns them on every swap; no area-name checks or hardcoded positions in code. Each entry is a `SpawnEntry` resource (`game/world/spawn_entry.gd`); overworld guards, roamers, ambushes and DEFENSE waves use the same type (D21). Current content: DungeonA - 3 plain enemies, 2 splitting slimes (#392) and 2 Fishies (#464, #522); DungeonB - 3 plain enemies and 2 Fishies, then the Warlord; DungeonC/D - no mobs; DungeonE/Maze - no SpawnData (waves come from DEFENSE). Enemy stats are PLACEHOLDER.
*Where:* `game/world/area_spawn_data.gd`, `game/core/area_loader.gd` (`_mount_area_spawns`), `game/world/dungeon_*.tscn` (`SpawnData`).

### D18. Projectiles duplicate their collision shape per instance
`Projectile._ready` duplicates its collision shape before applying the spell's radius, so radii never leak across instances. Projectiles despawn at max range, never hit their source, and damage anything with `apply_damage`.
*Where:* `game/spells/projectile.gd`.

### D19. Evidence standard for gameplay PRs
Mechanics land with headless SceneTree harness drivers plus, for player-visible claims, a browser recording of the exact pushed head with zero console errors, made with real input (synthetic `apply_damage` calls are a named headless complement only). One-off evidence drivers and recordings stay out of the repo.
*Where:* `tests/<feature>/test*.gd`.

### D20. CI/CD: web build and test gate; only main deploys
`deploy.yml` exports the web build in a pinned `barichello/godot-ci:4.5.1` container using the image's checksum-verified nothreads templates. PRs get build-only runs; GitHub Pages deploys only on main pushes. Concurrency is per ref (`pages-${{ github.ref }}`, no cancel) so PR activity cannot cancel a main deploy (#52). `claude.yml` (the `@claude` / `claude`-label agent job) and `claude-code-review.yml` (automatic PR review) are agent workflows, not build gates. `tests.yml` runs `tools/run_tests.gd` on pull requests and main pushes with pinned Godot 4.5.1; it fails on failed, timed-out, unloadable or script-error harnesses.
*Where:* `.github/workflows/deploy.yml`, `.github/workflows/tests.yml`, `tools/run_tests.gd`, `.github/workflows/claude.yml`, `.github/workflows/claude-code-review.yml`.

### D21. Overworld between the hub and the dungeons (#346)
Hub (services: shop, spell directory, bestiary, fast travel) -> TRAVEL gate `GateOverworld` -> `game/world/overworld.tscn`, which holds every dungeon entrance (GateNormal, GateRed, GateGenerated, GateBoss, GateBeast, GateDefense, GateMaze) and `GateHub` back. Each guarded entrance has an `EntranceGuards` carrier (AreaSpawnData + `dungeon_id`); AreaLoader mounts only the sets whose dungeon is uncleared this run (`cleared_dungeons`, filled from `objective_completed`). Behaviors: one posted guard per entrance (`EnemyBehaviorGuard`, leashed chase), patrols on closed routes (`EnemyBehaviorPatrol`, 900 px leash, returns to its route, #414) and overworld-wide `Roamers` migrants (`EnemyBehaviorMigrate`, never suppressed). Routes are the optional `SpawnEntry.route` field. Route shapes, counts, speeds and leash radii are provisional.
*Where:* `game/world/overworld.tscn`, `game/world/overworld_ground.gd`, `game/world/entrance_guards.gd`, `game/enemies/behaviors/enemy_behavior_{guard,patrol,migrate}.gd`, `game/enemies/enemy_spawner.gd`, `game/core/area_loader.gd` (`_mount_entrance_guards`).

### D22. Location-triggered events, foundation only (#365)
A `LocationTrigger` (Area2D, group `location_triggers`, shape from its CollisionShape2D children) holds a `trigger_id` and an `OverworldEvent`. AreaLoader wires every trigger in the mounted area; a fire bumps the run-scoped `AreaLoader.location_event_fire_count(id)` (the abandoned village's run-once guard reads it), emits `location_event_triggered` and starts the event deferred with an `OverworldEventContext` (spawning through an area-owned `EventSpawner`). `AmbushEvent` is the example. Rules go behind `LocationTrigger.should_fire`, `arm()`/`disarm()`. No production scene places a trigger yet. `test365_location_events` covers it.
*Where:* `game/world/location_trigger.gd`, `game/world/overworld_event.gd`, `game/world/overworld_event_context.gd`, `game/world/ambush_event.gd`, `game/core/area_loader.gd` (`_mount_location_triggers`), `game/world/abandoned_village.gd`.

### D23. Tall grass hides characters (#461)
`TALL_GRASS` terrain is walkable and the only type with `conceals`. One sight rule, `TallGrass.can_see(map, viewer, target)`: a target outside grass is always visible; a target in grass is visible only to a viewer also in grass within `SIGHT_RADIUS` (96 px). Enemies lose a hidden player/summon target (falling back to their "no player" path), `Enemy.visible` follows `seen_by_player()`, summon guards and homing shots skip hidden enemies, and the player draws translucent while concealed. Only sight changes, never hits or collision. The overworld lays out the patches; dungeons have none. Radius and patch layout are implementer defaults. `test461_tall_grass` covers it.
*Where:* `game/world/terrain/terrain_types.gd`, `game/world/tall_grass.gd`, `game/enemies/enemy.gd`, `game/player/player.gd`, `game/spells/summons/summon_behavior_guard.gd`, `game/spells/projectile.gd`, `game/world/overworld_ground.gd`.

### D24. Terrain art is a presentation layer over the color tiles
TerrainMap keeps its colored Ground/Obstacle layers as the data mirror harnesses read, and draws `TerrainArt` sprites over them (`ArtFloor`, `ArtWalls`, `ArtObjects`). Floors use hashed variants, wall-like sets pick an autotile piece from a 4-neighbour mask, trees are objects; grass and trees follow `season`. A type with no art keeps its color swatch. A hidden map (the overworld collision grid) builds no art; `OverworldGround` draws the overworld from the same atlases. Sheets are packed by `tools/sprites/pack_terrain_sheets.py`; `test_terrain_art` pins it.
*Where:* `game/world/terrain/terrain_art.gd`, `game/world/terrain/terrain_map.gd`, `game/world/overworld_ground.gd`, `data/terrain_palettes/*.tres`.

### D25. Shop stock and refresh (#132, #466)
The hub `Shop` never sells a spell the player owns; the offerable set is derived (catalog minus owned). It shows `stock_size` slots (3, #466) drawn without replacement; an unfillable slot shows OUT OF STOCK. Stock refreshes free on dungeon victory only (which also resets the paid price); a paid re-roll charges `ShopRefreshSchedule` (Fibonacci 1, 2, 3, 5, 8...) and is refused without charge when it could not surface a new good. Purchases are atomic: precheck, `try_spend`, then `grant` with a full refund on failure.
*Where:* `game/economy/shop.gd`, `game/ui/shop_panel.gd`, `game/core/main.gd`.

---

## Provisional harness defaults (merged, explicitly not settled)

- **P1. Duplicate spell pickups are ignored** and **P2. pickups are consumed on grant** (`game/spells/spell_pickup.gd`), labeled PROVISIONAL in code. The O2 reward direction supersedes them for production once it lands.
- **P3. Revive restores 50 HP** (`revive_hp` in `game/player/revive_satchel.gd`). Tunable data.
- **P4. Revive item visual** is a placeholder green cross (`game/player/revive_item.tscn`); identity is open (O3).

---

## Open human choices (no code may presume an answer)

- **O1. RED gate / DungeonB (#55) - RESOLVED 2026-11-08 (PR #182).** The Mustache Warlord owns DungeonB: ELIMINATION (SpawnData mobs, then the Warlord), portal locked until it dies. Open: boss balance, rewards beyond the demo table.
- **O2. Spell pickups and rewards (#10 stage 2).** Settled: enemies carry reward tables; a picked-up spell leaves the pool; spells auto-unlock (no auto-equip); 6 slots on LMB, RMB, Q, E, R, F (#319), each casting directly; Tab opens a non-pausing equip panel that doubles as the upgrade UI; unlocks and the pool reset per run; `starting_spells` fill the slots in order (#238). Open: reward table contents and weights; dropped-uncollected and duplicate policies.
- **O3. Playable revive (#54).** Open: placement, identity, counts and cap, and the post-revive edge (no i-frames after a revive).
- **O4. Spell upgrade content and UX (#33 -> #36/#37/#38).** Settled: XP on use, 2 paths per level-up, Base > Specialization > Mastery > Signature, manual non-pausing upgrades in the spell panel, placeholder paths allowed. Open: what counts as a "use", XP amounts, tier display in the HUD.
- **O5. HUD/world-label overlap (#50, cosmetic).** Candidate fixes are on the issue.
- **O6. Head boss / DungeonC (#173) - RESOLVED 2026-11-08.** DungeonC (overworld `GateBoss`, BOSS) is a boss arena: ELIMINATION with zero mobs, portal locked until the Head dies. Boss: `game/enemies/bosses/head_boss.tscn`, `game/enemies/bosses/enemy_behavior_head.gd`. Open: balance (PLACEHOLDER), rewards.
- **O7. Beast boss / DungeonD (#326) - RESOLVED 2026-11-09.** DungeonD (overworld `GateBeast`, BOSS, label BEAST) is the Beast's arena, same rules as DungeonC. Reusing the BOSS type and the arena look are implementer choices. Open: balance (PLACEHOLDER), rewards.
- **O8. Dungeon offering chance (#350).** Settled: NORMAL vs RED is 50/50 (`red_chance = 0.5`), no ranks. Open: the run's end goal, and whether each overworld visit should reroll (currently one roll per gate per run).
- **O9. Map reveal (#347) - SETTLED.** The M map reveals explored terrain automatically (fog-of-war, `EXPLORE_RADIUS_CELLS` 4 around the player each tick) and never shows details automatically; players mark them with ink and markers. Run-scoped, wiped on death. Marker/stroke caps are provisional. `test347_world_map` covers it.
  *Where:* `game/world/world_map.gd`, `game/ui/map_panel.gd`, `game/ui/map_canvas.gd`, `game/core/main.gd`.
- **O10. Defense mission (#337).** Settled: a fixed number of waves; mixed targeting. DungeonE (overworld `GateDefense`, NORMAL, no roll, no guards): half of each wave goes for the `DefenseCore` (turning on the player within 150 px), the rest hunt the player; a destroyed core fails the mission and leaves the portal open. Numbers (core 800 HP, 5 waves of 3-7, 15 s cadence) are implementer defaults. Open: balance, success rewards, failure cost, whether the gate should roll.
- **O11. Map dungeon marks + fast travel (#366).** Only CLEARED dungeons show on the map automatically; clicking one and Travel fast-travels through the #349 Hub-spoke policy (`FastTravelRoutes.scene_from_hub`: origin must be the Hub, target cleared this run), rechecked on commit. Marks showing under fog and being run-scoped are implementer defaults. `test366_map_travel` covers it.
  *Where:* `game/world/world_map.gd`, `game/ui/map_panel.gd`, `game/ui/map_canvas.gd`, `game/world/fast_travel_routes.gd`, `game/core/travel_service.gd`.
- **O12. Maze defense (#367).** `DungeonMaze` (overworld `GateMaze`) runs DEFENSE on a seeded `MazeGen` maze; wave enemies route with `FlowNav` (opt-in per enemy via `Enemy.nav`) and are clamped out of walls with `TerrainMotion.clamp_displacement`. Size, entrances, loop rate and a fresh seed per visit are implementer defaults. Open: balance (far entrances are slow), crowding, breakable walls, whether the maze replaces DungeonE.
  *Where:* `game/world/terrain/maze_gen.gd`, `game/world/terrain/flow_nav.gd`, `game/world/maze_defense_dungeon.gd`, `game/world/dungeon_maze.tscn`.
- **O13. Gated dungeon maps are terrain (#396).** DungeonA-D carry fixed ASCII layouts (`TerrainFixedLayout`, `data/terrain_maps/`) with per-dungeon wall palettes (placeholder look); DungeonE stays flat. Bosses move through `Enemy.terrain_move_and_slide`, and knockback is clamped on every terrain grid. Non-destroyable solid walls stop shots at the cell face, piercing included (#433); destroyable tiles, water and pits keep their own rules. `test396_dungeon_terrain` covers it.
  *Where:* `game/world/terrain/terrain_fixed_layout.gd`, `game/world/terrain/terrain_map.gd`, `game/enemies/enemy.gd`, `data/terrain_maps/`, `data/terrain_palettes/dungeon_*.tres`.
- **O14. Defense boss waves (#368).** `DungeonObjective.boss_waves` spawns `wave_boss_count` x `wave_boss_scene` `wave_boss_delay` after the wave, with their slots reserved in the wave's alive count. Both defense dungeons have one boss wave (the last) with one Siege Brute (`game/enemies/bosses/defense_wave_boss.tscn`). All numbers are implementer defaults; type, count, rewards and balance stay open.
- **O15. Overworld details (#346) - implementer placeholders.** Settled by Colin: hub outside the overworld, entrances in the overworld, guards around uncleared entrances. Open: the generated dungeon has no clear state (its entrance is always guarded), guard counts and radii, the overworld layout and look.

---

## Conventions for future work

- One assigned reviewer per PR; heads are frozen while a review is assigned; the lead is the sole squash executor.
- Separate issue and PR per concern; draft PRs are opened early while work is local.
- Bugs may be logged and worked freely; design suggestions are filed with the `suggestion` label and wait for explicit human approval.
- Working agreements: `INSTINCT.md`. Agent notes: `CLAUDE.md`.
