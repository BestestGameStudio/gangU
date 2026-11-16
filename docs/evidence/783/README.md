# Magnet Fishing (#783)

At its clamped aimed endpoint (up to560px), Hook Shot Specialization pulls all living enemies within72px. It passes through enemies on the way to that endpoint, but world blockers stop the shot. Same zero-damage and moving-player reel rules as base.72px is the chosen small-radius default.

The base upgrade quest is three successful hooks in consecutive casts; misses reset unfinished progress. Successful hook events, not damaging hits, advance it. Group-hook events count enemies acquired together, used by the next upgrade.

Test783 exercises three enemies within72px, one outside, and the exact serialized base quest. Test781 covers base and test129 preserves all-base-spell catalog inclusion. Art remains temporary until PR790.
