class_name PlayerHurtAudio
extends AudioStreamPlayer
## #596: presentation only. Player calls this only for nonlethal HP loss.
const CUE := preload("res://assets/audio/sfx/player_hurt_oof_v1.ogg")
const COOLDOWN := 0.15
var _remaining := 0.0
var play_count := 0

func _ready() -> void:
	stream = CUE
	max_polyphony = 1

func _process(delta: float) -> void:
	_remaining = maxf(0.0, _remaining - delta)

func cue() -> void:
	if _remaining > 0.0:
		return
	_remaining = COOLDOWN
	play_count += 1
	play()

func silence() -> void:
	stop()
