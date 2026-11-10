class_name DungeonMusic
extends AudioStreamPlayer
## #471: default dungeon music (Colin 2026-11-09: "Make that the default dungeon
## music"). One original retro-synth battle loop (assets/audio/music/SOURCE.md).
## Main mounts ONE of these. It plays in dungeon areas (Main._swap) and is
## silent in the hub and overworld. While a boss theme plays (#359) it yields
## (stream_paused) and fades back in when the boss theme ends.
##
## Author defaults, not owner decisions (the ticket leaves them open): which
## areas count, the volume trim, a fresh start on each dungeon entry, and the
## yield-to-boss behaviour.

const TRACK: AudioStream = preload("res://assets/audio/music/dungeon_battle_loop.ogg")
## Runtime attenuation. The source loop measures mean -14.9 dB; this puts it
## near the boss themes' effective level (committed -21.5 dB mean, then -6).
const MUSIC_VOLUME_DB := -13.0
const FADE_IN_SEC := 1.5
const SILENT_DB := -60.0

var _fade: Tween = null
## AudioStreamPlayer.playing reads false while stream_paused, so the yield is
## tracked here.
var _yielded := false

func _ready() -> void:
	volume_db = MUSIC_VOLUME_DB
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps playing under menus/panels

## Dungeon areas are the DungeonA..E / Maze / Generated scenes (root name
## starts with "Dungeon"); Hub and Overworld are not.
static func is_dungeon_area(area: Node) -> bool:
	return area != null and String(area.name).begins_with("Dungeon")

## Start the loop from the top. Called on every dungeon entry.
func start() -> void:
	_kill_fade()
	var s := TRACK
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	stream = s
	stream_paused = false
	_yielded = false
	volume_db = MUSIC_VOLUME_DB
	play()

## Stop immediately (hub/overworld, area swap).
func stop_music() -> void:
	_kill_fade()
	stop()
	stream_paused = false
	_yielded = false
	volume_db = MUSIC_VOLUME_DB

## A boss theme started: hold the loop where it is.
func yield_to_boss() -> void:
	if not playing:
		return
	_kill_fade()
	_yielded = true
	stream_paused = true

## The boss theme is done: continue the loop, fading back in.
func resume_after_boss() -> void:
	if not _yielded:
		return
	_kill_fade()
	_yielded = false
	volume_db = SILENT_DB
	stream_paused = false
	_fade = create_tween()
	_fade.tween_property(self, "volume_db", MUSIC_VOLUME_DB, FADE_IN_SEC)
	_fade.tween_callback(_kill_fade)

func _kill_fade() -> void:
	if _fade != null:
		_fade.kill()
		_fade = null
