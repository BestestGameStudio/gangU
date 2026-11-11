class_name FishyAudio
extends Node2D
## #594/#595: observes real Fishy state, never drives AI or gameplay timers.
const WHISTLE := preload("res://assets/audio/sfx/fishy_whistle_b2.ogg")
const IDLE_RADIUS := 300.0
var _whistle: AudioStreamPlayer2D
var _idle_left := 0.0
var _last_state := -1
var whistle_count := 0

func _ready() -> void:
	add_to_group(&"fishy_audio")
	_whistle = _voice(WHISTLE)
	_idle_left = randf_range(30.0, 50.0)

func _voice(cue: AudioStream) -> AudioStreamPlayer2D:
	var voice := AudioStreamPlayer2D.new()
	voice.stream = cue
	voice.max_polyphony = 1
	voice.max_distance = 900.0
	voice.attenuation = 1.0
	add_child(voice)
	return voice

func _physics_process(delta: float) -> void:
	step(delta)

func step(delta: float) -> void:
	var enemy := get_parent() as Enemy
	if enemy == null:
		return
	var behavior := enemy._behavior as EnemyBehaviorFishy
	var target := enemy._player
	if behavior == null or enemy.hp <= 0 or enemy.freeze.is_frozen() or not is_instance_valid(target) or target.hp <= 0:
		_silence()
		_last_state = -1
		return
	var state := behavior.state
	var idle := state == EnemyBehaviorFishy.State.APPROACH and not behavior.engaged and enemy.global_position.distance_to(target.global_position) <= IDLE_RADIUS
	if not idle:
		if _whistle.playing:
			_whistle.stop()
			_idle_left = randf_range(30.0, 50.0)
	else:
		_idle_left -= delta
		if _idle_left <= 0.0 and not _any_whistle():
			_whistle.play()
			whistle_count += 1
			_idle_left = WHISTLE.get_length() + randf_range(30.0, 50.0)
	_last_state = state

func _any_whistle() -> bool:
	for node in get_tree().get_nodes_in_group(&"fishy_audio"):
		var audio := node as FishyAudio
		if audio != null and audio._whistle.playing:
			return true
	return false

func _silence() -> void:
	_whistle.stop()

func _exit_tree() -> void:
	if _whistle != null:
		_silence()
