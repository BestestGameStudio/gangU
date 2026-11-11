---
name: dungeon-creation
description: "Add a new gangU dungeon/area or hub gate: area scene with SpawnData, hub gate instance, gate type, main.gd objective + exit-portal wiring, docs and tests. Use when asked for a new dungeon, arena, room, area, boss room, hub gate or gate type, or to give a boss its own area."
---

# Dungeon / gate creation (gangU)

Reference: PR #213 (#173) - boss-gate arena `DungeonC` behind the violet `GateBoss`. The area, gate colour and lock-in rules are **human decisions** (ARCHITECTURE "Open human choices"): ask, then record them.

## 0. Check for prior work
- `gh pr list --repo BestestGameStudio/gangU --state all --search "<issue#>"` and `gh issue view <n> --repo BestestGameStudio/gangU --comments`; also check open PRs touching `game/world/hub.tscn` or `game/core/main.gd` (two PRs claiming one room or gate spot conflict).

## Checklist (everything that must be touched)
- [ ] **Area scene** `game/world/dungeon_X.tscn`: root `Node2D` named `DungeonX` (main.gd matches on the node name), `PlayerSpawn` marker, `SpawnData` child (`game/world/area_spawn_data.gd`) with mob entries (empty for a boss-only arena). Copy `game/world/dungeon_b.tscn`.
- [ ] **Hub gate** in `game/world/hub.tscn`: instance `game/world/gate.tscn` with `gate_type` and `target_dungeon = ExtResource(...)`. Give the new `ext_resource` a **unique id string** (e.g. `id="7_dnc"`, not the next integer) so parallel PRs do not collide on merge, and bump `load_steps`.
- [ ] **Gate placement**: keep it clear of the other gates and their labels.
- [ ] **Gate type** (if new): `game/world/gate.gd` `GateType` enum + tint constant + label text in `_ready`. Gates stay transport-only (D13).
- [ ] **`game/core/main.gd`**: add an `area.name == "DungeonX"` branch in `_mount_objective` (dungeon_id, objective type, `boss_scene`, `boss_spawn_position`, `boss_spawned.connect(_on_boss_spawned)`), and add the name to both lists in `_mount_exit_portal` (mount list; locked list for clear-or-die). These name branches are hard-coded - a known refactor candidate (per-area config on the area scene); do not refactor inside a content PR.
- [ ] **`game/world/exit_portal.gd`** header comment: say how the new area mounts the portal.
- [ ] **ARCHITECTURE.md**: a dated decision entry (O-entry) naming who decided, plus D11/D12/D13/D17 sentences that list the areas.
- [ ] **Tests**: extend the core harnesses, not a new per-issue one: `tests/world/test512_dungeon_definitions.gd` (definition), `tests/world/test306_gate_swap.gd` / `tests/world/test378_exit_to_entrance.gd` (gate and exit travel), `tests/world/test337_defense_objective.gd` (objectives).

## Verify and PR
- Engine/`.uid` rules, full-suite baseline and the PR convention are in the enemy-creation skill ("Verify", "PR etiquette") and README "Testing".
- Clip of the new gate and area: the showcase-video skill (set `GATE_NAME` / `AREA_NAME`).
