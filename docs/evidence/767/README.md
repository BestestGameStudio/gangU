# Settings key rebinding

Preserves current keys: WASD movement, Shift dash, LMB/RMB/Q/E/R spell slots, Space legacy cast, Ctrl alternate cast, H heal, C consumable, Tab spell menu, M map. Water Shot now starts in Q's slot on a new run, without overwriting occupied slots or changing restored runs. Custom bindings still win.

Click a binding, then press a physical key or mouse button (left/right/middle/side buttons). Escape cancels capture and stays reserved for Settings. Wheel rejected. Conflicts name the other action and keep the original bindings. No silent swap. Reset restores all default controls only, preserving audio. Changes save immediately in settings.cfg and reload on scene/restart. Save errors are shown.

Spell slot labels and HUD tooltips use actual bindings. Ctrl alternate-fire now uses a rebindable action rather than hardcoded key polling. Input capture is consumed before other UI handlers. Existing modal casting guard remains.

Actual Settings and conflict screens captured in running main.tscn and visually checked at1152x648. Focused regression checks cover changed key routing, old key removal, mouse binding, conflict, Escape cancel, alternate modifier, reset, persistence, audio preservation, and new-run Q placement.
