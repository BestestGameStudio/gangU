# Generic stun halo

Original procedural pixel art preview, November 17, 2026. This archive is an art handoff, not evidence of user approval or authority to commit, publish or merge. The receiving worker must rely on the original conversation for any required authority. Runtime wiring and review/merge remain separate.

## Art and provenance

Three warm gold four-point stars orbit a flattened broken ellipse, with a dark slate-family outline. Intended for the gangU pixel-art look. Source authored by deterministic Python geometry, encoded as SpriteU JSON, checked with SpriteU check_sprite.py, rendered using SpriteU sheet.py. No image-model generation or editor hand-drawing. Exported opaque pixels match the SpriteU renderer. Transparency restored from JSON, never exported checkerboard pixels.

## Files

- tools/sprites/generate_stun_halo.py: reproducible original geometry.
- tools/sprites/pack_stun_halo_spriteu.py: transparent atlas and Godot resource packer.
- tools/sprites/specs/stun_halo.spriteu.json: SpriteU source.
- assets/sprites/stun_halo.png: 512x64 transparent RGBA atlas, 8 columns, 64px cells.
- data/sprites/stun_halo_frames.tres: animation `stun`, loop=true.

## Timing

Eight frames, 75ms each, 600ms loop. Godot speed 10 with duration 0.75 per frame. Runtime should remove the effect on stun end; do not extend gameplay stun duration to finish the animation loop. No directional variants needed.

## Anchor

Ring center is pixel (32,14) in the 64px cell. For a centered AnimatedSprite2D this means local (0,-18). Place the ring center 10px above the enemy's visible top. Therefore effect node offset.y = enemy_visible_top_y + 8, offset.x = 0.

Examples, assuming enemy origin and centered sprite are aligned:

- Enemy fills the 64px frame up to local y=-32: effect node offset (0,-24).
- Scorpion's visible top is local y=-24: effect node offset (0,-16), matching preview.

Use the actual visual top rather than a single offset for all enemy shapes. Parent to a stable visual/enemy anchor, not a transform that rotates to aim, and draw above the enemy. World/screen scaling must match the sprite pixel scale. These are integration guidance, not runtime changes included in this package.

## Checks

SpriteU checker: 8 frames, 600ms; no cell edge contact, errors or warnings. Two or three substantial connected parts per frame are intentional separated stars along the orbit. Visual inspection performed on the full eight-frame strip and actual MP4 showing effect alone and mounted on scorpion. No runtime/gameplay evidence claimed.

To regenerate with Pillow installed, from gangU root:

```
python tools/sprites/generate_stun_halo.py
python tools/sprites/pack_stun_halo_spriteu.py
```

No scene/behavior mutation, issue, PR, commit or push is included in this handoff.

## Runtime verification (#858)

`Enemy.is_stunned()` combines the existing generic timer with an explicit behavior
opt-in. EnemyStunHalo only reads that status; it never changes a clock. Scorpion
miss stun is1s; first accepted direct tip hit adds2s once to the current deadline.
AoE, shell hits, raw/unlocated damage and modifier queries do not grant the bonus.
The next miss re-arms it. Both miss stun and generic Enemy.stun hold attack frame2,
whose tip is down at ground height. Hurt cannot interrupt the held pose. Generic
stun restores the pre-hold sprite action before resumed AI chooses its next action.
No pincer, sting wind-up, recovery, bird, boss, lighting or audio timing changes.

Godot4.5.1 native scripted fixture shows generic stun during a raise,1s miss, and
real Water Shot hits to the grounded tip: HP100->88 adds2s; second hit HP88->76
does not stack. Actual Player, SpellCaster, projectile collision and damage path;
scripted positions/state transitions, flat sand fixture and paused AI outside
miss steps. No browser, obstacle-rich or external-displacement qualification.
Video is delivered separately, not committed, per showcase-video guidance.

Core enemy harness guards timer, once/reset, accepted-hit context, held pose,
freeze/thaw, halo anchor/lifecycle and unchanged pincer timing. Full suite run uses
Godot4.5.1; final result is recorded in the PR.
