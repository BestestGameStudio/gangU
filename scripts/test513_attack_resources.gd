extends SceneTree
## #513: authored Resource assets retain all former constant-backed values.
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("[513 resources] ",label," -> ","PASS" if ok else "FAIL")
func _initialize() -> void:
	for b in [EnemyBehaviorHead.new(),EnemyBehaviorBeast.new(),EnemyBehaviorWarlord.new()]:
		var script: Script = b.get_script()
		var c := script.get_script_constant_map()
		if b.volley_data != null:
			var d = b.volley_data
			_check(d is BossVolleyData and d.resource_path.begins_with("res://resources/boss_attacks/"),"authored volley resource")
			for pair in [["shots","VOLLEY_SHOTS"],["enraged_shots","VOLLEY_SHOTS_ENRAGED"],["spread","VOLLEY_SPREAD_DEG"],["enraged_spread","VOLLEY_SPREAD_ENRAGED_DEG"],["fire_at","VOLLEY_FIRE_AT"],["second_wave_at","VOLLEY_SECOND_WAVE_AT"],["duration","VOLLEY_TIME"],["muzzle_offset","MUZZLE_OFFSET"]]:
				_check(d.get(pair[0]) == c[pair[1]],"volley "+pair[0]+" matches original constant")
		if b.lunge_data != null:
			var d = b.lunge_data
			_check(d is BossLungeData,"typed lunge resource")
			for pair in [["speed","LUNGE_SPEED"],["enraged_speed","LUNGE_SPEED_ENRAGED"],["duration","LUNGE_TIME"],["hit_range","LUNGE_HIT_RANGE"],["damage","LUNGE_DAMAGE"]]:
				_check(d.get(pair[0]) == c[pair[1]],"lunge "+pair[0]+" matches original constant")
		if b.ring_data != null:
			var d = b.ring_data
			var prefix := "PULSE" if b is EnemyBehaviorHead else "SCREAM"
			_check(d is BossRingData and d.radius == c[prefix+"_RADIUS"] and d.enraged_radius == c[prefix+"_RADIUS_ENRAGED"],"ring radii unchanged")
			_check(d.damage == c[prefix+"_DAMAGE"] and d.display_time == c[prefix+"_TIME"],"ring damage and duration unchanged")
	for kind in [BossVolleyData.new(),BossLungeData.new(),BossRingData.new()]:
		var exports := 0
		for p in kind.get_property_list():
			if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.usage & PROPERTY_USAGE_EDITOR: exports += 1
		_check(exports > 0,"attack data exposes editor tuning")
	quit(1 if failures else 0)
