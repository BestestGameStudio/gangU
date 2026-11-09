class_name LocationTrigger
extends Area2D
## #365: a place in an area that starts an event when the player walks in.
##
## FOUNDATION ONLY. The trigger knows WHERE (its own CollisionShape2D children,
## authored in the scene - any shape, any size) and WHAT (an OverworldEvent
## resource). It does not decide repeat or reset rules: those are open design
## questions, so they live behind the should_fire() seam (same role as
## EnemySpawner.should_spawn) and the armed flag, and the host (Main) keeps
## the run-scoped history a later rule would read.
##
## Default behaviour: a Player body entering an armed trigger fires it. Every
## entry fires again; nothing is consumed. A one-shot, per-visit or per-run
## rule is a should_fire override, a subclass, or the host calling disarm().
##
## Main wires every LocationTrigger of a mounted area (group
## "location_triggers"): on `triggered` it builds an OverworldEventContext and
## starts the event, so the trigger itself stays free of game wiring.

## Stable name for this trigger. Main's run-scoped fire history is keyed by
## it; empty falls back to the node name.
@export var trigger_id: StringName = &""
## What happens when the trigger fires. Null = the trigger only emits
## `triggered` (scripts can listen to it directly).
@export var event: OverworldEvent
## False ignores bodies until arm() is called.
@export var armed: bool = true

## Fired after should_fire() accepted the body. `body` is the Player.
signal triggered(trigger: LocationTrigger, body: Node2D)

## Times this trigger instance fired (resets with the area, i.e. per visit).
var fire_count := 0

func _ready() -> void:
	add_to_group("location_triggers")
	body_entered.connect(_on_body_entered)

func id() -> StringName:
	return trigger_id if trigger_id != &"" else StringName(name)

func arm() -> void:
	armed = true

func disarm() -> void:
	armed = false

## Policy seam. Default: any Player while armed. Override for repeat/reset
## rules, conditions (time, cleared dungeons, cooldowns) and so on.
func should_fire(body: Node2D) -> bool:
	return armed and body is Player

## Fires the trigger for `body` if the policy allows. Returns true when it
## fired. Public so scripts and tests can fire it without physics.
func try_fire(body: Node2D) -> bool:
	if not should_fire(body):
		return false
	fire_count += 1
	triggered.emit(self, body)
	return true

func _on_body_entered(body: Node2D) -> void:
	try_fire(body)
