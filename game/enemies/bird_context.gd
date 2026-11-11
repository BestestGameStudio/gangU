class_name BirdContext
extends RefCounted
## #513: typed per-bird context the OverworldBird manager sets on
## Enemy.context (replaces the bird_manager / bird_leave meta).

var manager: Object = null
## Nightfall order: fly off.
var leave: bool = false
