extends Resource
class_name Spell
## Spell definition (#3). Data-driven: all stats live on the resource, never
## hardcoded in casting logic.
## Consumed by: #4 concrete spells, #10 pickups (carry Spell resources),
## #11 HUD (name + cooldown state).

@export var spell_name: String = "Spell"
## UI art for spell rows and slots. Null renders an empty placeholder box.
@export var icon: Texture2D = null
## (#207) Shared SpriteFrames holding "<icon_prefix>_base", "<icon_prefix>_upgraded"
## and "<icon_prefix>_sweep" animations. Used when icon is null; the placeholder
## box still renders when both are null.
@export var icon_frames: SpriteFrames = null
## Animation-name prefix inside icon_frames, e.g. &"fireball".
@export var icon_prefix: StringName = &""
## True on upgrade-result spells (#207): the "<icon_prefix>_upgraded"
## green-chevron frame replaces the base frame.
@export var icon_upgraded: bool = false
@export var cooldown: float = 0.5 ## Seconds before this spell can be recast.
@export var damage: float = 10.0
@export var radius: float = 4.0 ## Projectile hit radius in pixels.
@export var tags: Array[StringName] = [] ## Delivery + effect classification (#66). Metadata only, from the SpellTags vocabulary; never behavior parameters.
@export var range: float = 600.0 ## Max projectile travel distance in pixels.
@export var projectile_speed: float = 500.0
@export var projectile_color: Color = Color(0.4, 0.8, 1.0)
## (#263) Visual-only projectile feel. None of these touch hit radius,
## movement, damage or despawn. Defaults keep every other spell unchanged.
## Multiplier on the supplied-art sprite size (base footprint is radius/16).
@export var visual_scale: float = 1.0
## Draws a soft additive halo in projectile_color behind the projectile.
@export var glow: bool = false
## Number of past positions in the fading trail; 0 = no trail.
@export var trail_length: int = 0
## (Progression placeholder mechanics, #33/#36) How many projectiles one cast
## fans out, and the total fan width. 1/0.0 = today's single-projectile
## behavior, so every existing spell is unchanged. Provisional placeholder
## numbers only - balance is an open human choice.
@export var projectile_count: int = 1
@export var spread_degrees: float = 0.0
## (#209) Summon hook: when set, casting this spell asks the SummonManager to
## spawn this definition (the shared cap applies). Null on every existing
## spell, so casting behavior is unchanged. The first concrete summon spell
## is #212.
@export var summon: SummonDefinition = null
