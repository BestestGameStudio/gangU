# Abandoned village (#484)

One fixed southern overworld village at (576,1400). Six cosmetic ruined houses leave the square maneuverable. One east-west dirt road crosses the forest. Two loose rows of trees have aligned walking gaps, following the requested thinner forest; trees keep their existing movement/projectile blocking rules.

The village is a LocationTrigger carrying an AmbushEvent. Main's existing mounter/context starts it. Thirty standard mustache men spawn evenly around a 320px circle through EnemySpawner. Killing all 30 drops a 100c clear reward through RewardDrop; standard 5c enemy drops remain. Walking out along either road despawns survivors with no clear bonus. A forced escape beyond the outer boundary also ends the encounter.

Implementer defaults: one attempt per run, 100c bonus, cosmetic/walk-through ruins. Main's existing trigger-fire history prevents farming on area remount; no shared event/host API changes.

No new tests created or tests run locally. The existing test365 production-trigger assertion is updated with owner approval. It now expects the abandoned village trigger while still checking that arrival fires no event. Editor import and disclosed recording-only showcases are not regression-suite evidence.

Demo: staged arrival, 10,000 HP, scripted movement; production event/spawn/AI/reward code. The clear beat applies disclosed synthetic damage, not natural combat. Escape beats use normal movement. Independent review and green required CI remain gates.

Sprite revision: original static four-cell prop atlas replaces all house/well/ruin shapes; clearing disk removed. Generated imports with Godot 4.5.1, nearest filtering, reproducible Python generator and SOURCE.md provenance.
