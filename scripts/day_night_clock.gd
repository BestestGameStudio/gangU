extends Node
class_name DayNightClock
## #448 (Daniel, 2026-11-09): foundations for a day/night cycle. One node,
## parked on the SceneTree ROOT (not inside any area scene): the overworld
## is freed on every area swap (main.gd _swap), so anything living in
## overworld.tscn would stop the moment the player enters a dungeon - and
## Daniel's call is that the clock KEEPS RUNNING in dungeons ("Keep
## running"). Root-parking also survives reload_current_scene, like the
## other persistent managers.
##
## Visual-only foundations: the clock exposes a time and a tint; no
## gameplay effects (enemies, spawns, drops) read it yet.
##
## #351 FLAG (unspecified by Daniel, implementer's pick): the clock does
## NOT reset on death. It stays out of RunManager.RUN_STATE_GROUP - time of
## day is persistent world state (like the Bestiary's meta records), not
## run state, and resetting the clock on death would be a gameplay effect,
## which this issue rules out of scope.

## One full day/night cycle in seconds (Daniel: "about 10 minutes" -> 600).
const CYCLE_SECONDS := 600.0
const GROUP := &"day_night_clock"

## Fraction of the cycle in [0, 1): 0.0 midnight, 0.25 sunrise, 0.5 noon,
## 0.75 sunset. Runs start mid-morning so the world opens in daylight.
var time_of_day := 0.35

func _ready() -> void:
	add_to_group(GROUP)

func _process(delta: float) -> void:
	advance(delta)

## Advance the clock; wraps at the end of the cycle. Pulled out of
## _process so harnesses can drive it deterministically.
func advance(delta: float) -> void:
	time_of_day = fposmod(time_of_day + delta / CYCLE_SECONDS, 1.0)

## The CanvasModulate tint for the current time. White = unmodified
## daylight; the night tint is a dark blue so local lights (gate and
## portal PointLight2D, #189) keep glowing on top of it.
func tint_color() -> Color:
	return _sample_tint(time_of_day)

## Keyframed tint ramp, smoothstep-blended between keys so dawn and dusk
## ease instead of snapping.
const TINT_KEYS: Array = [
	[0.00, Color(0.30, 0.33, 0.55)], # midnight
	[0.18, Color(0.30, 0.33, 0.55)], # night holds
	[0.29, Color(1.00, 0.78, 0.60)], # sunrise warms up
	[0.37, Color(1.00, 1.00, 1.00)], # full day
	[0.64, Color(1.00, 1.00, 1.00)], # day holds
	[0.72, Color(1.00, 0.70, 0.52)], # sunset
	[0.82, Color(0.30, 0.33, 0.55)], # night falls
	[1.00, Color(0.30, 0.33, 0.55)], # wraps to midnight
]

static func _sample_tint(t: float) -> Color:
	for i in range(1, TINT_KEYS.size()):
		var t1: float = TINT_KEYS[i][0]
		if t <= t1:
			var t0: float = TINT_KEYS[i - 1][0]
			var span := t1 - t0
			var f := 0.0 if span <= 0.0 else clampf((t - t0) / span, 0.0, 1.0)
			f = f * f * (3.0 - 2.0 * f) # smoothstep
			return (TINT_KEYS[i - 1][1] as Color).lerp(TINT_KEYS[i][1], f)
	return TINT_KEYS[0][1]

## Find the parked clock, or null when nothing parked one yet.
static func find_clock(tree: SceneTree) -> DayNightClock:
	return tree.get_first_node_in_group(GROUP) as DayNightClock

## Find or park the ONE shared clock on the tree root. Idempotent; called
## by main.gd at boot and by the overworld tint driver, so harnesses that
## mount only the overworld still get a clock.
static func ensure(tree: SceneTree) -> DayNightClock:
	var existing := find_clock(tree)
	if existing != null:
		return existing
	var clock := DayNightClock.new()
	clock.name = "DayNightClock"
	tree.root.add_child.call_deferred(clock)
	return clock
