class_name DungeonModifier
extends Resource
## (#222) Dungeon modifier: a dungeon-specific effect paired with a trigger
## that is declared HERE, on the modifier side. Daniel: modifiers can be
## "triggered from a variety of events not specifically to anything", e.g. a
## specific enemy's death or dungeon entry.
##
## The trigger is just an event name plus an optional payload filter. The
## systems that raise events (Enemy, DungeonObjective, SpellCaster,
## RunManager, Main's area mount) never know which modifiers exist;
## DungeonModifierHost bridges their signals into named events and routes
## them here. Any other code can raise its own event through
## DungeonModifierHost.emit_event without changing this class.
##
## FOUNDATION ONLY: no production modifiers ship. The modifier list, effects,
## numbers and how modifiers are acquired/assigned are human-open.

## Stable logical identity (for UI, saves or dedupe later).
@export var id: StringName
@export var display_name: String = ""
## Event name that fires this modifier, e.g. DungeonModifierHost.ENEMY_DIED,
## DungeonModifierHost.DUNGEON_ENTERED, or any custom event name.
@export var trigger_event: StringName
## Optional payload filter: EVERY key must be present in the event payload
## with an equal value. Empty = any occurrence of trigger_event fires.
## Example, a specific enemy's death:
##   trigger_event = &"enemy_died"
##   trigger_filter = {"enemy_scene": "res://game/enemies/bosses/mustache_warlord.tscn"}
@export var trigger_filter: Dictionary = {}
## How many times this modifier may fire per mount. 0 = unlimited.
@export var max_triggers: int = 0
@export var effect: DungeonModifierEffect

func is_valid_definition() -> bool:
	return id != &"" and trigger_event != &"" and effect != null and max_triggers >= 0

## True when this modifier's trigger accepts the given event + payload.
func matches(event: StringName, payload: Dictionary) -> bool:
	if event != trigger_event:
		return false
	for key: Variant in trigger_filter:
		if not payload.has(key) or payload[key] != trigger_filter[key]:
			return false
	return true
