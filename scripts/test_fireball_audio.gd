extends SceneTree
## #584: real cast and collision paths, approved streams and one-shot lifetime.
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("[584] ", label, " -> ", "PASS" if ok else "FAIL")
func _initialize() -> void:
	call_deferred("_run")
func _voices(stream: AudioStream) -> int:
	var n := 0
	for p in get_nodes_in_group(&"fireball_audio"):
		if p.stream == stream and not p.is_queued_for_deletion(): n += 1
	return n
func _quiet_voices(stream: AudioStream) -> bool:
	var count := 0
	for v in get_nodes_in_group(&"fireball_audio"):
		if v.stream == stream and not v.is_queued_for_deletion():
			count += 1
			if v.volume_db != -10.0 or v.pitch_scale != 1.0 or v.bus != &"Master":
				return false
	return count > 0
func _shot(stage: Node2D, spell: Spell, source: Node2D) -> Projectile:
	var p: Projectile = load("res://scenes/projectile.tscn").instantiate()
	p.setup(spell, Vector2.RIGHT, source)
	stage.add_child(p)
	p.set_physics_process(false)
	return p
func _run() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var fire: Spell = load("res://resources/spells/fire_ball.tres")
	var water: Spell = load("res://resources/spells/water_ball.tres")
	for id in FireballAudio.IDS:
		_check(FireballAudio.supports(load("res://resources/spells/%s.tres" % id)), "family supported: %s" % id)
	_check(not FireballAudio.supports(water) and not FireballAudio.supports(null), "other spells/null silent")
	_check(absf(FireballAudio.CAST.get_length() - 0.65) < 0.03 and absf(FireballAudio.IMPACT.get_length() - 1.0) < 0.03, "approved stream durations")
	_check(not (FireballAudio.CAST as AudioStreamOggVorbis).loop and not (FireballAudio.IMPACT as AudioStreamOggVorbis).loop, "one-shots not loops")
	var owner := Node2D.new()
	stage.add_child(owner)
	var caster := SpellCaster.new()
	caster.projectile_scene = load("res://scenes/projectile.tscn")
	owner.add_child(caster)
	caster.set_process(false)
	caster.set_physics_process(false)
	caster.aim_override = Vector2(200, 0)
	caster.cast() # null spell, no cast
	_check(_voices(FireballAudio.CAST) == 0, "null/uncommitted cast silent")
	caster.add_spell(fire)
	caster.cast()
	_check(_voices(FireballAudio.CAST) == 1 and is_equal_approx(caster.cooldown_remaining(fire), fire.cooldown), "actual committed cast one cue, cooldown unchanged")
	_check(_quiet_voices(FireballAudio.CAST), "actual firing cue is quieter at -10 dB")
	var split: Spell = load("res://resources/spells/fire_ball_split.tres")
	caster._cast_spell(split)
	_check(_voices(FireballAudio.CAST) == 2, "split fanout only one extra cast cue")
	caster._cast_spell(water)
	_check(_voices(FireballAudio.CAST) == 2, "other actual spell cast silent")
	for p in get_nodes_in_group(&"projectiles"):
		p.queue_free()
	await process_frame
	var enemy: Enemy = load("res://scenes/enemy.tscn").instantiate()
	enemy.position = Vector2(1000, 1000)
	stage.add_child(enemy)
	enemy.set_physics_process(false)
	var p := _shot(stage, fire, owner)
	p._on_body_entered(owner)
	_check(_voices(FireballAudio.IMPACT) == 0, "own source collision silent")
	var hp := enemy.hp
	p._on_body_entered(enemy)
	_check(_voices(FireballAudio.IMPACT) == 1 and enemy.hp < hp and p.is_queued_for_deletion(), "real enemy hit sounds with unchanged damage and despawn")
	_check(_quiet_voices(FireballAudio.IMPACT), "actual impact cue is quieter at -10 dB")
	p._on_body_entered(enemy)
	_check(_voices(FireballAudio.IMPACT) == 1, "already-spent shot does not double sound")
	await process_frame
	_check(_voices(FireballAudio.IMPACT) == 1, "impact survives projectile deletion")
	var wall := StaticBody2D.new()
	stage.add_child(wall)
	var solid := _shot(stage, fire, owner)
	solid._on_body_entered(wall)
	_check(_voices(FireballAudio.IMPACT) == 2 and solid.is_queued_for_deletion(), "non-damageable solid collision sounds")
	var expiry := _shot(stage, fire, owner)
	expiry._traveled = fire.range
	expiry._physics_process(0.0)
	_check(expiry.is_queued_for_deletion() and _voices(FireballAudio.IMPACT) == 2, "max-range expiry silent")
	var wet := _shot(stage, water, owner)
	wet._on_body_entered(wall)
	_check(_voices(FireballAudio.IMPACT) == 2, "other spell collision silent")
	var map := TerrainMap.new()
	map.cell_size = 32
	stage.add_child(map)
	map.set_cells({Vector2i(12, 0): TerrainTypes.OBSTACLE})
	var terrain_shot := _shot(stage, fire, owner)
	terrain_shot._terrain = map
	terrain_shot.global_position = Vector2(350, 16)
	terrain_shot._sweep_segment(Vector2(350, 16), Vector2(100, 0))
	_check(terrain_shot.is_queued_for_deletion() and _voices(FireballAudio.IMPACT) == 3 and absf(terrain_shot.global_position.x - 384.0) < 1.0, "real terrain wall stop sounds at unchanged wall face")
	for v in get_nodes_in_group(&"fireball_audio"):
		_check(v.get_parent() == stage and v.bus == &"Master" and v.volume_db == -10.0 and v.pitch_scale == 1.0 and v.playing, "scene-owned cast and impact playback is -10 dB with unchanged pitch and Master settings")
	# Dummy/headless audio callback timing can lag wall-clock timers under load.
	var deadline := Time.get_ticks_msec() + 4000
	while not get_nodes_in_group(&"fireball_audio").is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(get_nodes_in_group(&"fireball_audio").is_empty(), "all one-shot players self-clean after finish")
	stage.free()
	quit(1 if failures else 0)
