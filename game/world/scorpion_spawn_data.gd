extends AreaSpawnData
## Run-owned scene data carrier. The existing overworld spawner mounts it
## once and retains living/dead state across hub/dungeon travel.
@export var arena_path := NodePath("../DesertStatueArena")
@export var ground_path := NodePath("../Ground")
@export var scorpion_scene: PackedScene
@export var scorpion_definition: EnemyDefinition

func _ready() -> void:
	var arena := get_node(arena_path) as DesertStatueArena
	var ground := get_node(ground_path) as OverworldGround
	arena.configure_size()
	entries.clear()
	# Choose deterministic sand samples in the approved outside-barrier band.
	# No terrain repaint and no hard-coded screen-size assumption.
	for sector in 4:
		var found := false
		for radial in [180.0,220.0,260.0,300.0,160.0,320.0]:
			for turn in [0.0,0.12,-0.12,0.24,-0.24]:
				var angle: float = -PI/4.0 + sector*PI/2.0 + turn
				var p: Vector2 = arena.position + Vector2.from_angle(angle)*(arena.barrier_radius+radial)
				if ground._compute_lattice_type(p) != DualGrid.T.SAND: continue
				var entry := SpawnEntry.new(p,scorpion_scene,null,scorpion_definition)
				entries.append(entry)
				found = true
				break
			if found: break
		if not found: push_error("Scorpion spawn: no sand sample in approved sector/band")
