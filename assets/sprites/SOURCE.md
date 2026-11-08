# main_character.png - original chunky wizard sprite sheet

Original hand-authored pixel art for gangU (#136). No copied game assets, no
traced art, no stock files shipped.

## Design
- Chunky wizard: oversized pointed hat with gold band, white beard, bell robe,
  stubby boots, wood staff with cyan orb. Among-Us-LIKE chunky proportions as
  style direction only (round little body, stubby legs) - original art, no
  Innersloth assets used or referenced as files.
- Flat palette, no gradients/glow, fitted to the existing player blue
  (73,142,232) with gate/HUD accents (gold band, spell-cyan orb).
- Frame: 32x48 px. Sheet: uniform 5x4 grid (160x192 px), rows = directions
  [down, left, right, up], col 0 = idle, cols 1-4 = walk cycle
  (contact, passing, contact, passing). Player footprint ~44px tall against
  the 64px grid.

## References (layout/timing only, not shipped art)
- "Space Guy - 8 Directional animated character 16x16"
  https://opengameart.org/content/space-guy-8-directional-animated-character-16x16
  License: CC0 (verified in page HTML 2026-11-07). File blitzorion.png
  (64x256, 16x16 frames) consulted for walk-cycle frame counts and direction
  ordering only; its slim astronaut proportions were NOT used.

## Provenance
- Author: instinctmitra (Mitra's Instinct), 2026-11-07, pixel-by-pixel via
  generator script (PIL), iterated against rendered previews.
- License for this original asset: CC0 (matches project asset licensing).

# boss_head.png - "Head" boss sprite atlas (#173)

User-supplied reference art, sliced and repacked for the engine.

## Provenance
- Source image: uploaded by repo collaborator Mitravasu to issue #173
  ("BOSS SPRITE", 2026-11-07) with the request "Can you use this sprite for
  a boss enemy, with the animations and stuff?" - user-supplied asset for
  this project. No third-party asset pack, stock file, or copied game art
  shipped.
- Processing (instinctmitra, 2026-11-08): the reference sheet's labeled
  panels (Idle 6 / Move 7-per-direction x4 / Attack-Projectile 8 /
  Attack-AOE-Pulse 8 / Hurt 4 / Stun 4 / Death 10 / FX variants / VFX
  overlays) were sliced per frame from the irregular presentation layout,
  panel background flood-removed to transparency, normalized to a 96x64
  cell atlas, bottom-center anchored. The sheet labels Move as "(8, 4 dir)"
  but ships 7 frames per direction; the atlas carries the actual 7.
  AOE ring frames with panel-clipped baked rings were dropped (the pulse
  ring is drawn in-engine from the sheet's VFX circle element instead).
- Frame counts, timing and gameplay numbers that use this art are CHOSEN
  tunings (scripts/boss_head.gd), not facts from the image.
