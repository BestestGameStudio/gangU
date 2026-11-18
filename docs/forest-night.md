# Forest grass and permanent night

Owner requested existing overworld grass and permanent night in the forest
placeholder behind #891, then approved the corrected shader preview.

- Reuses ground_paint.gdshader unchanged, with a grass-only lattice. Same
  palette, clumpy noise and 2px art scale as the overworld, not legacy tiles.
- Grass extends beyond unchanged collision bounds with no visible floor-panel
  edge. Removed rectangular south-guide fills. Invisible return trigger stays.
- Static scene-local CanvasModulate uses the existing midnight colour
  (0.30,0.33,0.55). No clock driver, reset, freeze or global appearance change.
- Player/world tinted; HUD/instructions remain on their existing canvas.
- Regression covers shader reuse, clock-cycle samples and cached-world return.
  Demo stages start/HP/clock samples, uses real movement input/physics for the
  round trip. Native evidence, not browser gameplay or balance qualification.
