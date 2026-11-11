---
name: enemy-creation
description: "Add or change a gangU enemy or boss: scene structure, behavior slot, state-driven AnimatedSprite2D, boss telegraphs/phases/HP bar, enemy projectiles, wiring into a dungeon via spawn data / ELIMINATION objective / portal lock, tests, verification and PR etiquette. Use when asked to create a new enemy type, a boss, enemy attacks or AI, or to put enemies/bosses into an area."
---

# Enemy creation (gangU)

Reference implementations: PR #182 (#177) - common enemy `scenes/enemy.tscn` and boss `scenes/mustache_warlord.tscn`; PR #213 (#173) - Head boss in a new arena. Read `ARCHITECTURE.md` (D6, D7, D11, D12, D14, D19, O1) and `INSTINCT.md` first. For new art, use the sprite-sheet-pipeline skill; for a new area or hub gate, the dungeon-creation skill; for a PR clip, the showcase-video skill.

## 0. Check for prior work
- `gh pr list --repo BestestGameStudio/gangU --state all --search "<issue#>"` and `gh issue view <n> --repo BestestGameStudio/gangU --comments`: find existing or stale PRs (e.g. #180 vs #182) and reviewer comments before starting.

## Decide before coding (human-owned)
- Which area/room an enemy or boss lives in, objective type, and whether a red room allows pre-clear retreat are **human decisions** (ARCHITECTURE "Open human choices", D17). Do not pick them: ask, then record the decision with date in `ARCHITECTURE.md` (see O1) and the PR body. Two PRs claiming one room (#180 vs #182) is a conflict for the human, not for you.
- Balance numbers are placeholders; label them `PLACEHOLDER` in code and list them as open in the PR.

## Scene structure
- Root `CharacterBody2D` with `scripts/enemy.gd` (HP, `apply_damage`, `died`, `health_changed` - D7, never bypass). Stats come only from the required `EnemyDefinition` resource (`resources/enemies/*.tres`, `scripts/enemy_definition.gd`), copied as a set when it is assigned; a scene without one logs an error.
- Children: `Shadow` (Polygon2D), `Sprite` (AnimatedSprite2D + `scripts/enemy_sprite.gd`, `texture_filter = 1`), `CollisionShape2D`. Bosses add `Telegraph` (`scripts/boss_telegraph.gd`, `z_index = -1`) and `HealthBar` (`scripts/boss_health_bar.gd`). Position the sprite so its feet sit on the collision circle's bottom.
- Behavior: the #99 slot. `EnemyDefinition.behavior` holds an `EnemyBehavior` resource prototype (`resources/behaviors/*.tres`) overriding `physics_step(enemy, player, delta)`; each enemy duplicates its own instance, and null means the default chase/contact. Land every hit through `enemy.deal_hit(target, base, OnHit.DELIVERY_*)` so DamageCalc and OnHit apply. Default: `scripts/enemy_behavior_chase_contact.gd`; boss example: `scripts/enemy_behavior_warlord.gd`. Never special-case a type inside `enemy.gd`.

## Animation pattern (`scripts/enemy_sprite.gd`)
- Locomotion idle/walk from body velocity; `flip_h` from travel/target x (art faces right).
- Behaviors request one-shots via `enemy.play_action(&"attack")`, holds via `play_action(anim, true)` + `clear_action()`.
- Hurt plays from `health_changed` only when interruptible (`HURT_INTERRUPTS`); boss actions have super armor. The root `modulate` flash from `enemy.gd` still shows.
- Death: `Enemy` still frees itself immediately (contract tested by test110); `EnemySprite.spawn_corpse` adds a detached copy that plays `death`, fades, frees itself.

## Boss patterns (`scripts/enemy_behavior_warlord.gd`)
- State machine CHASE -> WINDUP -> attack -> RECOVER; attack picked by range with an anti-repeat fallback.
- Every attack gets a wind-up: held wind-up pose + `sprite.set_glow(true)` + a ground marker (`BossTelegraph.show_line/ring/cone`), aim tracks then locks for a dodge window.
- Phase change at an HP threshold (`is_enraged`: <= 50%): shorter gaps, stronger attacks; the HP bar changes colour.
- Ranged attacks reuse `scenes/projectile.tscn` with a `Spell` resource (`resources/spells/warlord_orb.tres`); custom look via `Projectile.visual_override` (assign before add, e.g. `scripts/warlord_orb_visual.gd`) and impact FX via the `hit` signal. Do not fork projectile logic. Projectiles hit any body with `apply_damage` except their source - check whether allies can be alive in the attack's lifetime.
- D14: add nodes from physics code with `call_deferred("add_child", ...)`.

## Wiring into an area
- Mobs: the area's `SpawnData` child (`scripts/area_spawn_data.gd`) entries in the area `.tscn` (e.g. `scenes/dungeon_b.tscn`).
- Objective + boss: `main.gd` `_mount_objective` (mounted AFTER spawns). ELIMINATION: `boss_scene` + `boss_spawn_position`; connect `boss_spawned` and set `boss.player_path = NodePath("../../Player")` before tree entry (D6 explicit wiring; otherwise Enemy falls back to `Player.find`).
- Portal: `_mount_exit_portal` locks red rooms only when the objective can complete (D12 clear-or-die, #55 no soft-lock).
- Update docs and comments that described the area's old content (ARCHITECTURE D11/D17/O-entries, `exit_portal.gd`, `hud.gd`, `area_spawn_data.gd`).
- A brand-new area or gate: follow the dungeon-creation skill's checklist.

## Tests
- Extend the core harnesses instead of adding a per-issue one: `scripts/test_enemy_definition.gd` (definition data), `scripts/test220_enemy_spawner.gd` (spawning), `scripts/test513_boss_damage_path.gd` (boss hits), `scripts/test518_spawn_entry_typed.gd` (spawn data). Add a new `scripts/test_<system>.gd` only for a genuinely new system.
- No playable fixture scenes or record scripts in the repo; keep them in scratch space.

## Verify
1. Engine: `project.godot` pins 4.5.1 (CI image `barichello/godot-ci:4.5.1`). A newer local Godot (4.7.x) regenerates `.uid` files for untouched scripts: commit only the `.uid` files of scripts you added, and name the Godot version you used in the PR.
2. `godot --headless --path . --import` - read the output for errors.
3. While iterating, run only the touched harness: `godot --headless --path . --script res://scripts/test<name>.gd` (macOS: wrap with `perl -e 'alarm 150; exec @ARGV' godot ...`). Once at the end, run the full suite (README "Testing") - it must report `RESULT: ALL PASS`.
4. Look at it: windowed run of a scratch SceneTree script that saves `root.get_texture().get_image().save_png(...)` at each boss state; Read the PNGs.
5. Demo clip for the PR: the showcase-video skill (`tools/showcase/record_showcase.gd`). Disclose demo-only tweaks (boss HP floor, player autoheal).

## PR etiquette (INSTINCT.md)
- Open a draft PR as soon as work starts and mark it ready when verified; state exact files and evidence; name the engine version tests ran on. Request review from another Instinct on the exact head; leave labels and auto-merge alone.
- `Closes #N` in the PR body - issues auto-close on merge; the merger confirms closure afterward (see INSTINCT.md).
- One concern per PR; check open PRs for file/room overlap before starting.
- Review and merge follow INSTINCT.md: independent approval on the exact head, then a single designated merge executor.
