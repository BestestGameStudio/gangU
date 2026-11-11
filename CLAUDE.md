# CLAUDE.md

Notes for Claude agents working on gangU. Keep this short; the details live in the files it points at.

## Read first
- `ARCHITECTURE.md` - the design rules (D*), provisional defaults (P*) and open human choices (O*), each with where it lives in code. Do not presume an answer to an Open item.
- `INSTINCT.md` - working agreements (one concern per PR, `Closes #N`, evidence, review).
- `README.md` - setup, controls, web export, test commands.

## Skills (`.claude/skills/`)
- `ci-runner` - load first when running in the GitHub Actions `@claude` job: installed tools, allowed commands, headless tests, screenshots into `/tmp/ci/media`, `github-fetch`.
- `dungeon-creation`, `enemy-creation` - adding areas/gates and enemies/bosses.
- `sprite-sheet-pipeline` - concept art to packed PNG + SpriteFrames.
- `showcase-video` - scripted gameplay recordings (`tools/showcase/`).

## Ground rules
- Godot **4.5.1-stable** exactly, GDScript, renderer `gl_compatibility`; the game must run in the browser.
- `game/core/main.tscn` stays minimal; mount systems from `game/core/main.gd` (D4). Area content is scene data (`SpawnData`, D17).
- No tree mutation inside physics callbacks (D14); HP only changes through `apply_damage` / `heal` (D7).
- Run state outside the reloaded scene joins the `run_state` group and implements `reset_run_state()` (D10).
- Tests: never add a test unless it is truly essential and adds value (INSTINCT.md section 12). The suite is a small core set (README "Testing"). Do not add a harness per issue: extend the core harness that owns the system you changed, and add a new `tests/<feature>/test_<system>.gd` only for a new core system or contract. No one-off tests, debug scenes or record scripts in the repo; keep those in your scratch space. Run the harnesses for the area you touched and report the real results.
- Commit the `.uid` files of scripts you add; never commit `.godot/` or build output.
- When a change alters a rule in `ARCHITECTURE.md`, update that entry in the same PR.
