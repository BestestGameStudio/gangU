class_name SummonDefinition
extends Resource
## #209: per-summon-type definition (foundation). "Enemies targeting is
## configurable" (Daniel, 2026-11-08): enemy_targetable gates whether standard
## chase/contact enemies may pick this summon as their target.
## No lifetime, control, stat-scaling or acquisition fields: those stay open
## (#209 foundation excludes them; later issues own them).

@export var display_name: String = "Summon"
@export var max_hp: int = 30
## When false, standard enemies ignore this summon and keep chasing the player.
@export var enemy_targetable: bool = true
## Placeholder body color; real art is a later issue (no new art in #209).
@export var body_color: Color = Color(0.5, 0.7, 1.0)
