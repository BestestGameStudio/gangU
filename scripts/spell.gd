extends Resource
class_name Spell
## Spell definition (#3). Data-driven: all stats live on the resource, never
## hardcoded in casting logic.
## Consumed by: #4 concrete spells, #10 pickups (carry Spell resources),
## #11 HUD (name + cooldown state).

@export var spell_name: String = "Spell"
@export var cooldown: float = 0.5 ## Seconds before this spell can be recast.
@export var damage: float = 10.0
@export var radius: float = 4.0 ## Projectile hit radius in pixels.
@export var effects: Array[String] = [] ## Freeform effect tags, e.g. "burn".
@export var range: float = 600.0 ## Max projectile travel distance in pixels.
@export var projectile_speed: float = 500.0
@export var projectile_color: Color = Color(0.4, 0.8, 1.0)
