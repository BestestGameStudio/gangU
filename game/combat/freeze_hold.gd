class_name FreezeHold
extends RefCounted
## #305 Signature freeze state of one mover. FreezeBubble claims are
## reference-counted so overlapping bubbles freeze and release
## independently; the mover skips its clocks while is_frozen().

var count := 0

## One claim (frozen = true) or release. `sprite` pauses on the first claim
## and resumes on the last release: pause() alone does not hold an
## AnimatedSprite2D (its own processing replays it), so that stops too.
func apply(frozen: bool, sprite: AnimatedSprite2D = null) -> void:
	var was := count
	count = maxi(count + (1 if frozen else -1), 0)
	if sprite == null or not is_instance_valid(sprite):
		return
	if count > 0 and was == 0:
		sprite.pause()
		sprite.process_mode = Node.PROCESS_MODE_DISABLED
	elif count == 0 and was > 0:
		sprite.process_mode = Node.PROCESS_MODE_INHERIT
		sprite.play()

func is_frozen() -> bool:
	return count > 0
