class_name PhysicsLayers
## #515: the project's named 2D physics layers (also named in project.godot).
##
## Each scene sets its own layer (what it IS) and mask (what it can touch),
## so physics queries only see relevant bodies. This replaces the per-pair
## collision exceptions of the old ActorCollision (#290/#279/#493):
## players, enemies and summons never physically block each other because
## their masks simply leave each other's layers out. They all still collide
## with the WORLD layer (containers, barricades). Area triggers, pickups and
## projectile hits are separate masks below.
##
## Values are bit masks (layer N = 1 << (N - 1)), ready for collision_layer
## and collision_mask.

const WORLD := 1 ## layer 1: solid props (destroyable containers, barricades)
const PLAYER := 2 ## layer 2
const ENEMY := 4 ## layer 3 (bosses included)
const SUMMON := 8 ## layer 4
const PLAYER_PROJECTILE := 16 ## layer 5: shots from the Player or a Summon
const ENEMY_PROJECTILE := 32 ## layer 6: every other shot
const PICKUP := 64 ## layer 7: Area triggers (gates, portals, pickups, vendors)

## What a walking player or enemy collides with.
const ACTOR_MASK := WORLD
## Summons also keep blocking each other (legacy, test279).
const SUMMON_MASK := WORLD | SUMMON
## What a player-side shot can hit. The Player is left out (it never hits
## itself and a Summon's shot used to be absorbed by it); ownerless summons
## keep the legacy hit, so SUMMON stays.
const PLAYER_SHOT_MASK := WORLD | ENEMY | SUMMON
## What an enemy shot can hit: everything a body can be (legacy behavior).
const ENEMY_SHOT_MASK := WORLD | PLAYER | ENEMY | SUMMON
## Area triggers only react to the Player.
const TRIGGER_MASK := PLAYER
## Freeze bubbles catch enemies, summons and both sides' shots.
const FREEZE_MASK := ENEMY | SUMMON | PLAYER_PROJECTILE | ENEMY_PROJECTILE

## Group names kept from ActorCollision: "players" is collision/targeting-free
## bookkeeping used by the freeze bubble and tests.
const PLAYER_GROUP := &"players"
const ENEMY_GROUP := &"enemies"
