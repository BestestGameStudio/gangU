class_name MusicDirector
extends Node
## #512: ONE music director for the whole run, merging the former BossMusic
## (#359), DungeonMusic (#471) and OverworldAmbience (#477/#487) players.
## Main mounts ONE of these and AreaLoader tells it about area swaps, boss
## spawns and objective completions; freed with Main on a death restart, so
## no theme leaks into the reloaded run. Playback behavior is identical to
## the three separate players.
##
## Boss theme (#359): a random track per fight, looping, started when a boss
## spawns in a RED-entered dungeon or in the Head / Beast arenas, faded out
## when the objective clears, stopped on every area swap. Volume (#359:
## "really loud, so dampen them quite a bit"): the source files measure mean
## -7.3 / -4.6 dB with 0 dBFS peaks. The committed .ogg files have the gain
## baked down (-15 dB boss1, -17 dB boss2; now -21.7 / -21.5 dB mean), and
## BOSS_VOLUME_DB is a further runtime trim. See assets/audio/music/SOURCE.md.
##
## Dungeon loop (#471): one original retro-synth battle loop. Plays in
## dungeon areas, silent in the hub and overworld, a fresh start on every
## dungeon entry; while a boss theme plays it yields (stream_paused) and
## fades back in when the theme ends.
##
## Overworld piano (#487, supersedes the #477 nature ambience): one quiet
## original piano piece, no ambience bed. It was mounted in overworld.tscn;
## the director now starts it when the overworld scene becomes the current
## area and stops it on leaving. The track is already quiet by design (peak
## -15.1 dBFS, RMS about -37 dBFS) and ends in a 4 s fade to silence, so the
## loop restarts with a natural pause; the level is kept as approved (0 dB,
## no gain trim and no loudness match to the other tracks).

const BOSS_TRACKS: Array[AudioStream] = [
	preload("res://assets/audio/music/boss1.ogg"),
	preload("res://assets/audio/music/boss2.ogg"),
]
## Extra runtime attenuation on top of the baked-in gain. Tweak here.
const BOSS_VOLUME_DB := -6.0
## Seconds to fade the theme out after the boss dies.
const BOSS_FADE_OUT_SEC := 1.5

const DUNGEON_TRACK: AudioStream = preload("res://assets/audio/music/dungeon_battle_loop.ogg")
## Runtime attenuation. The source loop measures mean -14.9 dB; this puts it
## near the boss themes' effective level (committed -21.5 dB mean, then -6).
const DUNGEON_VOLUME_DB := -13.0
const DUNGEON_FADE_IN_SEC := 1.5

const OVERWORLD_TRACK: AudioStream = preload("res://assets/audio/music/overworld_soft_piano_loop.ogg")
## The scene whose mount plays the piano (the #477 home was overworld.tscn,
## so this is a scene path, not an area-name check).
const OVERWORLD_SCENE := "res://scenes/overworld.tscn"

const SILENT_DB := -60.0

## The three players, created in _ready; public so harnesses can inspect
## playback state (CI has no audio device).
var boss: AudioStreamPlayer = null
var dungeon: AudioStreamPlayer = null
var overworld: AudioStreamPlayer = null

var _boss_fade: Tween = null
var _dungeon_fade: Tween = null
## AudioStreamPlayer.playing reads false while stream_paused, so the dungeon
## loop's yield to the boss theme is tracked here.
var _dungeon_yielded := false

func _ready() -> void:
	boss = _make_player("Boss", BOSS_VOLUME_DB)
	dungeon = _make_player("Dungeon", DUNGEON_VOLUME_DB)
	overworld = _make_player("Overworld", 0.0)

