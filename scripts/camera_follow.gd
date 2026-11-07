extends Camera2D
class_name FollowCamera
## Follow camera: keeps the player in view (user-reported usability fix -
## the player could previously walk out of the fixed viewport).
## Lives in main.tscn (not player.tscn) to stay independent of the spell
## system's player.tscn changes (#3) and future scene-flow work (#7/#9).

@export var target_path: NodePath = ^"../Player"

@onready var target: Node2D = get_node_or_null(target_path)

func _ready() -> void:
	make_current()
	if target:
		global_position = target.global_position

func _process(_delta: float) -> void:
	if target:
		global_position = target.global_position
