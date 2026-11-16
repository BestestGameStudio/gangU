# Tide redirect without cooldown

Signature means Water Shot Tide. Its water_shot_redirect_cooldown is now0.0 instead of the inherited0.5. Base/Hover/Reservoir unchanged. Spell cast cooldown remains0.5; contact damage interval remains0.5. Repeat redirects still use Ctrl+fire and return to hover. Description no longer says redirect has a cooldown.

Actual WaterShotProjectile and SpellCaster harness verifies two consecutive redirect calls both succeed without advancing time; repeated travelling re-aim remains allowed. Full suite43/43 passes. Existing card-fit assertion also passes with shorter corrected description.
