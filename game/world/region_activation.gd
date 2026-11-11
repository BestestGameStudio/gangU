class_name RegionActivation
extends Node
## Hysteresis avoids toggling a region at its edge. Polling is bounded and
## independent of frame rate; active encounters are never put to sleep.
@export var wake_distance: float = 768.0
@export var sleep_distance: float = 960.0
@export var interval: float = 0.25
var player: Player
var regions: Array[OverworldRegion] = []
var _remaining := 0.0
func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining > 0.0 or not is_instance_valid(player):
		return
	_remaining = interval
	update_now()
func update_now() -> void:
	for region in regions:
		if not is_instance_valid(region):
			continue
		var at := player.global_position
		var nearest := at.clamp(region.bounds.position, region.bounds.end)
		var distance := at.distance_to(nearest)
		var awake := region.keep_active() or distance <= (sleep_distance if region.active else wake_distance)
		if awake != region.active:
			region.set_active(awake)
		region.refresh_dormancy()
