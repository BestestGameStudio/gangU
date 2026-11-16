# Catch and release (#785)

Mastery increases Magnet Fishing radius from72px to120px. Enemies reaching the player's current position are stunned for1.5s; the reel releases its locomotion claim. Stun pauses enemy AI/movement, not damage/lifecycle, and expires on the enemy physics clock. Frozen enemies do not advance stun clocks.

The Specialization quest requires acquiring at least3enemies in one endpoint pulse. The Mastery-to-Signature placeholder quest (next PR) uses5casts.

Test785 checks radius120, exact1.5s arrival stun, ownership cleanup, motion held during stun and expiry; serialized group quest threshold3. Art remains temporary until PR790.
