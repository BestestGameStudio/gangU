# Hook Shot SpriteU integration (#789)

Original SpriteU JSON + PNG exports retained under assets/spells/hook_shot/. SOURCE.md records source/export provenance and dimensions/pivots. Four spell icons, right-facing hook, tiled rope, placed rock anchor, lure and animated face music notes are wired to actual runtime nodes. Rope and notes never define collision bounds. Notes have three8x12frames/120ms, drawn above the player's face while pairs exist; one Fishy whistle voice per owner across all pairs.

Running main-scene capture hook-tiers.mp4 shows Catch and release taking three enemies together, then a Rock fishing pair reeling enemies to its fixed anchor. Rock-fishing.png is the inspected still. Temporary scripted player movement/spawn/casts only; real spell/caster/reel/enemy code. Sprites keep nearest-neighbor filtering. 51/51 local Godot suite passed before final global-default guard; final rerun recorded below.
