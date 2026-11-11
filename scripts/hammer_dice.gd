class_name HammerDice
extends Node2D
## #370 Stone Hammer Rhythm Signature: the die rolled every
## spell.hammer_dice_every consecutive hits. It tumbles above the player
## (random faces) for ROLL_TIME, settles on `face`, then drops the reward
## rolled from that face's table (currency for now) at the player's feet and
## fades out. The face and reward are decided up front by StoneHammerState.

signal settled(face: int)

const ROLL_TIME := 0.6
const SHOW_TIME := 1.0
const SIZE := 22.0
const OFFSET := Vector2(0.0, -70.0)
const REWARD_DROP := preload("res://scenes/reward_drop.tscn")

var face := 1
var entry: RewardEntry
var drop_parent: Node
var drop: RewardDrop = null
## The entry this die dropped (stays readable after the drop is collected).
var dropped_entry: RewardEntry = null

var _t := 0.0
var _shown := 1
var _settled := false

static func spawn(p_owner: Node2D, p_face: int, p_entry: RewardEntry, p_drop_parent: Node) -> HammerDice:
	var d := HammerDice.new()
	d.name = "HammerDice"
	d.face = clampi(p_face, 1, 6)
	d.entry = p_entry
	d.drop_parent = p_drop_parent
	p_owner.add_child(d)
	d.global_position = p_owner.global_position + OFFSET
	d.global_rotation = 0.0
	return d

func _ready() -> void:
	add_to_group(&"hammer_dice")
	z_index = 5
	_shown = randi_range(1, 6)

func is_settled() -> bool:
	return _settled

func shown_face() -> int:
	return _shown

func _process(delta: float) -> void:
	# Stay upright even though the player node rotates to face the cursor.
	var owner2d := get_parent() as Node2D
	if owner2d != null:
		global_position = owner2d.global_position + OFFSET
	global_rotation = 0.0
	_t += delta
	if not _settled:
		if int(_t / 0.07) != int((_t - delta) / 0.07):
			_shown = (_shown % 6) + 1 if randf() < 0.5 else randi_range(1, 6)
		if _t >= ROLL_TIME:
			_settle()
	elif _t >= ROLL_TIME + SHOW_TIME:
		queue_free()
	queue_redraw()

func _settle() -> void:
	_settled = true
	_shown = face
	settled.emit(face)
	if entry == null:
		return
	var parent := drop_parent if drop_parent != null and is_instance_valid(drop_parent) else get_tree().current_scene
	drop = REWARD_DROP.instantiate()
	drop.setup(entry)
	dropped_entry = entry
	var owner2d := get_parent() as Node2D
	var at := owner2d.global_position if owner2d != null else global_position
	drop.global_position = at + Vector2(randf_range(-24.0, 24.0), 18.0)
	parent.call_deferred(&"add_child", drop)

const PIPS := {
	1: [Vector2(0, 0)],
	2: [Vector2(-1, -1), Vector2(1, 1)],
	3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
	4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
	5: [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)],
	6: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)],
}

func _draw() -> void:
	var fade := 1.0
	if _settled:
		fade = clampf(1.0 - (_t - ROLL_TIME - SHOW_TIME * 0.6) / (SHOW_TIME * 0.4), 0.0, 1.0)
	var tumble := 0.0 if _settled else sin(_t * 30.0) * 0.35
	var pop := 1.0 + (0.25 * maxf(1.0 - (_t - ROLL_TIME) / 0.2, 0.0) if _settled else 0.0)
	draw_set_transform(Vector2.ZERO, tumble, Vector2.ONE * pop)
	var half := SIZE * 0.5
	var rect := Rect2(-half, -half, SIZE, SIZE)
	draw_rect(rect.grow(2.0), Color(0.1, 0.08, 0.06, fade), true)
	draw_rect(rect, Color(0.97, 0.95, 0.9, fade), true)
	var pip := Color(0.15, 0.12, 0.1, fade) if _shown != 6 or not _settled else Color(0.8, 0.15, 0.1, fade)
	for p: Vector2 in PIPS[_shown]:
		draw_circle(p * SIZE * 0.27, 2.4, pip)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _settled and entry != null and entry.kind == RewardEntry.Kind.CURRENCY:
		var font := ThemeDB.fallback_font
		var txt := "+%dc" % entry.currency_amount
		draw_string(font, Vector2(-20.0, -half - 6.0), txt, HORIZONTAL_ALIGNMENT_CENTER, 40.0, 14, Color(1.0, 0.85, 0.2, fade))
