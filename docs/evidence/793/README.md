# Tide repeated hits (#793)

Root cause: WaterShotProjectile used its repeat-contact timer only while hovering. During flight it fell back to Projectile's one-hit-per-enemy guard, so even a later redirected pass was refused.

The Signature's existing0.5s per-enemy interval now applies both while travelling and hovering. Transitions do not reset the timer. Early recontacts still do no damage; Mastery and Specialization retain one hit per enemy. No resource values or other spell behavior changes.

Regression test793 uses the real Tide resource and real enemy HP dispatch for first pass, early refusal, later repeat pass, hover/release transitions and lower-tier exclusion. Updated test717's old expectation that released Tide could never hit the same target again, which this bug request explicitly changes.

Runtime video repeat-passes.mp4 and still repeat-passes.png use real Player/SpellCaster/Tide/BeastBoss scenes in an empty Node2D staging area to avoid hub world blockers. Scripted redirects send the same shot across the same enemy four times: HP340->328->316->304->292. Actual sprite/physics/HP dispatch, not simulated labels.
