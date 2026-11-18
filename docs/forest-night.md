# Forest grass and permanent night

Daniel's November18 request: existing grass texture and permanent night in
the forest placeholder behind #891's tree wall.

- Reuses assets/sprites/terrain/dualgrid_variants_grass.png, 64px tiles with
  deterministic variants and nearest filtering. No new art or SpriteU edit.
- Static scene-local CanvasModulate uses the existing DayNightClock midnight
  colour(0.30,0.33,0.55). No clock driver, reset, freeze or gameplay change.
- Player/world tint at night, HUD/instructions stay on their existing canvas.
- Existing room bounds, return guide, doorway and cached overworld behavior
  unchanged. Night tint is freed with forest scene on return.
- Tests sample the full clock cycle, grass coverage and cached return. Demo
  uses staged start/clock samples with actual input/physics for the round trip.
  Native/scripted evidence, not hands-on browser or balance qualification.
