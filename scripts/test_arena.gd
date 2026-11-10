extends Node2D
## #5 TEST ARENA - evidence scene only. Spawns TEST projectiles on cast (stand-in
## for #3/#4) and shows a debug label in place of the #11 HUD. Removed/replaced
## when real spells (#3) and HUD (#11) land; no production dependencies on it.
## GANGU_AUTOTEST=1 env: auto-casts and prints diagnostics (evidence capture only).

const TestProjectileScene := preload("res://scenes/test_projectile.tscn")

@onready var debug: Label = $DebugLabel
var _status := ""
var _autotest := false
var _cast_timer := 0.0
var _cast_count := 0

func _ready() -> void:
	_autotest = OS.get_environment("GANGU_AUTOTEST") == "1"
	var p = Player.find(get_tree())
	print("[arena] player=", p, " has_hp=", p != null and p.get("hp") != null)
	p.health_changed.connect(func(c, m): _status = "health_changed(" + str(c) + "/" + str(m) + ") from apply_damage")
	p.died.connect(func(): _status = "PLAYER died() EMITTED"; print("[arena] PLAYER died() emitted"))
	for e in get_tree().get_nodes_in_group("enemies"):
		e.died.connect(func(): _status = "enemy died() EMITTED"; print("[arena] enemy died() emitted"))
	if _autotest:
		get_tree().create_timer(21.0).timeout.connect(func(): get_tree().quit())

func _cast() -> void:
	var p = Player.find(get_tree())
	if p == null or p.get("hp") <= 0:
		return
	var proj := TestProjectileScene.instantiate()
	var dir: Vector2 = Vector2.UP if _autotest else p.global_position.direction_to(get_global_mouse_position())
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	proj.direction = dir
	proj.global_position = p.global_position + dir * 28.0
	add_child(proj)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cast"):
		_cast()

var _print_timer := 0.0
func _process(delta: float) -> void:
	var p = Player.find(get_tree())
	var enemies := get_tree().get_nodes_in_group("enemies")
	debug.text = "hp " + str(p.get("hp")) + "/" + str(p.get("max_hp")) + " | enemies " + str(enemies.size()) + " | " + _status
	if _autotest:
		_cast_timer += delta
		if _cast_timer >= 1.0 and _cast_count < 4:
			_cast_timer = 0.0
			_cast_count += 1
			_cast()
			print("[arena] auto-cast ", _cast_count)
		_print_timer += delta
		if _print_timer >= 2.0:
			_print_timer = 0.0
			var pos := []
			for e in enemies:
				pos.append(str(e.global_position.round()))
			print("[arena] t hp=", p.get("hp"), " enemies=", enemies.size(), " pos=", pos)
