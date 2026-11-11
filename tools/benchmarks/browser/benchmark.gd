extends Node2D
## Separate artifact only; never attached to production Main.
const Probe = preload("res://game/core/game_perf_probe.gd")
var _started := false
var _result := {}
var _status: Label
func _ready() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var start := Button.new()
	start.text = "Start isolated seeded benchmark"
	start.position = Vector2(16, 16)
	ui.add_child(start)
	start.pressed.connect(_run)
	_status = Label.new()
	_status.position = Vector2(16, 56)
	_status.text = "OFF until Start. Isolated common systems, not folded world/FPS acceptance."
	ui.add_child(_status)
	var download := Button.new()
	download.text = "Download result JSON"
	download.position = Vector2(16, 88)
	ui.add_child(download)
	download.pressed.connect(_download)
func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
func _run() -> void:
	if _started:
		return
	_started = true
	_status.text = "Running isolated fixture: warm30 then180 physics ticks, no FPS gate."
	var seed_value := 548
	seed(seed_value)
	Bestiary.save_path = "user://browser_gameperf_bestiary.cfg"
	var fixture := Node2D.new()
	fixture.name = "IsolatedCommonSystems"
	add_child(fixture)
	var player: Player = load("res://game/player/player.tscn").instantiate()
	player.name = "Player"
	player.max_hp = 100000
	player.position = Vector2(576,324)
	fixture.add_child(player)
	player.damage_rng.seed = seed_value
	var positions := []
	for i in 8:
		var enemy: Enemy = load("res://game/enemies/enemy.tscn").instantiate()
		enemy.name = "Enemy%d" % i
		enemy.player_path = NodePath("../Player")
		enemy.position = player.position + Vector2.RIGHT.rotated(TAU * i / 8.0) * 64.0
		positions.append([enemy.position.x, enemy.position.y])
		fixture.add_child(enemy)
		enemy.damage_rng.seed = seed_value + i + 1
	await _frames(30)
	var metadata := JSON.parse_string(FileAccess.get_file_as_string("res://tools/benchmarks/browser/provenance.json")) as Dictionary
	var engine_metadata := Probe.metadata_from_args()
	metadata["engine_backend"] = engine_metadata.backend
	metadata.merge(engine_metadata, false)
	metadata.seed = seed_value
	metadata.frame_schedule = "explicit button;8enemies radius64/player576,324;warm30 then180 physics ticks at configured60Hz; process callbacks observed, not fixed rendering schedule"
	metadata["browser_acceptance"] = false
	metadata["workload"] = "isolated8 common-system contact enemies, production assets; benchmark-only100000HP endurance; local damage RNGs seeded AFTER _ready; no terrain/spells/kills"
	metadata["fixture_enemy_positions"] = positions
	metadata["player_hp_before_capture"] = player.hp
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.ganguRaf={raw:[],active:true,last:null};requestAnimationFrame(function tick(t){let s=window.ganguRaf;if(!s.active)return;if(s.last!==null)s.raw.push(t-s.last);s.last=t;requestAnimationFrame(tick);});")
	var probe := Probe.new()
	probe.name = "GamePerfProbe"
	fixture.add_child(probe)
	probe.start(fixture, null, metadata, 0)
	await _frames(180)
	metadata["player_hp_after_capture"] = player.hp
	if OS.has_feature("web"):
		metadata["browser_raf_intervals_ms"] = JSON.parse_string(JavaScriptBridge.eval("window.ganguRaf.active=false;JSON.stringify(window.ganguRaf.raw)"))
		metadata["browser_user_agent"] = JavaScriptBridge.eval("navigator.userAgent")
	probe.metadata = metadata
	_result = probe.finish("user://browser-gameperf.json")
	_status.text = "Done. Relative software-browser diagnostics only; download JSON."
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.ganguBrowserPerf=" + JSON.stringify(_result) + ";console.log('BROWSER_GAMEPERF_JSON',JSON.stringify(window.ganguBrowserPerf));")
func _download() -> void:
	if _result.is_empty() or not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("(()=>{let b=new Blob([JSON.stringify(window.ganguBrowserPerf,null,2)],{type:'application/json'});let u=URL.createObjectURL(b);let a=document.createElement('a');a.href=u;a.download='browser-gameperf.json';a.click();setTimeout(()=>URL.revokeObjectURL(u),1000);})()")
