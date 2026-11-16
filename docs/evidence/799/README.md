# Hook reel contact stop (#799)

Player stop radius is 32px. Initial 24px candidate ran into real player/enemy collision shapes before reaching its threshold. Anchor targets keep the existing18px radius.

Single reels accelerate in speed, but their direction points directly inward each tick. Steps stop at the player radius instead of carrying tangential inertia. Shared group center and member motion use the same inward steering; member steps are capped at their assigned bunch slot and swept against the player stop circle. Arrival zeros reel and enemy velocity, then retains existing Catch stun/ownership release behavior.

Actual running-main-scene recording reel-stop.mp4: base Hook, then three-enemy Magnet. The player moves during the pull. Both stop on the near side without swinging, and remain still after release. The displayed distance can grow slightly above32px because the scripted player finishes moving after the enemy stops. Script only stages casts, movement and enemies; production caster/projectile/reel/enemy code runs unchanged apart from this fix. Initial art is still the current-main placeholder, not pending#790 sprites.

Validation: full53/53 local suite PASS, including new test799 covering all currently landed tiers, single and group arrival, injected lateral momentum and swept long steps. The same regression includes Rock automatically once its resource lands. Review/CI are still required before merge.
