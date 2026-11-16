# UI frame art provenance

`icon-frame-{silver,gold,red,purple}.png` (48x48) and
`card-frame-{silver,gold,red,purple}.png` (48x64, nine-patch margins
L/R 12, T 13, B 4), added in #702.

- Authored in SpriteU's hand-authored JSON sprite format (character palette +
  pixel rows, validated against SpriteU's `tools/check_sprite.py` rules) by a
  generator script written for this task. The generator ran locally and was
  NOT committed to the SpriteU repo (SpriteU is used read-only for gangU).
- Reference frames: Daniel's 4 ornate frame images (steel / gold / red /
  purple), 2026-11-15.
- Colorways are exact `UiStyle.RANK_COLORS` values: silver = tier 0 (Base),
  gold = tier 1 (Specialization), red = tier 2 (Mastery), purple = tier 3
  (Signature).
- Interiors are transparent: spell icon art and card content show through.

## upgrade-lock.png (#715)
Original 24x28 grey padlock authored in SpriteU JSON format at
`tools/sprites/specs/upgrade_lock.json`. Validated with SpriteU
`tools/check_sprite.py` and exported through SpriteU
`tools/render_preview.py --scale 1` at source revision
`7fd4617ebb9a084450fef7e428bee61357b26227`. Exact first-frame PNG copied
into gangU. SpriteU source was read-only: no edits, issues, commits or PRs.
Silhouette narrowed and extended vertically per owner feedback.
Drawn at 2x nearest horizontally centered, above the mid-card progress bar per latest owner layout.

## upgrade-open-lock.png (#730)
Original24x28 open-shackle variant of upgrade-lock.png, same palette/body,
authored at `tools/sprites/specs/upgrade_open_lock.json`. Validated by SpriteU
`tools/check_sprite.py`; PNG exported by `tools/render_preview.py --scale 1`
at read-only source revision7fd4617ebb9a084450fef7e428bee61357b26227.
SpriteU remains unchanged. Same2x nearest placement as the closed lock.

## Water Shot art (#740)
All new Water Shot art (spell icon and projectile reused while hovering) is
original24x24 SpriteU-format JSON in tools/sprites/specs/water_shot_*.json.
Validated using SpriteU check_sprite.py; exported at1x by render_preview.py
from read-only revision7fd4617ebb9a084450fef7e428bee61357b26227.
PNGs in assets/sprites/spells/; no SpriteU source modifications.
