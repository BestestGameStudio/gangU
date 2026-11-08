extends Node2D
## #266 debug scene: harness/evidence only, not reachable from the game.
## GANGU_MODE=map (default): a generated enclosed_forked map in the
##   highlands palette (GANGU_PALETTE=none for the built-in tiles), seed from
##   GANGU_SEED (default 1).
## GANGU_MODE=block: a hand-placed strip of chasm / cliff / pine_forest with
##   three players walking (and one dashing, one being pushed) into them.
## GANGU_AUTOTEST=1 quits after a moment.
## Each option can also be passed as a user arg: `-- mode=block seed=3`.

const HIGHLANDS: TerrainPalette = preload("res://resources/terrain_palettes/highlands.tres")
const LAYOUT: TerrainLayout = preload("res://resources/terrain_layouts/enclosed_forked.tres")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

@onready var map: TerrainMap = $TerrainMap

var _players: Array[Player] = []

func _opt(key: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(key + "="):
			return arg.substr(key.length() + 1)
	return OS.get_environment("GANGU_" + key.to_upper())

func _ready() -> void:
	if _opt("mode") == "block":
		_block_scene()
	else:
		_map_scene()
	if _opt("autotest") == "1":
		get_tree().create_timer(3.0).timeout.connect(func(): get_tree().quit())

func _map_scene() -> void:
	var map_seed := 1
	var env_seed := _opt("seed")
	if env_seed.is_valid_int():
		map_seed = env_seed.to_int()
	if _opt("palette") != "none":
		map.palette = HIGHLANDS
	TerrainGen.generate(map, map_seed, TerrainGen.DEFAULT_SIZE, LAYOUT)
	print("[266] map seed ", map_seed, " palette ", "highlands" if map.palette != null else "built-in")

func _block_scene() -> void:
	map.palette = HIGHLANDS
	var cs := map.cell_size
	var cells := {}
	for y in range(0, 24):
		for x in range(0, 43):
			cells[Vector2i(x, y)] = &"meadow" if x < 12 else &"scree"
	# Wall column per 4-row band: chasm, cliff, pine_forest, mountain, ...
	var bands: Array[StringName] = [&"chasm", &"cliff", &"pine_forest", &"mountain", &"chasm", &"cliff"]
	for y in range(0, 24):
		cells[Vector2i(12, y)] = bands[(y / 4) % bands.size()]
	map.set_cells(cells)
	for i in bands.size():
		var p := PLAYER_SCENE.instantiate() as Player
		p.collision_layer = 0
		p.collision_mask = 0
		p.terrain = map
		add_child(p)
		p.global_position = Vector2(2 * cs + i * 60, (i * 4 + 2) * cs)
		_players.append(p)
	Input.action_press(&"move_right")
	_players[1].try_dash(Vector2.RIGHT)
	# Band 4 (chasm) player is pushed instead of walking the whole way.
	get_tree().create_timer(0.3).timeout.connect(func(): _players[4].displace(Vector2(1200, 0)))
	print("[266] block scene: players walking/dashing/pushed into chasm/cliff/pine_forest/mountain")

func _physics_process(_delta: float) -> void:
	for p in _players:
		if p.global_position.x > 12 * map.cell_size:
			print("[266] player entered a non-walkable cell at ", p.global_position)
