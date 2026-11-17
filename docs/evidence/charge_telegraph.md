# Open-end gradient charge telegraph

Art handoff, not proof of permission to commit, publish or merge. Carry any required user approval separately from the original conversation. Replaces earlier closed-rectangle and narrower-diffusion candidates.

## Approved-look target

Three thin red edges, no short edge nearest the enemy. Border diffuses inward. During windup a gradient grows from the open enemy end toward the far end, reaching full lane length at attack start, then clearing. Spatial edge diffusion and progress-driven fill are separate.

Original procedural pixel art authored as a SpriteU alpha-ID stencil and validated/rendered by SpriteU. SpriteU char palettes are RGB, so the six palette keys encode alpha stages; their diagnostic colours are NOT the final red shades. The packer maps them to one constant RGB red with true alpha. Not image-model-generated or editor hand-painted.

## Visual parameters, exact latest preview

- Constant RGB: (237,69,74), hex ED454A.
- Outer edge: 1 world pixel at alpha178/255.
- Successive inward 1px bands: 108,62,32,14,4 out of255. Then zero.
- No near-side short edge or near-side border diffusion.
- Inward distance at integer pixel (x,y): min(y, height-1-y, width-1-x). Deliberately excludes x.
- Gradient progress p = clamp(elapsed / windup_duration,0,1).
- Fill front reach = width*p.
- Fill alpha at x<reach: round(112*(1-x/max(1,reach))^0.8). Else zero. Strongest at near end, transparent at the moving front. At p=1, the whole lane has a near-to-far gradient, never a solid flat slab.
- Compose fill below border with source-over: final_alpha = round(border_alpha + fill_alpha*(1-border_alpha/255)). Same RGB red for both.
- Latest preview has the outline visible immediately at target strength; only fill grows. Do not retain the obsolete 40ms whole-outline fade from the earlier closed-rectangle timing study.
- Clear at attack start or cancellation/death. Never hold/fill beyond actual attack state.

## Geometry contract from coding worker

Lane supplied as world-space anchor, locked aim direction, length and width. Scorpion reference starts at grounded attack-tip minus24px along aim, length248px, full width48px. This bounds a 200px tip sweep plus24px endpoint radius. Use the actual rendered grounded tip for each directional suffix, not body center. Local rectangle runs x=0..length, y=-width/2..width/2 and rotates with locked aim. Art does not change collision or attack reach.

Initial windup0.18s, later windup0.36s. Continuous progress is preferred to a fixed-frame animation. Preview was50fps, illustrating fill over9 or18 frames. Do not change timing to match art frames.

## Variable sizing and nine-patch

Preferred: generate the three-edge mesh/shader/draw geometry in world pixels, using above inset/alpha formula and a separate progress gradient quad. Preserve constant1px edge and5px inward diffusion regardless of lane dimensions. Share the art parameters, not the old filled BossTelegraph.LINE implementation.

Alternative: charge_telegraph_border.png is64x32 transparent RGBA, open on its left. For Godot NinePatchRect, patch margins left=0, right=6, top=6, bottom=6; draw_center=false for border only. Place its top-left at lane start minushalfwidth along normal and rotate about lane start. Stretch ONLY the edge center strips, not the full texture; corner pieces remain6px. Overlay a separately parameterized gradient below the border, clipped to the lane. Nine-patch must be tested at the actual engine pixel scale, rotation and non-integer world dimensions. The supplied Python renderer is the integer-pixel reference. The top/bottom edges intentionally reach the near end; there is no vertical closure there.

Use nearest sampling for source art and avoid half-pixel thickening. Dynamic draw-line geometry needs consistent pixel-center alignment. A shader may keep fractional widths, but must reproduce the apparent1px edge at the actual game zoom. No new global edits to other enemies' green/ring/cone telegraphs.

## Files and reproduction

- tools/sprites/generate_charge_telegraph.py: original SpriteU stencil generator.
- tools/sprites/specs/charge_telegraph.spriteu.json: one static64x32 frame, alpha-stage palette keys.
- tools/sprites/pack_charge_telegraph_spriteu.py: true RGBA export plus render_lane(width,height,progress) reference.
- assets/sprites/charge_telegraph_border.png:64x32 nine-patch border.
- assets/sprites/charge_telegraph_reference_empty.png and _full.png:248x48 exact target reference images, NOT textures to stretch.
- docs/evidence/charge_telegraph.md: this contract.

Run from repo root with Pillow:

```
python tools/sprites/generate_charge_telegraph.py
python tools/sprites/pack_charge_telegraph_spriteu.py
```

No SpriteFrames resource: this is static edge art plus continuous time/size parameters, not a looping sprite animation.

## Verification and limits

SpriteU checker has one connected part and no errors/warnings. Cell-edge contact is intentional because the border is a tiling/nine-patch stencil. Visually inspected latest softer-diffusion still at25%,60%,100% progress and timing keyframes. Packed export checked against the preview's exact renderer formula. No engine integration, runtime collision, real gameplay, obstacle or browser qualification claimed. No commit, push, issue or PR in this archive.

## Runtime integration (#860)

Scorpion-only consumer `scorpion_charge_telegraph.gd` uses a world-pixel shader
reproducing the three-edge diffusion and progress formula above, not a stretched
atlas or the global BossTelegraph.LINE renderer. Owner signal is derived from
STING_WINDUP only. State exit/death/burial/generic stun removes the lane. Freeze
holds the behavior timer, so the fill remains in place. Direction is the locked
aim, origin predicts the actual directional grounded attack tip. Width48 and
length248 preserve the existing200px sweep plus24px endpoint radii.

Initial attack retains full0.30s emerge, then0.18s windup (formerly0.36s), total
0.48s instead of0.66s. Later windup0.36s, dash600px/s up to200px, all pincer,
stun and recovery timings are unchanged. This is intentionally a quick warning.
Native60Hz demo measured11frames initial and22frames later. Both lane outlines
are visible immediately; fill rises from the open near end. At normal timing the
initial warning is a short but visible flash, while the preceding emerge supplies
advance context. No claim that a human dodge/reaction playtest was done.

Evidence: separately relayed8s native recording uses production scorpion AI and
physics timers, actual Player art, staged player positions/dodge and invulnerable
player, flat fixture. No forced enemy states/timer stepping. Native screenshots
of initial and later windups inspected after correcting ground draw order; lane
renders over the floor and under enemy/player. No browser, obstacle-rich or
knockback qualification. Video stays outside the repository per showcase guidance.