func _make_player(player_name: String, volume: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = player_name
	p.volume_db = volume
	# Keep playing while the tree is paused (menus / panels).
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p

## Dungeon areas are the DungeonA..E / Maze / Generated scenes (root name
## starts with "Dungeon"); Hub and Overworld are not.
static func is_dungeon_area(area: Node) -> bool:
	return area != null and String(area.name).begins_with("Dungeon")

## AreaLoader's _swap: the boss theme never outlives its dungeon; the
## dungeon loop restarts on a dungeon entry and stops elsewhere; the
## overworld piano plays only while the overworld scene is mounted.
func on_area_swapped(area: Node) -> void:
	stop_boss()
	if is_dungeon_area(area):
		start_dungeon()
	else:
		stop_dungeon()
	if area != null and area.scene_file_path == OVERWORLD_SCENE:
		start_overworld()
	else:
		stop_overworld()

## AreaLoader's _on_boss_spawned: play the theme for RED-entered dungeon
## bosses and the boss arenas; the dungeon loop yields to it.
func on_boss_spawned(play_theme: bool) -> void:
	if not play_theme:
		return
	start_boss()
	yield_dungeon_to_boss()

## AreaLoader's _on_objective_completed: boss down, the theme fades out and
## the dungeon loop fades back in.
func on_objective_completed() -> void:
	fade_out_boss()
	resume_dungeon_after_boss()

## Start a random boss theme (looping). No-op if a theme is already playing,
## so a second boss_spawned in the same fight does not restart the music.
func start_boss(rng: RandomNumberGenerator = null) -> void:
	if boss.playing and _boss_fade == null:
		return
	_kill_boss_fade()
	var i := rng.randi_range(0, BOSS_TRACKS.size() - 1) if rng else randi_range(0, BOSS_TRACKS.size() - 1)
	var s := BOSS_TRACKS[i]
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	boss.stream = s
	boss.volume_db = BOSS_VOLUME_DB
	boss.play()

## Fade the current theme out, then stop (boss defeated).
func fade_out_boss() -> void:
	if not boss.playing or _boss_fade != null:
		return
	_boss_fade = create_tween()
	_boss_fade.tween_property(boss, "volume_db", SILENT_DB, BOSS_FADE_OUT_SEC)
	_boss_fade.tween_callback(stop_boss)

## Stop immediately (area swap, leaving the dungeon).
func stop_boss() -> void:
	_kill_boss_fade()
	boss.stop()
	boss.volume_db = BOSS_VOLUME_DB

func _kill_boss_fade() -> void:
	if _boss_fade != null:
		_boss_fade.kill()
		_boss_fade = null

## Start the dungeon loop from the top. Called on every dungeon entry.
func start_dungeon() -> void:
	_kill_dungeon_fade()
	var s := DUNGEON_TRACK
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	dungeon.stream = s
	dungeon.stream_paused = false
	_dungeon_yielded = false
	dungeon.volume_db = DUNGEON_VOLUME_DB
	dungeon.play()

## Stop immediately (hub/overworld, area swap).
func stop_dungeon() -> void:
	_kill_dungeon_fade()
	dungeon.stop()
	dungeon.stream_paused = false
	_dungeon_yielded = false
	dungeon.volume_db = DUNGEON_VOLUME_DB

## A boss theme started: hold the loop where it is.
func yield_dungeon_to_boss() -> void:
	if not dungeon.playing:
		return
	_kill_dungeon_fade()
	_dungeon_yielded = true
	dungeon.stream_paused = true

## The boss theme is done: continue the loop, fading back in.
func resume_dungeon_after_boss() -> void:
	if not _dungeon_yielded:
		return
	_kill_dungeon_fade()
	_dungeon_yielded = false
	dungeon.volume_db = SILENT_DB
	dungeon.stream_paused = false
	_dungeon_fade = create_tween()
	_dungeon_fade.tween_property(dungeon, "volume_db", DUNGEON_VOLUME_DB, DUNGEON_FADE_IN_SEC)
	_dungeon_fade.tween_callback(_kill_dungeon_fade)

func _kill_dungeon_fade() -> void:
	if _dungeon_fade != null:
		_dungeon_fade.kill()
		_dungeon_fade = null

## Start the overworld piano from the top (overworld entered). No gain trim:
## the track is quiet by design.
func start_overworld() -> void:
	var s := OVERWORLD_TRACK
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	overworld.stream = s
	overworld.volume_db = 0.0
	overworld.play()

## Stop immediately (leaving the overworld).
func stop_overworld() -> void:
	overworld.stop()
	overworld.volume_db = 0.0
