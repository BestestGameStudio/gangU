extends Node2D
## Standalone season debug scene: harness/evidence only, not reachable from
## the game. Seed from GANGU_SEED (default 1); season from GANGU_SEASON
## (spring|summer|autumn|winter), else the seed's own season.
## GANGU_AUTOTEST=1 quits after a moment.

var map_seed := 1

@onready var map: TerrainMap = $TerrainMap

func _ready() -> void:
	var env_seed := OS.get_environment("GANGU_SEED")
	if env_seed.is_valid_int():
		map_seed = env_seed.to_int()
	TerrainGen.generate(map, map_seed, TerrainGen.DEFAULT_SIZE)
	var named := TerrainSeason.from_name(OS.get_environment("GANGU_SEASON"))
	map.season = TerrainSeason.for_seed(map_seed) if named == -1 else named as TerrainSeason.Season
	print("[170] seed ", map_seed, " season ", TerrainSeason.NAMES[map.season])
	if OS.get_environment("GANGU_AUTOTEST") == "1":
		get_tree().create_timer(2.0).timeout.connect(func(): get_tree().quit())
