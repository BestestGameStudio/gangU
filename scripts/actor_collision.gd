class_name ActorCollision
## #290: players and enemies never physically block or push each other.
##
## Every body in the project shares the default physics layer 1, and Areas
## (gates, pickups, portals) plus projectile sweeps rely on that mask, so the
## player/enemy pair is separated with per-pair collision exceptions instead
## of re-layering. Only the movement solver is affected: Area overlaps,
## projectile hits and distance-based contact damage are untouched, and both
## actors still collide with everything else (containers, summons, each other
## within their own side).
##
## Order-independent: whichever side enters the tree second pairs itself with
## every member of the other side's group. Exceptions are added in BOTH
## directions so neither body's move_and_slide sees the other.

const PLAYER_GROUP := &"players"
const ENEMY_GROUP := &"enemies"

static func ignore_pair(a: PhysicsBody2D, b: PhysicsBody2D) -> void:
	if a == null or b == null or a == b:
		return
	if not is_instance_valid(a) or not is_instance_valid(b):
		return
	if not a.is_inside_tree() or not b.is_inside_tree():
		return
	a.add_collision_exception_with(b)
	b.add_collision_exception_with(a)

## Pair `body` with every node of `group` that is a PhysicsBody2D.
static func ignore_group(body: PhysicsBody2D, group: StringName) -> void:
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return
	for n in body.get_tree().get_nodes_in_group(group):
		if n is PhysicsBody2D:
			ignore_pair(body, n)
