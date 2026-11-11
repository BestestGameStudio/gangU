extends SceneTree
## #222: dungeon modifiers foundation. Fixture-only modifiers/effects; no
## production content or numbers.
var failures := 0
var checks := 0

class Recorder extends DungeonModifierEffect:
	var log: Array = []
	func apply(event: StringName, payload: Dictionary, host: DungeonModifierHost) -> void:
		log.append({"event": event, "payload": payload, "host": host})

class Echo extends DungeonModifierEffect:
	var calls := 0
	func apply(event: StringName, _payload: Dictionary, host: DungeonModifierHost) -> void:
		calls += 1
		host.emit_event(event) # re-raises itself: depth guard must stop it

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("[222] ", label, " -> ", "PASS" if ok else "FAIL")

func modifier(key: StringName, event: StringName, effect: DungeonModifierEffect, filter: Dictionary = {}, max_triggers: int = 0) -> DungeonModifier:
	var m := DungeonModifier.new()
	m.id = key
	m.trigger_event = event
	m.trigger_filter = filter
	m.max_triggers = max_triggers
	m.effect = effect
	return m

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for child in root.get_children():
		child.free()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var player := main.get_node("Player") as Player
	player.set_physics_process(false)
	player.max_hp = 100000
	player.hp = 100000

	# Inert in production: no shipped area carries a DungeonModifiers child.
	var any_prod := false
	for path in ["res://scenes/hub.tscn", "res://scenes/dungeon_a.tscn", "res://scenes/dungeon_b.tscn", "res://scenes/dungeon_c.tscn", "res://scenes/dungeon_d.tscn"]:
		if not ResourceLoader.exists(path):
			continue
		var a := (load(path) as PackedScene).instantiate()
		if a.get_node_or_null("DungeonModifiers") != null:
			any_prod = true
		a.free()
	check(not any_prod, "no production area carries modifiers (inert)")

	# Pure trigger matching.
	var rec_m := Recorder.new()
	var filt := modifier(&"f", DungeonModifierHost.ENEMY_DIED, rec_m, {"enemy_scene": "res://x.tscn"})
	check(filt.matches(&"enemy_died", {"enemy_scene": "res://x.tscn", "is_boss": false}), "filter matches equal payload")
	check(not filt.matches(&"enemy_died", {"enemy_scene": "res://y.tscn"}), "filter rejects other value")
	check(not filt.matches(&"enemy_died", {}), "filter rejects missing key")
	check(not filt.matches(&"dungeon_entered", {"enemy_scene": "res://x.tscn"}), "other event rejected")
	check(not modifier(&"", &"e", rec_m).is_valid_definition(), "empty id invalid")
	check(not modifier(&"n", &"e", null).is_valid_definition(), "missing effect invalid")

	# Mount DungeonB (ELIMINATION: mobs then Warlord) with fixture modifiers.
	var area := (load("res://scenes/dungeon_b.tscn") as PackedScene).instantiate()
	var host := DungeonModifierHost.new()
	host.name = "DungeonModifiers"
	var on_entry := Recorder.new()
	var on_any_death := Recorder.new()
	var on_boss_death := Recorder.new()
	var once := Recorder.new()
	var on_boss_spawn := Recorder.new()
	var on_progress := Recorder.new()
	var on_clear := Recorder.new()
	var on_cast := Recorder.new()
	var on_custom := Recorder.new()
	var warlord_path: String = main.area_loader.WARLORD_SCENE.resource_path
	host.modifiers = [
		modifier(&"entry", DungeonModifierHost.DUNGEON_ENTERED, on_entry),
		modifier(&"any_death", DungeonModifierHost.ENEMY_DIED, on_any_death),
		modifier(&"boss_death", DungeonModifierHost.ENEMY_DIED, on_boss_death, {"enemy_scene": warlord_path}),
		modifier(&"once", DungeonModifierHost.ENEMY_DIED, once, {}, 1),
		modifier(&"boss_spawn", DungeonModifierHost.BOSS_SPAWNED, on_boss_spawn),
		modifier(&"progress", DungeonModifierHost.OBJECTIVE_PROGRESS, on_progress),
		modifier(&"clear", DungeonModifierHost.OBJECTIVE_COMPLETED, on_clear),
		modifier(&"cast", DungeonModifierHost.SPELL_CAST, on_cast),
		modifier(&"custom", &"fixture_custom", on_custom),
		null,
		modifier(&"", &"broken", Recorder.new()),
	]
	area.add_child(host)
	main.area_loader._swap(area)
	await process_frame

	check(on_entry.log.size() == 1, "dungeon_entered fired once on mount")
	check(on_entry.log.size() == 1 and on_entry.log[0]["payload"]["dungeon_id"] == &"dungeon_b", "entry payload carries dungeon_id")
	check(on_entry.log.size() == 1 and on_entry.log[0]["payload"]["area"] == area, "entry payload carries area")
	check(on_entry.log.size() == 1 and area.get_node_or_null("ExitPortal") != null and area.get_node_or_null("DungeonObjective") != null, "entry fires after full mount")

	var mobs: Array = []
	for c in area.get_children():
		if c is Enemy:
			mobs.append(c)
	check(mobs.size() > 0, "dungeon_b has mobs (%d)" % mobs.size())
	for e in mobs:
		(e as Enemy).apply_damage(999999)
	check(on_any_death.log.size() == mobs.size(), "enemy_died fired per mob death")
	check(on_boss_death.log.is_empty(), "boss-only filter ignores mob deaths")
	check(once.log.size() == 1 and host.fire_count(&"once") == 1, "max_triggers=1 fires once")
	check(on_progress.log.size() == mobs.size(), "objective_progress bridged")
	check(on_boss_spawn.log.size() == 1, "boss_spawned bridged")
	await process_frame
	await process_frame
	var boss: Enemy = null
	for c in area.get_children():
		if c is Enemy and c.is_in_group("boss") and not c.is_queued_for_deletion():
			boss = c
	check(boss != null, "warlord spawned into area")
	if boss != null:
		boss.apply_damage(999999)
	check(on_boss_death.log.size() == 1, "specific-enemy (warlord) death trigger fired")
	check(on_boss_death.log.size() == 1 and on_boss_death.log[0]["payload"]["is_boss"] == true, "boss death payload is_boss")
	check(on_clear.log.size() == 1, "objective_completed bridged")

	var spell := Spell.new()
	spell.mode = Spell.CastMode.PROJECTILE
	spell.spell_name = "Fixture"
	(main.get_node("Player/SpellCaster") as SpellCaster).spell_cast.emit(spell)
	check(on_cast.log.size() == 1 and on_cast.log[0]["payload"]["spell_name"] == "Fixture", "spell_cast bridged")

	check(host.emit_event(&"fixture_custom", {"k": 1}) == 1 and on_custom.log.size() == 1, "custom event routes via emit_event")
	check(on_custom.log.size() == 1 and on_custom.log[0]["payload"]["k"] == 1 and on_custom.log[0]["payload"]["dungeon_id"] == &"dungeon_b", "custom payload kept + dungeon_id added")

	# Re-entrant effects are capped.
	var echo := Echo.new()
	var loop_host := DungeonModifierHost.new()
	loop_host.modifiers = [modifier(&"echo", &"ping", echo)]
	root.add_child(loop_host)
	loop_host.emit_event(&"ping")
	check(echo.calls == DungeonModifierHost.MAX_EVENT_DEPTH, "nested emit depth capped (%d)" % echo.calls)
	loop_host.free()

	# Leaving the dungeon frees the host (per-mount lifetime).
	var host_ref: WeakRef = weakref(host)
	main.area_loader._swap(load("res://scenes/hub.tscn").instantiate())
	await process_frame
	check(host_ref.get_ref() == null, "host freed with its area on swap")
	(main.get_node("Player/SpellCaster") as SpellCaster).spell_cast.emit(spell)
	check(on_cast.log.size() == 1, "no events after the dungeon is left")

	print("[222] ", checks - failures, "/", checks, " checks passed")
	print("RESULT: ", "ALL PASS" if failures == 0 else "FAILURES")
	quit(0 if failures == 0 else 1)
