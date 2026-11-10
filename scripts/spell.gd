extends Resource
class_name Spell
## Spell definition (#3). Data-driven: all stats live on the resource, never
## hardcoded in casting logic.
## Consumed by: #4 concrete spells, #10 pickups (carry Spell resources),
## #11 HUD (name + cooldown state).

## Stable identity, equal to the .tres file stem (e.g. &"mana_shot_volley").
## Code keys on this, never on spell_name, which is player-facing copy and is
## shared by several tiers (every Spirit Punch tier is "Spirit Punch").
@export var id: StringName = &""
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

## ---- #331 Water Ball tree. Every field defaults to OFF, so every existing
## spell casts exactly as before. Provisional placeholder numbers live on
## the water_ball*.tres resources only - balance is an open human choice.
## Steer branch, Specialization: pressing the spell's key while its shots are
## still flying re-aims them at the cursor instead of casting again.
@export var recast_redirect: bool = false
## (Daniel 2026-11-09: the first guided tier changes direction ONCE.) Max
## times one shot can be re-aimed by recast_redirect presses; a shot at its
## limit is ignored by the redirect gate, so the next press casts normally.
## 0 = unlimited (legacy behavior, e.g. Seeking).
@export var redirect_limit: int = 0
## Steer branch, Mastery: seconds each shot turns toward the cursor after it
## spawns (or after a redirect). A negative value chases for the shot's whole
## life (Signature). 0 = no cursor chase.
@export var cursor_chase_time: float = 0.0
## Max turn toward the cursor in rad/s while chasing.
@export var cursor_turn_rate: float = 7.0
## Steer branch, Signature: hits one shot lands before it disappears
## (Daniel 2026-11-09: the signature STAYS until it has hit 5 times - the
## travel-range expiry does not apply while pierce_hits > 0). Re-hits of the
## same body count too (see rehit_delay), so a boss is not a one-hit wall.
## 0 = legacy (despawn on the first hit unless PIERCING-tagged).
@export var pierce_hits: int = 0
## (Daniel 2026-11-09 boss fix.) Seconds a pierce_hits shot waits before it
## may damage the SAME body again; one pass-through still lands one hit, a
## loop back lands another. Only read when pierce_hits > 0.
@export var rehit_delay: float = 0.35
## Splash branch, Specialization: when > 0 the cast lobs a WaterSplash to the
## cursor (clamped to `range`) instead of a flat projectile; it lands and deals
## `damage` to every enemy within this radius. projectile_count lobs land
## around the cursor, scattered within splash_scatter px (Mastery).
@export var splash_radius: float = 0.0
@export var splash_scatter: float = 0.0
## Splash branch, Signature (heavy rain): when > 0 the cast opens a WaterRain
## zone at the cursor that drops a splash every rain_interval seconds at a
## random point within rain_radius, for rain_duration seconds.
@export var rain_duration: float = 0.0
@export var rain_interval: float = 0.2
@export var rain_radius: float = 0.0
## Bubble branch, Specialization: when > 0 the cast surrounds the player with
## a WaterShield of this radius for shield_duration seconds. It deals `damage`
## to touching enemies (once per shield_tick per enemy) and absorbs up to
## shield_charges enemy projectiles before it pops.
@export var shield_radius: float = 0.0
@export var shield_duration: float = 0.0
@export var shield_charges: int = 0
@export var shield_tick: float = 0.5
## Bubble branch, Mastery: when the shield ends it pushes every enemy within
## shield_push_radius away from the player at shield_push_force px/s.
@export var shield_push_radius: float = 0.0
@export var shield_push_force: float = 0.0
## Bubble branch, Signature: casting while the shield is up fires this spell
## (a plain Water Ball) instead, costing shield_shot.cooldown, and shrinks
## the ball by shield_shrink of its radius. Once the shield is gone the slot
## waits this spell's own `cooldown` before a new shield can be cast.
@export var shield_shot: Spell = null
@export var shield_shrink: float = 0.0

## ---- #370 Stone Hammer tree. Every field defaults to OFF, so every existing
## spell casts exactly as before. Provisional placeholder numbers live on the
## stone_hammer*.tres resources only - balance is an open human choice.
## Base: when > 0 the cast is an overhead hammer swing (StoneHammer) that
## crashes down on the aim point (clamped to `range`) after hammer_windup
## seconds and deals `damage` to every enemy within this radius.
@export var hammer_radius: float = 0.0
@export var hammer_windup: float = 0.3
## Crush route, Specialization: crit chance the hammer gains for the rest of
## the run per enemy it kills (0.1 = +10%). Kept on the caster, so it carries
## over into the route's later tiers.
@export var hammer_kill_crit: float = 0.0
## Crush route, Mastery: strike radius (and drawn hammer) scale by
## 1 + crit_chance * hammer_crit_scale, capped at hammer_max_scale.
@export var hammer_crit_scale: float = 0.0
@export var hammer_max_scale: float = 3.0
## Crush route, Signature: holding the key opens a HammerVortex of this
## radius at the strike point that pulls enemies in at up to
## hammer_vortex_pull px/s; releasing the key swings.
@export var hammer_vortex_radius: float = 0.0
@export var hammer_vortex_pull: float = 0.0
## Rhythm route, Specialization: each consecutive hit takes this many seconds
## off the next cooldown (down to hammer_min_cooldown). A miss, or
## hammer_combo_idle_reset seconds without a swing, resets the combo.
@export var hammer_combo_cdr: float = 0.0
@export var hammer_min_cooldown: float = 0.5
@export var hammer_combo_idle_reset: float = 30.0
## Rhythm route, Mastery: the player jumps (invulnerable during the wind-up)
## and the impact sends out a shockwave that deals hammer_shockwave_damage
## to enemies within hammer_shockwave_radius the hammer itself missed.
## Shockwave damage never counts as a hit.
@export var hammer_jump: bool = false
@export var hammer_shockwave_radius: float = 0.0
@export var hammer_shockwave_damage: float = 0.0
## Rhythm route, Signature: every hammer_dice_every consecutive hits roll a
## die above the player; face N rolls hammer_dice_tables[N - 1].
@export var hammer_dice_every: int = 0
@export var hammer_dice_tables: Array[RewardTable] = []
