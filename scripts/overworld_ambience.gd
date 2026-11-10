class_name OverworldAmbience
extends AudioStreamPlayer
## #487: overworld music (Colin 2026-11-09: very soft piano, kinda Minecraft,
## keep the volume low; supersedes the #477 nature ambience). One quiet
## original piano piece, no ambience bed: no wind, water or bush rustling.
##
## Mounted in overworld.tscn, so it starts when the overworld loads and is
## freed with it: silent in the hub and in every dungeon, no change to Main.
## (The node and class keep their #477 names to keep the scene diff small.)
##
## The track is already quiet by design (peak -15.1 dBFS, RMS about -37 dBFS)
## and ends in a 4 s fade to silence, so the loop restarts with a natural
## pause. The level is kept as approved: no gain trim and no loudness match
## to the other music tracks.

const TRACK: AudioStream = preload("res://assets/audio/music/overworld_soft_piano_loop.ogg")

func _ready() -> void:
	var s := TRACK
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	stream = s
	volume_db = 0.0
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps going under menus/panels
	play()
