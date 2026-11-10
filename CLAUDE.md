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
- `scenes/main.tscn` stays minimal; mount systems from `scripts/main.gd` (D4). Area content is scene data (`SpawnData`, D17).
- No tree mutation inside physics callbacks (D14); HP only changes through `apply_damage` / `heal` (D7).
- Run state outside the reloaded scene joins the `run_state` group and implements `reset_run_state()` (D10).
- Tests: `timeout 300 godot --headless --path . --script res://scripts/testNNN_topic.gd`. New behaviour gets a new `scripts/test<issue>_<topic>.gd` harness. Run the harnesses for the area you touched and report the real results.
- Commit the `.uid` files of scripts you add; never commit `.godot/` or build output.
- When a change alters a rule in `ARCHITECTURE.md`, update that entry in the same PR.
