# Forest entrance v11

Daniel approved v11 on November 18, 2026: v9 density with the beige hole at
the left arc joint removed. His explicit direction is gangU only. No art
source or exports from this work were committed to SpriteU.

Tree pixels come from this project's terrain_pieces_base.png and
terrain_pieces_top.png, not the other-game reference screenshot. Generator
arrangement, trunk edits, internal hole closure, removal of the inherited
solid ground shadows and a unified shadow gradient are stored as SpriteU
64x64 indexed-panel source under tools/sprites/forest_source/.

Panels were loaded, inspected and exported using the unchanged SpriteU
viewer. These are static spatial panels, not animation frames:
- forest-wall-panels.json: seven left-to-right panels, 448x64 PNG sheet.
- forest-back-row.json: 7x2 grid, exported sheet unpacked into 448x128 PNG.
- forest-unified-shadow.json: 7x3 grid, exported sheet unpacked to 448x192.
  export_forest_ground.py converts RGB blend weights to dark opacity so the
  game's sand texture remains visible beneath the shade.

The preview backdrop is sand RGB(183,165,109). Runtime uses translucent
shade, not an opaque rectangle painted over the terrain. Tree art is on
canopy z=3; ground shade is z=-1. No changes to global lighting or audio.
