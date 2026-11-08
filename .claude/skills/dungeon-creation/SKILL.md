---
name: dungeon-creation
description: "Add a new gangU dungeon/area or hub gate: area scene with SpawnData, hub gate instance, gate type, main.gd objective + exit-portal wiring, docs and tests. Use when asked for a new dungeon, arena, room, area, boss room, hub gate or gate type, or to give a boss its own area."
---

# Dungeon / gate creation (gangU)

Reference: PR #213 (#173) - boss-gate arena `DungeonC` behind the violet `GateBoss`. The area, gate colour and lock-in rules are **human decisions** (ARCHITECTURE "Open human choices"): ask, then record them.

## 0. Check for prior work
- `gh pr list --repo BestestGameStudio/gangU --state all --search "<issue#>"` and `gh issue view <n> --repo BestestGameStudio/gangU --comments`; also check open PRs touching `scenes/hub.tscn` or `scripts/main.gd` (two PRs claiming one room or gate spot conflict).

## Checklist (everything that must be touched)
- [ ] **Area scene** `scenes/dungeon_X.tscn`: root `Node2D` named `DungeonX` (main.gd matches on the node name), `PlayerSpawn` marker, `SpawnData` child (`scripts/area_spawn_data.gd`) with mob entries (empty for a boss-only arena). Copy `scenes/dungeon_b.tscn`.
- [ ] **Hub gate** in `scenes/hub.tscn`: instance `scenes/gate.tscn` with `gate_type` and `target_dungeon = ExtResource(...)`. Give the new `ext_resource` a **unique id string** (e.g. `id="7_dnc"`, not the next integer) so parallel PRs do not collide on merge, and bump `load_steps`.
- [ ] **Gate placement**: keep it off test106's scripted movement path and clear of the other gates' labels (`GateBoss` had to move to (712, 250)). Run test106, test50b, test91 and test189.
- [ ] **Gate type** (if new): `scripts/gate.gd` `GateType` enum + tint constant + label text in `_ready`. Gates stay transport-only (D13).
- [ ] **`scripts/main.gd`**: add an `area.name == "DungeonX"` branch in `_mount_objective` (dungeon_id, objective type, `boss_scene`, `boss_spawn_position`, `boss_spawned.connect(_on_boss_spawned)`), and add the name to both lists in `_mount_exit_portal` (mount list; locked list for clear-or-die). These name branches are hard-coded - a known refactor candidate (per-area config on the area scene); do not refactor inside a content PR.
- [ ] **`scripts/exit_portal.gd`** header comment: say how the new area mounts the portal.
- [ ] **ARCHITECTURE.md**: a dated decision entry (O-entry) naming who decided, plus D11/D12/D13/D17 sentences that list the areas.
- [ ] **Tests**: a `scripts/testNNN_*.gd` leg that walks gate -> area -> objective -> portal; extend `scripts/test9_exit_flow.gd` / `scripts/test100_spawn_data.gd` when flows change; check tests that enumerate gates (test106, test50b, test91, test189).

## Verify and PR
- Engine/`.uid` rules, full-suite baseline and the PR convention are in the enemy-creation skill ("Verify", "PR etiquette") and README "Testing".
- Clip of the new gate and area: the showcase-video skill (set `GATE_NAME` / `AREA_NAME`).
