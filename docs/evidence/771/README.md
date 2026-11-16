# Tree trunk-base collision

All361overworld trees now have small exact rectangular hitboxes inside the narrow visible trunk base, above baked root shadow. Source rectangle8x6px on72px variants or6x6px on56px variant, scaled with the exact existing sprite transform. Example runtime tree:7.03x5.27world pixels. Canopies and surrounding old circle/cells no longer collide. Village footprints unchanged.

World-space rectangles drive movement, high-speed dash/blink sweep, projectiles, and real StaticBody debug shapes. Coarse navigation indexes cells touched by the trunk boxes for routing only; those cells are not made solid in the terrain store. Existing terrain walls/water/corners unchanged.

Actual main.tscn overworld debug-collision capture inspected at4x camera zoom. Magenta is Godot's actual CollisionShape2D debug color. The normally hidden Terrain presentation was temporarily made visible with its art layers hidden in the capture driver so engine collision shapes could be seen; no art/collision overlay was fabricated. Small box stays inside narrow trunk; canopy clear. Full44/44 tests pass, including exact trunk/projectile/movement/blink/navigation checks. Not interactive combat qualification.
