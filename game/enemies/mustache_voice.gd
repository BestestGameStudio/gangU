class_name MustacheVoice
extends Node2D
## #480 (Colin, 2026-11-09: idle / combat / attacking / receiving-damage /
## dying sounds, played for the state each moustache warrior is actually
## in; "Both are good, randomize it" on the two auditioned voices). State
## vocal cues for the Mustache Warrior. Lives as the "MustacheVoice" child
## of game/enemies/enemy.tscn with one AudioStreamPlayer2D "Player" child.
## AUDIO ONLY: HP, damage, AI and the died() contract never depend on it.
##
## States -> cue families (assets/audio/sfx/mustache_warrior/<voice>/):
##   idle             - mutter / hum on a sparse random timer while the
##                      warrior is NOT engaged.
##   combat           - "spotted" bark exactly once on each engage rising
##                      edge, then sparse random taunt / warcry / laugh
##                      while engaged.
##   attacking        - grunt / exertion when the Sprite's one-shot attack
##                      or ranged action starts (chase-contact, cover
##                      charge and rock throws all route through
##                      Enemy.play_action).
##   receiving_damage - yelp on each health_changed drop (rate-limited).
##   dying            - groan from a DETACHED one-shot player, because the
##                      Enemy frees itself on death (same pattern as the
##                      #177 corpse).
##
## Voices (both approved by Colin): gravelly and excitable. Default: each
## warrior draws ONE voice at spawn (random per warrior, stable for its
## life) and picks random variants within it; PER_CUE_MIXING switches to
## drawing a voice per cue. The excitable combat_laugh is omitted
## (possible source clipping in the auditioned take, disclosed to Colin);
## the gravelly laugh stays.
##
## Engagement: a behavior with an `engaged` flag (guard/patrol) is
## authoritative; otherwise (plain chase / cover machine, which has no
## unaware state) a live player within ENGAGE_RADIUS counts as engaged.
## All timings, radii, the volume and the pitch wobble are PLACEHOLDER
## tuning (author defaults, human-open).

## Live-player distance that counts as combat for behaviors without an
## engaged flag (plain chase / cover machine).
const ENGAGE_RADIUS: float = 460.0
## Voice draw: false = one random voice per warrior (default); true =
## random voice per cue.
const PER_CUE_MIXING: bool = false
## #495 (Colin, 2026-11-09: "way too much moustache man sounds ... make
## their idle sound play less frequently and only when the character is
## close"): an unengaged warrior only mutters while the live player is
## within this distance, and the idle timer does not run while the player
## is farther away (no backlog burst on approach). Camera scale: viewport
## 1152x648, Camera2D zoom 1, so the screen is 576 px half-width and 324 px
## half-height; 300 px keeps idle on-screen in every direction.
## NOTE: a plain chase/cover warrior has no unaware state: it counts the
## player inside ENGAGE_RADIUS (460) as engaged (combat cues, not idle), so
## with this radius its idle is effectively silent (not enabled here). A
## guard/patrol warrior uses its own `engaged` flag (aggro 220), so while
## unaware with the player 220-300 px away it can idle rarely; its combat
## barks now follow that real awareness instead of 460 px. The user's "only
## when close" wins over idle variety. Combat, attack,
## hurt and death cues are untouched. PLACEHOLDER tuning, human-open (a var
## so tests can widen it to exercise the proximity gate).
var idle_hear_radius: float = 300.0
## Runtime trim on top of the -3 dBFS peak-normalized files.
const VOLUME_DB: float = -6.0
## Random pitch wobble so the single-variant cues do not repeat exactly.
const PITCH_WOBBLE: float = 0.06
## Minimum gap between hurt yelps (multi-hit spells tick fast).
const HURT_COOLDOWN: float = 0.25
## Cap on simultaneously playing warriors; idle / combat chatter is
## dropped past the cap (attack, hurt and death always play - they are
## short and event-driven).
static var MAX_SIMULTANEOUS: int = 4
static var _active: int = 0

## Ambient cue pacing, per warrior (seconds). Vars so tests can shrink
## them; PLACEHOLDER tuning.
var idle_min: float = 25.0
var idle_max: float = 45.0
var chatter_min: float = 6.0
var chatter_max: float = 12.0

const VOICES: Array[StringName] = [&"gravelly", &"excitable"]
## Sprite actions that read as "attacking".
const ATTACK_ACTIONS: Array[StringName] = [&"attack", &"ranged"]

