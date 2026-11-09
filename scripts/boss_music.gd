class_name BossMusic
extends AudioStreamPlayer
## #359: boss theme for RED dungeon bosses. Main mounts ONE of these and calls
## start() when a boss spawns in a RED-entered dungeon (main._area_is_red), then
## fade_out() when the objective clears and stop() on every area swap.
## One of TRACKS is picked at random per fight and loops until stopped.
##
## Volume (Mitravasu: "really loud, dampen them quite a bit"): the source files
## were mastered hot (mean -4.6 / -7.3 dB, peaks at 0 dBFS). The committed .ogg
## files have the gain baked down (-15 dB boss1, -17 dB boss2, both now ~-21.5 dB
## mean), and MUSIC_VOLUME_DB is a further runtime trim to tweak by ear.

const TRACKS: Array[AudioStream] = [
	preload("res://assets/audio/music/boss1.ogg"),
	preload("res://assets/audio/music/boss2.ogg"),
]
## Extra runtime attenuation on top of the baked-in gain. Tweak here.
const MUSIC_VOLUME_DB := -6.0
## Seconds to fade the theme out after the boss dies.
const FADE_OUT_SEC := 1.5
const SILENT_DB := -60.0

var _fade: Tween = null

func _ready() -> void:
	volume_db = MUSIC_VOLUME_DB
	# Keep playing while the tree is paused (menus / panels).
	process_mode = Node.PROCESS_MODE_ALWAYS

## Start a random boss theme (looping). No-op if a theme is already playing,
## so a second boss_spawned in the same fight does not restart the music.
func start(rng: RandomNumberGenerator = null) -> void:
	if playing and _fade == null:
		return
	_kill_fade()
	var i := rng.randi_range(0, TRACKS.size() - 1) if rng else randi_range(0, TRACKS.size() - 1)
	var s := TRACKS[i]
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	stream = s
	volume_db = MUSIC_VOLUME_DB
	play()

## Fade the current theme out, then stop (boss defeated).
func fade_out() -> void:
	if not playing or _fade != null:
		return
	_fade = create_tween()
	_fade.tween_property(self, "volume_db", SILENT_DB, FADE_OUT_SEC)
	_fade.tween_callback(stop_music)

## Stop immediately (area swap, leaving the dungeon).
func stop_music() -> void:
	_kill_fade()
	stop()
	volume_db = MUSIC_VOLUME_DB

func _kill_fade() -> void:
	if _fade != null:
		_fade.kill()
		_fade = null
