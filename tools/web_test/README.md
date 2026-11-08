# gangU browser testing + capture

Reusable tooling for loading a gangU web build in a real browser, driving it with
synthetic input, and capturing screenshots or video - the workflow used for PR review
evidence and demo clips. Requested by the project owner (2026-11-07).

Status labels: **[PROVEN]** = validated end-to-end on a real exported build on the date
noted, with artifacts to show. **[OBSERVED]** = true on our rig but environment-dependent.
**[OPEN]** = attempted, not yet reliable - contributions welcome.

## Contents

- `run_capture.mjs` - outer runner: serves a build (or points at a URL), launches Chrome,
  focuses the tab, injects the driver, runs a gate-entry + combat choreography, saves a
  `.webm` and optional screenshot burst.
- `capture.js` - in-page driver + canvas recorder (injected by the runner; can also be
  pasted into DevTools console). Input events + `canvas.captureStream` only - real game
  physics, no game-state reads or writes.
- `analyze_frames.py` - ffmpeg contact sheets, burst extraction, localized frame-diff
  event flagging.

## Setup [PROVEN 2026-11-07]

```
node >= 18
npm i puppeteer-core@22        # pinned; tested with google-chrome stable 131, headless 'new'
python3 + ffmpeg on PATH       # serving + video tools
pip install pillow             # only for analyze_frames.py --flag
```

Set `CHROME_PATH` if Chrome is not at `/usr/bin/google-chrome`. Other browsers and
automation drivers (Playwright, headed Firefox, etc.) are **untested** - the game only
needs plain HTTP and a canvas, so they are expected to work, but no claim is made until
someone runs them.

## Run it

```
# against a local CI artifact export (unzipped web build with index.html/index.pck/...)
node run_capture.mjs --serve /path/to/build --out takes/take1 --seconds 25 --shots

# against any already-served URL (including the deployed Pages build)
node run_capture.mjs --url https://<pages-url>/ --out takes/live1 --seconds 25
```

Outputs: `take1.webm` (bytes + sha256 printed; suspiciously small recordings fail the
run), optional `take1-shotN.png` burst frames, and console log markers
(`gate entered`, `gangU booted OK`) for the take. Convert for sharing:

```
ffmpeg -i takes/take1.webm -c:v libx264 -crf 21 -pix_fmt yuv420p -movflags +faststart takes/take1.mp4
```

Recording volume [OBSERVED]: roughly 2 MB per minute at the default 6 Mbps VP9 setting on
our rig - depends on scene motion and browser, not a guarantee.

## Verify an artifact before trusting captures from it [PROVEN]

Download the CI artifact zip, unzip, and hash the payload before capturing:

```
unzip artifact.zip -d build/
md5sum build/index.pck        # or shasum -a 256; compare against the run's recorded value
```

If the bytes are not the ones you reviewed, the capture says nothing about your review.

## Behavioral notes (gangU on the 2026-11-07 build)

- **Focus the tab after every load** [OBSERVED]: backgrounded or unfocused tabs throttle
  `requestAnimationFrame` (we saw ~3-4 fps vs ~24 fps focused, on our rig). The runner
  clicks the page after navigation for this reason.
- **First synthetic input after a load may be swallowed** [OBSERVED]: the runner sends
  one sacrificial tap before choreographing.
- **Bundle whole input sequences into one in-page script** [PROVEN]: driving one action
  per out-of-page call adds ~1s round-trip per action, leaving the player standing still
  mid-fight - in Dungeon A that is death in ~3s (spawn pack of 3, contact 10 dmg per
  enemy per 0.8s). `capture.js` exists so the whole choreography runs inside the page.
- **"gangU booted OK" after "gate entered"** [PROVEN for the observed case]: in our runs
  this signature accompanied the death-restart path (`run_manager.gd` calls
  `reload_current_scene()` on `Player.died` after a 1.5s delay; `main.gd` prints the boot
  line in `_ready()`), confirmed by the HUD sequence HP ticking down -> DEAD -> hub respawn
  at 100/100. The boot line alone is not proof of death - a driver or browser reload
  prints it too. Always corroborate with the HUD/death frames.
- **Combat survival** [PROVEN]: cast at the approaching pack within ~300ms of entry
  (aim around (640, 250-300)), strafe in short ~300-380ms pulses, re-cast every cooldown.
  Never stand still >1s while enemies live. Fire Ball does 25 damage vs 30 HP enemies:
  kills take two hits.
- **Coordinates**: `capture.js` maps game-space (1280x720) through the canvas bounding
  rect, so scripts work at any window size/CSS scale. Do not hardcode client pixels.

## Known gaps [OPEN]

- **0.12s enemy hit-flash isolation**: our naive whole-frame brightness threshold was
  swamped by scene content (the exact cause is unsettled - candidate factors are floor
  rendering and overlapping motion). Needs localized diffing locked to the enemy sprite
  across frames, or a slower cast cadence so the flash window does not overlap motion.
  `analyze_frames.py --flag` is a candidate generator only: eyeball flagged frames with
  `--burst`, never treat flags as automated proof.
- **Long hands-off captures**: the death-restart means the driver must keep the player
  alive; unattended full-run recording is not reliable.
- **CI integration**: not wired in. A natural follow-up is running this tooling on each
  PR's artifact in Actions.
