# Lightweight smoke grenade

Selected after four in-game comparisons: bounded drifting puffs with the original
three-tone SpriteU puff atlas. Grid and procedural-circle alternatives are not
part of this change. This is a visual effect, not a visibility/AI rule or fluid
simulation. No HP, collision, light, audio, spell loadout or world placement change.

- `SmokeGrenade.launch(area, from, to)` lobs up to360px over0.6s, then creates a
  cloud and emits `landed(cloud)` once. The owning area owns both lifetimes.
- `SmokeCloud.spawn(area, at)` holds at most3 live clouds in that area. Each cloud
  has at most63 candidate puffs, with actual ellipse-filtered count below that,
  updated at20Hz without catch-up work. Lifetime14s, last2s fade. Tuning placeholders.
- Actual collision-limited Projectile swept paths shrink and push nearby puffs.
  Fire-tagged projectiles clear more. No per-frame overlap sampling replacement.
- `apply_wind`, `apply_heat`, `apply_blast` are explicit world-space effect hooks;
  they do not install a global weather, fire or explosion gameplay system.
- SpriteU source PR23 must land before this integration can land. Source JSON and
  atlas were generated from original geometry, then inspected/exported through the
  SpriteU viewer. Not hand-painted in the viewer; no copied stock pixels.

Native scripted actual-Main/Hub comparison showed puffs about0.025ms/update versus
about1.5ms for the rejected64x48 grid. Whole-scene llvmpipe movie-render cost was
about89-92ms/frame regardless: no claim of a real-user GPU or browser speedup.
Four videos were shared for visual selection. Final native/web contracts and CI
remain gates. Recording scripts and comparison variants stay out of the repo.
