# Water Shot range (#791)

All four Water Shot tiers now travel **1280 world pixels**, up from 560. This is 128 pixels (about 11%) beyond the game's default 1152px-wide view at normal zoom1. It is a fixed stat, not a promise to exceed every resized browser window. Projectile speed remains750px/s, cooldown and all other fields unchanged.

Godot4.5.1 suite47/47 passes. `test791_water_shot_range` loads all four production resources and the real main-scene camera, checks1280 exceeds the default screen width at its actual zoom, and preserves750px/s speed. Hover and redirect destinations use the same range field, so their caps increase with the base shot.
