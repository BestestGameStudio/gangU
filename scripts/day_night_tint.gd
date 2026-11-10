extends CanvasModulate
class_name DayNightTint
## #448: the overworld's day/night tint. Lives in scenes/overworld.tscn and
## simply follows the root-parked DayNightClock - the clock itself is
## outside this scene so it keeps running while the player is in dungeons.
## Visual only for now: nothing gameplay-side reads the time of day.

func _ready() -> void:
	DayNightClock.ensure(get_tree())

func _process(_delta: float) -> void:
	var clock := DayNightClock.find_clock(get_tree())
	if clock != null:
		color = clock.tint_color()
