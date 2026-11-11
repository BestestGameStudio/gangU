extends Node
## Opt-in observer only. No gameplay setters, overlays, delta clamps or gates.
var metadata: Dictionary = {}
var raw_intervals_us: Array[int] = []
var snapshots: Array[Dictionary] = []
var observed_region_wakes := 0
var _states: Dictionary = {}
var _scope: Node
var _loader: Node
var _last_us := 0
var _callbacks := 0
var _limit := 600
var _finished := false

func start(scope: Node, loader: Node, meta: Dictionary, limit: int = 600) -> void:
	_scope = scope
	_loader = loader
	metadata = meta.duplicate(true)
	_limit = limit
	_last_us = Time.get_ticks_usec()
	snapshots.append(_counts())
	set_process(true)

func _process(_delta: float) -> void:
	if _finished or _scope == null:
		return
	var now := Time.get_ticks_usec()
	raw_intervals_us.append(now - _last_us)
	_last_us = now
	_callbacks += 1
	if _callbacks % 30 == 0:
		snapshots.append(_counts())
	if _limit > 0 and _callbacks >= _limit:
		finish()

func _counts() -> Dictionary:
	var area: Node = _scope
	if _loader != null:
		area = _loader.get("current_area") as Node
	var living := 0
	var eligible := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if area != null and area.is_ancestor_of(enemy) and enemy is Enemy and enemy.hp > 0:
			living += 1
			if enemy.can_process():
				eligible += 1
	var region_count = null
	var active_count = null
	var wakes = null
	if _loader != null and _has_property(_loader, &"regions"):
		region_count = 0
		active_count = 0
		for region in _loader.get("regions"):
			region_count += 1
			if region.active:
				active_count += 1
			var id: int = region.get_instance_id()
			if _states.has(id) and not _states[id] and region.active:
				observed_region_wakes += 1
			_states[id] = region.active
		wakes = observed_region_wakes
	var renderer_available := DisplayServer.get_name() != "headless"
	return {
		"callback": _callbacks, "tree_nodes_including_probe": get_tree().get_node_count(),
		"living_enemies_current_scope": living, "process_eligible_enemies": eligible,
		"process_disabled_enemies": living - eligible,
		"region_count": region_count, "active_regions": active_count,
		"observed_region_false_to_true_transitions": wakes,
		"renderer_objects_in_frame": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME) if renderer_available else null,
		"renderer_draw_calls_in_frame": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME) if renderer_available else null
	}

static func _has_property(object: Object, property: StringName) -> bool:
	for item in object.get_property_list():
		if item.name == property:
			return true
	return false

func finish(path: String = "user://gameperf.json") -> Dictionary:
	if _finished:
		return {}
	_finished = true
	set_process(false)
	snapshots.append(_counts())
	var result := {
		"metadata": metadata, "raw_process_callback_intervals_us": raw_intervals_us,
		"count_snapshots": snapshots,
		"semantics": "Monotonic callback cadence, not render duration/FPS. Periodic counts add observer overhead. Region transitions are observed at snapshots, not an exhaustive event counter. Initial region state is not a transition. Process eligibility is not physics sleep. Renderer counters are not scene nodes drawn."
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		result["export_error"] = FileAccess.get_open_error()
	else:
		file.store_string(JSON.stringify(result))
	print("GAMEPERF_JSON ", JSON.stringify(result))
	return result

static func metadata_from_args() -> Dictionary:
	var args := OS.get_cmdline_user_args()
	var sha := "unknown:not-supplied"
	for arg in args:
		if arg.begins_with("--gameperf-sha="):
			sha = arg.trim_prefix("--gameperf-sha=")
	return {
		"commit_sha": sha, "godot_version": Engine.get_version_info().string,
		"backend": {"display": DisplayServer.get_name(), "rendering_method": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name()},
		"seed": null, "frame_schedule": "passive first600 process callbacks after Main boot; count snapshot every30 callbacks; no seed or simulation settings changed",
		"workload": "opt-in passive production observation", "browser_acceptance": false
	}
