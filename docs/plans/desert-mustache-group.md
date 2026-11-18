# Unplaced desert mustache squad

Owner direction: groups of5 travel together, spread and keep distance when a
player approaches, one leader throws lightweight SpriteU smoke, then all living
members charge on actual grenade landing. No level, SpawnData, catalog or
encounter mounts this scene. Place the group under a mounted area when placement
is separately authorized; its player_path and terrain_path are explicit seams.

The group owns formation/phase/leader election; independent EnemyBehavior
instances own terrain-safe desired movement and contact damage through Enemy's
existing DamageCalc/OnHit API. No shared Enemy/area-loader changes. Dead members
are pruned, leadership transfers to a survivor, frozen/stunned leader cannot
advance the throw, and lost/hidden/dead/far player regroups. A grenade already in
flight belongs to the area, not its thrower. Generation-stamped landed callback
releases CHARGE once; a3s missing-landing timeout aborts/regroups, never invents a
landing. Shared grenade API dependency isolated to _throw and _on_smoke_landed.

PLACEHOLDER tuning: HP60, speed105/charge194.25px/s, damage10/contact0.8s/range35,
approach360/disengage760/keep230px, spread1.8s/windup0.4s/lob0.6s. Charge persists
until target loss/disengage. No respawning killed members. No reward-table or
objective selection. Original approved SpriteU22 atlas imported byte-identically.

Actual Main/Hub scripted15s demo shows all phases and contact damage. Player
HP boosted1000 for recording, approach/dodge scripted via real movement input,
no production placement. Native evidence, not human balance or browser play.
Current exit warning names existing OGG playback resources, not squad scripts.

## Smoke hold and scatter correction
The initial rigid V offsets were a placeholder, not owner direction. Replaced
with a loose irregular cluster, per-member travel pace and slow independent
arrival offsets. No sprite/animation source change. Once smoke lands, a player
inside live puffs can be charged/contacted; a player outside is not chased out.
Members use distinct interior puff points, even if the target is lost/dead/far.
Actual cloud exhaustion/expiry/removal releases3s outward scatter, then regroup
with4s re-arm delay. Knockback/terrain/freeze contracts still outrank propulsion.

## Placement after overworld reshape
Once #883 merged, place exactly1group/5members on the west desert approach.
A local overworld carrier checks an entire320x256 sand/walkable footprint outside
boss barrier+160 and at least320px from existing scorpion spawn samples. First
valid deterministic sample on current map is(-380,-960), west of boss center
(576,-960), about340px beyond its barrier. Short patrol is110x40 around that
anchor. No other group, new encounter, objective or respawn. Explicit player and
shared-terrain refs verified from actual Main/Overworld boot. Placement is
run-owned and retained with the cached overworld, reset by normal death reload.

## Shifty idle direction
Travel members choose independent twitch targets every0.16-0.52s, offset16-58px,
with24% short pauses and0.6-1.55 pace multiplier. Independent deterministic seeds
per member prevent synchronized changes. Existing group envelope, separation and
terrain/force constraints remain; smoke/charge phases do not use this idle jitter.

Engagement correction: same independent twitch/pace decisions also run through
spread/keep-range and nonleader throw/wait. Too-close retreat overrides a pause;
leader windup/wait remains steady for a reliable lob. Postlanding charge and
smoke-hold/scatter do not receive this pre-smoke jitter.
