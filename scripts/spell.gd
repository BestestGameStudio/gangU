extends Resource
class_name Spell
## Spell definition (#3). Data-driven: all stats live on the resource, never
## hardcoded in casting logic.
## Consumed by: #4 concrete spells, #10 pickups (carry Spell resources),
## #11 HUD (name + cooldown state).

@export var spell_name: String = "Spell"
## UI art for spell rows and slots. Null renders an empty placeholder box.
@export var icon: Texture2D = null
@export var cooldown: float = 0.5 ## Seconds before this spell can be recast.
@export var damage: float = 10.0
@export var radius: float = 4.0 ## Projectile hit radius in pixels.
@export var tags: Array[StringName] = [] ## Delivery + effect classification (#66). Metadata only, from the SpellTags vocabulary; never behavior parameters.
@export var range: float = 600.0 ## Max projectile travel distance in pixels.
@export var projectile_speed: float = 500.0
@export var projectile_color: Color = Color(0.4, 0.8, 1.0)
## (Progression placeholder mechanics, #33/#36) How many projectiles one cast
## fans out, and the total fan width. 1/0.0 = today's single-projectile
## behavior, so every existing spell is unchanged. Provisional placeholder
## numbers only - balance is an open human choice.
@export var projectile_count: int = 1
@export var spread_degrees: float = 0.0
