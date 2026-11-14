class_name DesertStatueAudio
extends Node2D
## Approved one-shots for the Sunbound Sanctum statues. Audio only: the arena
## calls these at real events, nothing here drives gameplay or timers.
const SPEAR: AudioStream = preload("res://assets/audio/sfx/statue_spear_throw_v2.ogg")
const DAMAGE: AudioStream = preload("res://assets/audio/sfx/statue_damage_v6a.ogg")
const DEATH: AudioStream = preload("res://assets/audio/sfx/statue_death_v7c.ogg")
const POSSESS: AudioStream = preload("res://assets/audio/sfx/statue_possession_v8d.ogg")
## Mixed to sit with the other effects (hurt/death cues play near 0 dB):
## Colin found the first pass (-8/-6 dB) very quiet by comparison.
const VOLUME_DB := -2.0
const DEATH_VOLUME_DB := 0.0
const MAX_DISTANCE := 1400.0

var _spear: AudioStreamPlayer2D
var _damage: AudioStreamPlayer2D
var _death: AudioStreamPlayer2D
var _possess: AudioStreamPlayer2D
var spear_count := 0
var damage_count := 0
var death_count := 0
var possess_count := 0

func _ready() -> void:
	_spear = _voice(SPEAR, 2, VOLUME_DB)
	_damage = _voice(DAMAGE, 3, VOLUME_DB)
	_death = _voice(DEATH, 2, DEATH_VOLUME_DB)
	_possess = _voice(POSSESS, 1, VOLUME_DB)

func _voice(cue: AudioStream, polyphony: int, volume_db: float) -> AudioStreamPlayer2D:
	var voice := AudioStreamPlayer2D.new()
	voice.stream = cue
	voice.max_polyphony = polyphony
	voice.max_distance = MAX_DISTANCE
	voice.attenuation = 1.0
	voice.volume_db = volume_db
	add_child(voice)
	return voice

func spear(at: Vector2) -> void:
	_play(_spear, at)
	spear_count += 1

func damage(at: Vector2) -> void:
	_play(_damage, at)
	damage_count += 1

func death(at: Vector2) -> void:
	_play(_death, at)
	death_count += 1

func possess(at: Vector2) -> void:
	_play(_possess, at)
	possess_count += 1

func _play(voice: AudioStreamPlayer2D, at: Vector2) -> void:
	if not is_inside_tree():
		return
	voice.global_position = at
	voice.pitch_scale = randf_range(0.96, 1.04)
	voice.play()
