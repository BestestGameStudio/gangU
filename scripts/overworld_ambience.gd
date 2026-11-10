class_name OverworldAmbience
extends AudioStreamPlayer
## #477: overworld ambience (Colin 2026-11-09: add the approved nature loop as
## the overworld sound). Mostly silence, sparse quiet birds and brief leaf
## rustles. No music, no wind bed, no water or rain, no continuous noise.
##
## Mounted in overworld.tscn, so it starts when the overworld loads and is
## freed with it: silent in the hub and in every dungeon, no change to Main.
##
## The loop is already very quiet by design (peak about -13 dBFS, RMS about
## -44.6 dBFS). The level is kept as approved: no gain trim and no loudness
## match to the music tracks.

const TRACK: AudioStream = preload("res://assets/audio/music/overworld_ambience_loop.ogg")

func _ready() -> void:
	var s := TRACK
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	stream = s
	volume_db = 0.0
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps going under menus/panels
	play()