## state -> alias list (variants); a voice missing an alias (the omitted
## excitable laugh) simply has one variant fewer.
const ALIASES: Dictionary = {
	&"idle": [&"idle_mutter", &"idle_hum"],
	&"combat": [&"combat_spotted", &"combat_taunt", &"combat_warcry", &"combat_laugh"],
	&"attacking": [&"attack_grunt", &"attack_exertion"],
	&"receiving_damage": [&"hurt_yelp"],
	&"dying": [&"death_groan"],
}
const _GRAVELLY: Dictionary = {
	&"idle_mutter": preload("res://assets/audio/sfx/mustache_warrior/gravelly/idle_mutter.ogg"),
	&"idle_hum": preload("res://assets/audio/sfx/mustache_warrior/gravelly/idle_hum.ogg"),
	&"combat_spotted": preload("res://assets/audio/sfx/mustache_warrior/gravelly/combat_spotted.ogg"),
	&"combat_taunt": preload("res://assets/audio/sfx/mustache_warrior/gravelly/combat_taunt.ogg"),
	&"combat_warcry": preload("res://assets/audio/sfx/mustache_warrior/gravelly/combat_warcry.ogg"),
	&"combat_laugh": preload("res://assets/audio/sfx/mustache_warrior/gravelly/combat_laugh.ogg"),
	&"attack_grunt": preload("res://assets/audio/sfx/mustache_warrior/gravelly/attack_grunt.ogg"),
	&"attack_exertion": preload("res://assets/audio/sfx/mustache_warrior/gravelly/attack_exertion.ogg"),
	&"hurt_yelp": preload("res://assets/audio/sfx/mustache_warrior/gravelly/hurt_yelp.ogg"),
	&"death_groan": preload("res://assets/audio/sfx/mustache_warrior/gravelly/death_groan.ogg"),
}
const _EXCITABLE: Dictionary = {
	&"idle_mutter": preload("res://assets/audio/sfx/mustache_warrior/excitable/idle_mutter.ogg"),
	&"idle_hum": preload("res://assets/audio/sfx/mustache_warrior/excitable/idle_hum.ogg"),
	&"combat_spotted": preload("res://assets/audio/sfx/mustache_warrior/excitable/combat_spotted.ogg"),
	&"combat_taunt": preload("res://assets/audio/sfx/mustache_warrior/excitable/combat_taunt.ogg"),
	&"combat_warcry": preload("res://assets/audio/sfx/mustache_warrior/excitable/combat_warcry.ogg"),
	# No excitable combat_laugh: possible source clipping in the take.
	&"attack_grunt": preload("res://assets/audio/sfx/mustache_warrior/excitable/attack_grunt.ogg"),
	&"attack_exertion": preload("res://assets/audio/sfx/mustache_warrior/excitable/attack_exertion.ogg"),
	&"hurt_yelp": preload("res://assets/audio/sfx/mustache_warrior/excitable/hurt_yelp.ogg"),
	&"death_groan": preload("res://assets/audio/sfx/mustache_warrior/excitable/death_groan.ogg"),
}
const _STREAMS: Dictionary = {&"gravelly": _GRAVELLY, &"excitable": _EXCITABLE}

## This warrior's drawn voice (stable unless PER_CUE_MIXING).
var voice: StringName
## Test/observability: last cue actually played.
var last_state: StringName = &""
var last_alias: StringName = &""
var cues_played: int = 0

var _enemy: Enemy
var _player: AudioStreamPlayer2D
var _rng := RandomNumberGenerator.new()
var _engaged := false
var _idle_timer: float = 0.0
var _chatter_timer: float = 0.0
var _hurt_cooldown: float = 0.0
var _last_action: StringName = &""
var _counted := false

func _ready() -> void:
	_enemy = get_parent() as Enemy
	_player = get_node_or_null("Player") as AudioStreamPlayer2D
	if _player == null:
		_player = AudioStreamPlayer2D.new()
		_player.name = "Player"
		add_child(_player)
	_player.volume_db = VOLUME_DB
	_player.finished.connect(_on_finished)
	_rng.randomize()
	voice = VOICES[_rng.randi() % VOICES.size()]
	_idle_timer = _rng.randf_range(idle_min, idle_max)
	_chatter_timer = _rng.randf_range(chatter_min, chatter_max)
	if _enemy != null:
		_enemy.health_changed.connect(_on_health_changed)
		_enemy.died.connect(_on_died)
	add_to_group(&"mustache_voices")

func _exit_tree() -> void:
	if _counted:
		_active = maxi(_active - 1, 0)
		_counted = false

