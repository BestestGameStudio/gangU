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
## Multiplier on the halo and trail size (spell.radius * visual_scale). The
## sprite's size comes from Projectile's clamped radius sizing instead (#289).
@export var visual_scale: float = 1.0
## Draws a soft additive halo behind the projectile (colour: see glow_tint).
@export var glow: bool = false
## Number of past positions in the fading trail; 0 = no trail.
@export var trail_length: int = 0
## (#289) Halo and trail colour when its alpha is above 0, so they can match the
## sprite art. Alpha 0 uses projectile_color. Only the glow and trail read this.
@export var glow_tint: Color = Color(0, 0, 0, 0)
## (#289) Fraction of the trail, measured from the head, that fades out so no
## solid end shows behind the sprite. 0 keeps the full-strength head end.
@export var trail_head_fade: float = 0.0
## (Progression placeholder mechanics, #33/#36) How many projectiles one cast
## fans out, and the total fan width. 1/0.0 = today's single-projectile
## behavior, so every existing spell is unchanged. Provisional placeholder
## numbers only - balance is an open human choice.
@export var projectile_count: int = 1
@export var spread_degrees: float = 0.0
## (#305) Burst: how many times one cast repeats its fan-out, and the pause
## between repetitions in seconds. 1 = a single fan-out, so every existing
## spell is unchanged. One cooldown per cast regardless of burst length.
## Provisional placeholder numbers only - balance is an open human choice.
@export var burst_count: int = 1
@export var burst_interval: float = 0.1
## (#305) Launch (Mastery: the player is launched forward BEFORE attacking):
## launch speed in px/s and duration in seconds. launch_speed 0.0 = no
## launch, so every existing spell is unchanged. Provisional placeholder
## numbers only - balance is an open human choice.
@export var launch_speed: float = 0.0
@export var launch_duration: float = 0.12
## #305 Signature freeze bubble: when freeze_radius > 0, casting also
## spawns a FreezeBubble anchored at the cast point for freeze_duration
## seconds (Daniel: 5s, stays where you cast). Default 0 on every existing
## spell, so casting behavior is unchanged. Provisional placeholder numbers
## only - balance is an open human choice.
@export var freeze_radius: float = 0.0
@export var freeze_duration: float = 0.0
## (#209) Summon hook: when set, casting this spell asks the SummonManager to
## spawn this definition (the shared cap applies). Null on every existing
## spell, so casting behavior is unchanged. The first concrete summon spell
## is #212.
@export var summon: SummonDefinition = null
## (#216) Terrain-block hook: when set to a destroyable TerrainTypes id,
## casting places that tile at the aimed cell (within `range` pixels) through
## TerrainBlock. A refused placement (no terrain in the area, unwalkable or
## occupied cell) is not a cast: no cooldown, no signals. Empty on every
## other spell, so their casting is unchanged.
@export var terrain_block: StringName = &""
