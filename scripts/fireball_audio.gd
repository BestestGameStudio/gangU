class_name FireballAudio
extends RefCounted
## #584: approved one-shots. Audio only, never changes hit/cast bookkeeping.
const CAST: AudioStream = preload("res://assets/audio/sfx/fireball_cast_soft.ogg")
const IMPACT: AudioStream = preload("res://assets/audio/sfx/fireball_impact.ogg")
## Both cues were too loud in the deployed mix. Preserve the approved streams.
const VOLUME_DB: float = -10.0
const IDS: Array[StringName] = [
	&"fire_ball", &"fire_ball_split", &"fire_ball_split_heavy", &"fire_ball_split_wide",
	&"fire_ball_beam", &"fire_ball_beam_heavy", &"fire_ball_beam_homing",
	&"fire_ball_beam_long", &"fire_ball_beam_piercing",
]

static func supports(spell: Spell) -> bool:
	return spell != null and IDS.has(spell.id())

static func cast(at: Node, spell: Spell) -> AudioStreamPlayer:
	return _play(at, spell, CAST, &"FireballCastAudio")

static func impact(at: Node, spell: Spell) -> AudioStreamPlayer:
	return _play(at, spell, IMPACT, &"FireballImpactAudio")

static func _play(at: Node, spell: Spell, stream: AudioStream, cue: StringName) -> AudioStreamPlayer:
	if not supports(spell) or not is_instance_valid(at) or not at.is_inside_tree():
		return null
	# A scene-owned voice survives projectile deletion, but not leaving the scene.
	var host := at.get_tree().current_scene
	if host == null:
		host = at.get_tree().root
	var player := AudioStreamPlayer.new()
	player.name = cue
	player.stream = stream
	player.bus = &"Master"
	player.volume_db = VOLUME_DB # local cue gain only; leave Master and other sounds alone
	player.pitch_scale = 1.0
	player.add_to_group(&"fireball_audio")
	host.add_child(player)
	player.finished.connect(player.queue_free, CONNECT_ONE_SHOT)
	player.play()
	return player
