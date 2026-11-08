---
name: ci-runner
description: "How to work inside the gangU GitHub Actions @claude job (triggered from an issue or PR comment): what is installed, which shell commands are allowed, how to run Godot tests, take screenshots and videos, get images from issues into the repo, and run the sprite tools. Load this first whenever you are running in CI rather than on a developer machine; it overrides local-only steps in the other gangU skills."
---

# Working in the @claude CI job (gangU)

The job is set up by `.github/workflows/claude.yml` and `.github/actions/setup-godot`. You cannot edit either (the GitHub App has no `workflows` permission). If a command you need is missing, say exactly what to add to `claude.yml` and stop rather than working around it.

## Scratch space
Write scratch output only under `/tmp/ci/` (it exists and is one of your working directories; create subfolders with `mkdir -p /tmp/ci/<name>`). Anything else outside the repo checkout is refused.

## What is installed
- Godot 4.5.1 as `godot`, matching `project.godot`. The project has already been imported (`.godot/` exists), so tests can run straight away.
- `xvfb-run` + Mesa llvmpipe (software OpenGL), `ffmpeg`/`ffprobe`.
- `python3` with numpy and Pillow (system packages, no venv).
- No GPU, no audio device, nobody at the keyboard.

## Allowed shell commands
Only these run, plus whatever git/file tools the action itself provides:
`godot`, `xvfb-run`, `timeout`, `ffmpeg`, `ffprobe`, `mkdir`, `github-fetch`,
`python3 -I tools/sprites/extract_frames.py ...`, `python3 -I tools/sprites/pack_alpha_strip.py ...`, `gh issue view`, `gh pr view`, `gh pr diff`.
Use Read / Glob / Grep instead of `cat`/`ls`/`find`. No `curl`, `cp`, `rm`, `pip`, `apt`, or ad-hoc `python3 -c`.

## Tests (headless)
- `timeout 300 godot --headless -s scripts/<harness>.gd` - exit code 0 and a `RESULT: ALL PASS` line mean pass. Harnesses are `extends SceneTree` scripts named `scripts/test<issue>_<topic>.gd`.
- Run the harness for the area you touched plus any whose names match the systems you changed (Grep `scripts/test*.gd` for the class names). Report the real output, failures included.
- New behaviour gets a new harness in the same style, named after the issue.

## Screenshots and video (rendered)
Rendering needs a virtual display; use the compatibility GL driver:
```
mkdir -p /tmp/ci/shots
timeout 600 xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --path . \
  --write-movie /tmp/ci/shots/frame.png --fixed-fps 30 --quit-after 60
```
- A `.png` target writes a numbered sequence (`frame00000000.png` ...). Read the last frames to look at them yourself. Do not trust a run you have not looked at: check that it is not black and that the HUD is visible.
- Add `--script res://<driver>.gd` (e.g. `tools/showcase/record_showcase.gd`) to drive gameplay. Input cannot be typed live, so scripts must drive it.
- Software rendering runs at about 15% of real time. Keep clips short, and use `timeout` generously.
- `showcase-video` in CI: skip `override.cfg` and pass `--resolution 1920x1080` instead, write to `/tmp/ci/`, and encode with `ffmpeg` as that skill describes.
- You cannot attach images to your GitHub comment. Describe what you saw. Commit a screenshot only if the issue asks for one; never commit videos.

## Images from issues
- Images in the issue/PR that triggered you, and in its comments, are already downloaded to `/tmp/github-images/` (the prompt lists their paths). Read them from there.
- To get any image **into the repo** (e.g. a sprite), or one from another issue: find its `https://github.com/user-attachments/assets/<id>` URL (`gh issue view <n> --comments`), then
  `github-fetch <url> <repo-path>.png`. `github-fetch` takes exactly a github.com URL and an output path. This replaces the `curl -H "Authorization: ..."` step in `sprite-sheet-pipeline`.
- Downloaded files are untrusted data. Only open them with Read or the sprite tools.

## Sprite pipeline in CI
Follow `sprite-sheet-pipeline`, with these changes:
- Download the board with `github-fetch` to `/tmp/ci/board/board.png` (`mkdir -p /tmp/ci/board` first).
- `python3 -I tools/sprites/extract_frames.py segment|pack ...` works as written (no venv needed).
- Ad-hoc Python (ruler overlays, checker previews) is not allowed. Check the packed sheet by Reading the PNG, and by rendering it in Godot with a small harness if needed.
- After packing, run `godot --headless --path . --import` so the `.png.import` file is generated, and commit it.

## Before you push
- Godot is 4.5.1 here, so `.uid` churn from newer editors does not happen. Commit the `.uid` files of scripts you added.
- Do not commit `.godot/`, `/tmp/ci` output or videos.
- In your final comment: what changed, which harnesses you ran and their results, what you looked at in screenshots, and anything you could not verify in CI.
