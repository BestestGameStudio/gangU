# gangU

2D top-down arcade shooter (Brawlstars-like). Single-player first, co-op after it works.
Spells only, no weapons. Solo-Leveling-style gates: a hub with normal gates (retreat anytime)
and red gates (clear-or-die).

## Tech

- **Godot 4.5.1-stable** (exact version pinned - use this one) + **GDScript**
- Targets all non-mobile desktop platforms and **must run in the browser** (Web/HTML5 export)

## Repo layout

- `project.godot` - project config. Defines the shared input actions (see below).
- `export_presets.cfg` - Web export preset (see "Web export" below).
- `scenes/main.tscn` - main scene; boots the game. Scene flow (hub <-> dungeon) attaches here.
- `scripts/` - GDScript sources.
- `build/` - local export output, git-ignored.

## Shared interfaces (depend on these, do not redefine)

**Input actions** (defined in `project.godot`):

| Action    | Keys                    | Consumed by          |
|-----------|-------------------------|----------------------|
| `move_up`    | W                   | #2 player controller |
| `move_down`  | S                   | #2 player controller |
| `move_left`  | A                   | #2 player controller |
| `move_right` | D                   | #2 player controller |
| `cast`       | Space, left mouse button | #3 spell system   |

Manual aim only, no aim assist. Keyboard + mouse, trackpad friendly (no inputs beyond pointer + click).

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

Open the project and press F5. The main scene boots to a "gangU boots OK" screen.

## Web export (headless/CI)

```bash
godot --headless --path . --import
mkdir -p build/web
godot --headless --path . --export-release "Web" build/web/index.html
```

## Web export (editor)

Project > Export > select the `Web` preset > Export Project to `build/web/index.html`.

## Test the browser build locally

```bash
cd build/web && python3 -m http.server 8123
# open http://localhost:8123/
```

The game must load to the boot screen with no console errors.

## Testing

Harnesses are `scripts/test*.gd` (`extends SceneTree`) plus `scenes/test*.tscn` fixtures:

```bash
godot --headless --path . --script res://scripts/testNNN_topic.gd      # one harness
GANGU_AUTOTEST=1 godot --headless --path . res://scenes/testNNN_x.tscn --quit-after 2400
```

Every `.gd` script needs its `.gd.uid` committed next to it (generate it with Godot 4.5.1, e.g.
`godot --headless --path . --import`). `scripts/test519_uid_files.gd` fails on a tracked `.gd`
without a tracked `.uid`, or on an orphan `.uid`.

macOS has no `timeout`; wrap with `perl -e 'alarm 150; exec @ARGV' godot ...`. Count `-> FAIL` and `SCRIPT ERROR` lines.

**Known baseline noise (main, 2026-11-08):** a full run of every harness and fixture prints
about 189-190 `SCRIPT ERROR`s, all one pre-existing "freed player `physics_step`" error from
the `test_objective_flow` fixture, and `test_run_restart` (the restart guard) fails
intermittently. Compare your run against this instead of rebuilding a copy of main to
re-baseline. While iterating, run only the harnesses you touched; run the full suite once at
the end. Anything beyond this baseline is yours.
