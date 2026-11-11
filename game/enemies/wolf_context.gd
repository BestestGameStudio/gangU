class_name WolfContext
extends RefCounted
## #513: typed per-wolf context the owning WolfCave sets on Enemy.context
## (replaces the wolf_anchor / wolf_cave / wolf_index / wolf_retreat meta).
## A wolf without one (fixture wolves) hunts around its own position.

var cave: Node = null
var anchor: Vector2 = Vector2.ZERO
var has_anchor: bool = false
var index: int = 0
## Daybreak order from the cave: go home unless in a fight.
var retreat: bool = false
