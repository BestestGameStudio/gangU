# Hook Shot base (#781)

Snapshot aim at cast, clamped560px;750px/s hook;1s cooldown. Shared swept circle collision selects the first body and respects world/terrain blockers without damaging either enemies or terrain. Hooked enemies reel to the player's CURRENT location, not the original cast point. Normal enemy locomotion is suspended only while a live displacement owner holds them; lifecycle/damage remains active.

Reel speed = min(1200,600 * displacement_force / max(weight,0.1)) px/s. Displacement1 by default. Steering acceleration2400px/s² retains side-to-side velocity as the player changes direction; resultant speed stays capped. Arrival18px, timeout8s, wall/terrain/boundary respecting movement; target death, owner loss, scene exit and timeout release control.

Both Fishy definitions drop Hook Shot through the existing reward pool until pickup. Hook Shot is also in the base-spell shop catalog at its established10c price, preserving the catalog's all-base-spells rule.

Quest plumbing: non-damaging hook result signals, separate from OnHit. Three consecutive successful casts qualify; an unsuccessful cast resets an unfinished streak. A completed quest stays complete. Actual Magnet Fishing row is in the next stacked PR. Spell art remains temporary geometry until SpriteU PR790.

Focused test781: actual swept first-enemy detection, HP unchanged, moving target/lateral inertia, force/weight/cap math, single owner, cleanup, streak reset/completion, both Fishy rewards and grant exclusion. Existing shop test passes after catalog integration.

Running-game clip: hook-demo.mp4 and still hook-demo.png. Real main scene/caster, spawned enemy at weight3 for slower visible reel; scripted player movement reverses vertically while the reel continues. Temporary geometry pending SpriteU art.