func _process(delta: float) -> void:
	if _enemy == null or not is_instance_valid(_enemy) or _enemy.hp <= 0:
		return
	# Frozen warriors keep their voices frozen too (#305 symmetry).
	if _enemy.freeze.is_frozen():
		return
	_hurt_cooldown = maxf(0.0, _hurt_cooldown - delta)
	# Attack cues follow the Sprite's one-shot actions (the visual swing
	# and the rock throw both start one); each fresh action start = 1 cue.
	var action: StringName = &""
	if _enemy.sprite != null:
		action = _enemy.sprite.current_action()
	if action != _last_action and ATTACK_ACTIONS.has(action):
		_play_cue(&"attacking")
	_last_action = action
	# Engagement rising edge: one spotted bark per engagement.
	var now_engaged := _is_engaged()
	if now_engaged and not _engaged:
		_play_cue(&"combat", &"combat_spotted")
		_chatter_timer = _rng.randf_range(chatter_min, chatter_max)
	_engaged = now_engaged
	if _engaged:
		_chatter_timer -= delta
		if _chatter_timer <= 0.0:
			_chatter_timer = _rng.randf_range(chatter_min, chatter_max)
			_play_ambient(&"combat")
	else:
		# #495: the idle timer only runs while the player is close.
		if _player_within(idle_hear_radius):
			_idle_timer -= delta
		if _idle_timer <= 0.0:
			_idle_timer = _rng.randf_range(idle_min, idle_max)
			_play_ambient(&"idle")

func _player_within(radius: float) -> bool:
	var p: Player = _enemy._player
	if p != null and is_instance_valid(p) and p.hp > 0:
		return _enemy.global_position.distance_to(p.global_position) <= radius
	return false

func _is_engaged() -> bool:
	var b: RefCounted = _enemy._behavior
	if b != null and "engaged" in b:
		return b.get(&"engaged") # guard/patrol: the behavior's own flag is authoritative
	return _player_within(ENGAGE_RADIUS)

func _cue_voice() -> StringName:
	if PER_CUE_MIXING:
		return VOICES[_rng.randi() % VOICES.size()]
	return voice

## Ambient cues (idle mutter, combat chatter) respect the concurrency cap.
func _play_ambient(state: StringName) -> void:
	if _active >= MAX_SIMULTANEOUS and not _counted:
		return
	_play_cue(state)

func _play_cue(state: StringName, forced_alias: StringName = &"") -> void:
	var v := _cue_voice()
	var table: Dictionary = _STREAMS[v]
	var alias := forced_alias
	if alias == &"":
		var options: Array = []
		for a: StringName in ALIASES[state]:
			# The spotted bark is reserved for the engage rising edge
			# (forced); it is never random chatter.
			if state == &"combat" and a == &"combat_spotted":
				continue
			if table.has(a):
				options.append(a)
		if options.is_empty():
			return
		alias = options[_rng.randi() % options.size()]
	_start(_player, table[alias], true)
	last_state = state
	last_alias = alias
	cues_played += 1

func _start(p: AudioStreamPlayer2D, stream: AudioStream, counted: bool) -> void:
	p.stream = stream
	p.pitch_scale = 1.0 + _rng.randf_range(-PITCH_WOBBLE, PITCH_WOBBLE)
	if counted and not _counted:
		_active += 1
		_counted = true
	p.play()

func _on_health_changed(current: int, _max_hp: int) -> void:
	# Emitted only from apply_damage (a reduction); hp 0 is the death path.
	if current <= 0 or _hurt_cooldown > 0.0:
		return
	_hurt_cooldown = HURT_COOLDOWN
	_play_cue(&"receiving_damage")

func _on_died() -> void:
	# The Enemy queue_frees on death, so the groan plays from a detached
	# one-shot parented to the area (the #177 corpse pattern).
	var p := AudioStreamPlayer2D.new()
	p.stream = _STREAMS[_cue_voice()][&"death_groan"]
	p.volume_db = VOLUME_DB
	p.pitch_scale = 1.0 + _rng.randf_range(-PITCH_WOBBLE, PITCH_WOBBLE)
	p.global_position = _enemy.global_position
	p.finished.connect(p.queue_free)
	var area: Node = _enemy.get_parent()
	if area != null:
		area.call_deferred("add_child", p)
		p.call_deferred("play")
	last_state = &"dying"
	last_alias = &"death_groan"
	cues_played += 1

func _on_finished() -> void:
	if _counted:
		_active = maxi(_active - 1, 0)
		_counted = false
