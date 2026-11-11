class_name DungeonModifierEffect
extends Resource
## (#222) Dungeon-modifier effect base: the "what happens" half of a
## DungeonModifier. Concrete effects extend this and override apply().
##
## FOUNDATION ONLY: no production effects ship. Which effects exist, their
## numbers, and whether damage effects compose through DamageCalc (#186) are
## human-open decisions.
##
## apply() receives the event that fired, its payload (see
## DungeonModifierHost for the payload keys per event) and the host, which
## exposes the mounted area (host.area) and dungeon id (host.dungeon_id).

func apply(_event: StringName, _payload: Dictionary, _host: DungeonModifierHost) -> void:
	pass
