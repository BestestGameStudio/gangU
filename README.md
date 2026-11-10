# gangU

2D top-down arcade shooter (Brawlstars-like). Single-player first, co-op after it works.
Spells only, no weapons. Solo-Leveling-style gates: a hub, an overworld full of dungeon
entrances, normal gates (retreat anytime) and red gates (clear-or-die).

Design decisions and their code locations: [ARCHITECTURE.md](ARCHITECTURE.md).
Contributor working agreements: [INSTINCT.md](INSTINCT.md). Agent notes: [CLAUDE.md](CLAUDE.md).

## Tech

- **Godot 4.5.1-stable** (exact version pinned - use this one) + **GDScript**
- Targets all non-mobile desktop platforms and **must run in the browser** (Web/HTML5 export)

## Repo layout

- `project.godot` - project config and the shared input actions.
- `export_presets.cfg` - Web export preset (see "Web export" below).
- `scenes/main.tscn` - main scene (Player + FollowCamera). `scripts/main.gd` mounts every
  run service in code and swaps areas: hub (`scenes/hub.tscn`) <-> overworld
  (`scenes/overworld.tscn`) <-> dungeons (`scenes/dungeon_*.tscn`).
- `scripts/` - GDScript sources, plus `test*.gd` harnesses and `record*.gd` capture drivers.
- `scenes/test*.tscn` - evidence fixtures for harnesses (never production).
- `resources/` - data: spells, enemies, rewards, terrain maps and palettes, gate offering.
- `assets/` - art and audio.
- `tools/showcase/` - scripted gameplay recordings; `tools/sprites/` - sprite packing tools.
- `.github/workflows/` - web build/deploy and the Claude agent jobs (ARCHITECTURE.md D20).
- `build/` - local export output, git-ignored.

## Controls

| Input                     | Action                                   |
|---------------------------|------------------------------------------|
| W / A / S / D             | Move (`move_up/left/down/right`)         |
| LMB, RMB, Q, E, R, F      | Cast the spell in slots 1-6              |
| Space                     | Cast the equipped spell (`cast`)         |
| Shift                     | Dash (`dash`)                            |
| Tab                       | Equip / upgrade panel (does not pause)   |
| M                         | Map                                      |
| Esc                       | Settings                                 |

The movement, `cast` and `dash` actions live in `project.godot`; the slot keys are registered
at runtime by `scripts/spell_caster.gd`. Manual aim only, no aim assist; keyboard + mouse,
trackpad friendly.

**Web export contract:**

- Preset name: `Web`, output: `build/web/index.html`
- **Thread support OFF** (`variant/thread_support=false`) so the build runs on plain static
  hosting (e.g. GitHub Pages) without COOP/COEP headers. Keep it off unless hosting changes.
- Renderer: `gl_compatibility` (required for broad WebGL2 browser support).

## Setup

1. Install Godot 4.5.1-stable (standard, not .NET): https://godotengine.org/download/archive/4.5.1-stable/
2. Install the matching export templates: in the editor, Editor > Manage Export Templates > Download and Install.
3. Open the project: Project > Import, select this repo's `project.godot`.

## Run (editor)

Open the project and press F5. The game boots into the hub; walk into the gold TRAVEL gate to
reach the overworld and its dungeon entrances.

## Web export (headless/CI)

```bash
godot --headless --path . --import
mkdir -p build/web
godot --headless --path . --export-release "Web" build/web/index.html
```

Every push to `main` builds and deploys this to GitHub Pages (`.github/workflows/deploy.yml`);
pull requests get a build-only run.

## Web export (editor)

Project > Export > select the `Web` preset > Export Project to `build/web/index.html`.

## Test the browser build locally

```bash
cd build/web && python3 -m http.server 8123
# open http://localhost:8123/
```

The game must load into the hub with no console errors.

## Testing

Harnesses are `scripts/test*.gd` (`extends SceneTree`) plus `scenes/test*.tscn` fixtures:

```bash
timeout 300 godot --headless --path . --script res://scripts/testNNN_topic.gd   # one harness
GANGU_AUTOTEST=1 godot --headless --path . res://scenes/testNNN_x.tscn --quit-after 2400
```

A pass is exit code 0 (newer harnesses also print `RESULT: ALL PASS`) with no `-> FAIL` or
`SCRIPT ERROR` lines. macOS has no `timeout`; wrap with `perl -e 'alarm 300; exec @ARGV' godot ...`.
While iterating, run only the harnesses for the area you touched; run the full set once at the end.

**Known baseline noise (main, 2026-11-08):** a full run of every harness and fixture prints
about 189-190 `SCRIPT ERROR`s, all one pre-existing "freed player `physics_step`" error from
the `test_objective_flow` fixture, and `test_run_restart` (the restart guard) fails
intermittently. Anything beyond this baseline is yours.
