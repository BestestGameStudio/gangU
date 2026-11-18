# Forest entrance

Owner-requested continuous forest wall north of the desert. Art v11 was
approved November 18, 2026 for gangU only, not a SpriteU art commit.

## Scope

- ForestEntrance at (576,-1610), scale 0.75, stays within the island's north
  shoreline without changing the coast, cliff shader, terraces or lighting.
- Connected tree mass, smaller recessed arc, unified soft ground gradient.
- Enter the dark floor opening to mount ForestPlaceholder via AreaLoader.
- Placeholder south exit returns to the same cached overworld at (576,-1510).
  Player health and run/encounter state are retained. Active encounters,
  stale/hidden origins and dead players cannot initiate the passage.
- Physical walls, path and shot blockers share TerrainMap trunk rectangles.
  No duplicate collision on return, and cached overworld collision/layers
  use the existing parking/restoration path.

## Verification

Native Godot 4.5.1 checks cover the approach, wall/back collision, shoreline,
active-encounter refusal, hidden-origin refusal, safe spawn, cached round trip,
health retention and collision count. Scripted native demo stages the player
start and health, then uses real input/physics to enter and return. It is not
human play, browser gameplay, full traversal or balance qualification.

Independent exact-head review and green CI are required before landing.
