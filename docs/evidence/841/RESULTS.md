# #841 cached layer visibility

Base fea7efe4e515760b59108b277e4a4ed797341d51. Native Godot4.5.1.

Bug is transient, not persistent in ordinary dormant case: return overworld from hub forces dormant arena CanvasLayer visible, next arena physics tick hides it again. Rendering between physics ticks displays an empty boss bar at top center. Repro with fixed simulated render240Hz / physics60Hz; movie slowed60x to make the flash legible. This is controlled native simulation, not measured actual GPU240FPS or browser qualification. Initial10Hz movie showed no flash, prompting this correction. No art/light/audio/gameplay change.

Fix stores each existing CanvasLayer visible state when parked, hides all, restores only recorded states, clears snapshot. First mount and new layers untouched. Repeated park does not overwrite originals. Freed IDs retain only booleans until restore then clear, no nodes held alive.

Validation: own native full suite62/62 PASS, including test841 hidden/visible first mount, repeated park/restore, changed runtime visibility, freed/new layer, two actual Main hub trips. Before PNG shows erroneous bar at x336..815 y64..79; after PNG bar absent. Working movie records actual native area transitions; clips slowed60x and labeled before/after. Random movement/world details can differ, not a whole-frame pixel identity claim. Existing overlays and HUD preserved. No new art authored.

Reproduce: godot --path . --rendering-method gl_compatibility --resolution1152x648 --fixed-fps240 --write-movie /tmp/demo.avi --script docs/evidence/841/visual-driver.gd (separate space before numeric argument values). CASE environment selects screenshot suffix under /downloads. Driver awaits one rendered frame immediately after cached return; no arena visibility mocked.
