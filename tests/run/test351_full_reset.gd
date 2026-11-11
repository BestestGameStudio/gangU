extends SceneTree
## #351 harness: death is a FULL reset (Colin, 2026-11-08). Boots the real
## main.tscn, dirties every kind of run state the issue names, kills the
## player through the production RunManager path and checks the reloaded run
## starts clean:
##   world        - back in the hub, not the dungeon we died in
##   dungeon clear- DungeonA objective completed before death; fresh run has
##                  no completed objective and DungeonA re-mounts its enemies
##   spells       - collected extra spell gone, loadout == starting_spells
##   upgrades     - SpellProgress cast counts and tiers back to 0
##   coins        - CurrencyWallet balance back to 0
##   map          - stand-in for root-parked state (#347/#348) in the
##                  RunManager.RUN_STATE_GROUP gets reset_run_state() called
## Run: timeout 300 godot --headless -s tests/run/test351_full_reset.gd

class FakeMap extends Node:
	## Stand-in for future persistent map / overworld cleared-state.
	var revealed: Dictionary = {}
	var cleared: Dictionary = {}
	var resets := 0
	func _ready() -> void:
		add_to_group(RunManager.RUN_STATE_GROUP)
	func reset_run_state() -> void:
		revealed.clear()
		cleared.clear()
		resets += 1

var ok := true
var phase := 0
var t := 0.0
var old_scene: Node
var map: FakeMap
var extra := Spell.new()
var fire_ball: Spell = load("res://data/spells/fire_ball.tres")
var objective_done := false

func _check(cond: bool, name: String) -> void:
	print("[351] ", "PASS " if cond else "FAIL ", name)
	if not cond:
		ok = false

func _initialize() -> void:
	extra.mode = Spell.CastMode.PROJECTILE
	map = FakeMap.new()
	map.name = "FakeMap351"
	root.add_child(map)
	old_scene = load("res://game/core/main.tscn").instantiate()
	root.add_child(old_scene)
	current_scene = old_scene

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if old_scene.area_loader.current_area == null:
				return false
			# --- world: enter DungeonA (real swap path) ---
			old_scene.area_loader.enter_overworld()
			old_scene.area_loader.dungeon_cleared.connect(func(id):
				if id == &"dungeon_a": objective_done = true)
			phase = 1; t = 0.0
		1:
			if t < 0.2:
				return false
			# --- dungeon cleared-state: kill every enemy for real ---
			for e in get_nodes_in_group("enemies"):
				if e is Enemy:
					e.apply_damage(100000)
			phase = 2; t = 0.0
		2:
			# #392: slimes split, keep killing every frame until none remain.
			for e in get_nodes_in_group("enemies"):
				if e is Enemy and is_instance_valid(e) and not e.is_queued_for_deletion():
					e.apply_damage(100000)
			if t < 0.5:
				return false
			_check(objective_done, "setup: DungeonA cleared before death")
			# --- coins / spells / upgrades / map ---
			var wallet := old_scene.get_node("CurrencyWallet") as CurrencyWallet
			wallet.add(42)
			_check(wallet.balance() == 42, "setup: wallet holds 42 coins")
			var caster := old_scene.get_node("Player/SpellCaster") as SpellCaster
			extra.spell_name = "Test351Extra"
			caster.add_spell(extra)
			_check(extra in caster.spells, "setup: extra spell collected")
			var prog := old_scene.get_node("SpellProgress") as SpellProgress
			for i in 10:
				prog._on_spell_cast(fire_ball)
			var applied := prog.apply_upgrade(fire_ball, &"fireball_split") if prog.can_upgrade(fire_ball) else false
			_check(prog.cast_count(fire_ball) >= 10, "setup: fire ball XP recorded")
			print("[351] info: fireball_split applied before death = ", applied)
			map.revealed[&"dungeon_a"] = true
			map.cleared[&"dungeon_a"] = true
			# --- die through the production path ---
			var p := old_scene.get_node("Player") as Player
			var manager := old_scene.get_node("RunManager") as RunManager
			var revive := ReviveSatchel.new()
			revive.player_path = NodePath("../Player")
			old_scene.add_child(revive)
			manager.satchel = revive
			revive.collect()
			p.apply_damage(100000)
			_check(p.hp > 0 and not manager._restarting and get_nodes_in_group(&"player_death_presentation").is_empty(), "revive intercepts before any death presentation")
			manager.satchel = null
			revive.queue_free()
			p.apply_damage(100000)
			_check(manager.restart_delay == 1.5 and manager._restarting, "existing 1.5-second death restart retained")
			_check(get_nodes_in_group(&"player_death_presentation").size() == 1, "actual unrevived death creates one presentation")
			var presentation := get_nodes_in_group(&"player_death_presentation")[0] as PlayerDeathPresentation
			_check(presentation._audio.playing and not presentation._audio.stream.loop, "real death starts one nonlooping audio cue")
			_check(absf(presentation._audio.stream.get_length() - 1.5) < 0.02, "cue fits existing 1.5-second screen window")
			p.died.emit()
			_check(get_nodes_in_group(&"player_death_presentation").size() == 1, "duplicate death does not repeat presentation")
			_check((p.get_node("SpellCaster") as SpellCaster).process_mode == Node.PROCESS_MODE_DISABLED, "dead casting stays disabled")
			phase = 3; t = 0.0
		3:
			if t > 10.0:
				_check(false, "run reloaded within 10s of death")
				phase = 9
				return false
			var s := current_scene
			if s == null or s == old_scene or not is_instance_valid(s) or s.get("area_loader") == null:
				return false
			phase = 4; t = 0.0
		4:
			if t < 0.2:
				return false
			var s := current_scene
			_check(s != old_scene, "death reloaded the run scene")
			_check(get_nodes_in_group(&"player_death_presentation").is_empty(), "death screen is gone on the next run")
			# world
			_check(s.area_loader.current_area.name == &"Hub", "world: fresh run starts in the hub (got %s)" % s.area_loader.current_area.name)
			# dungeon cleared-state: no completed objective carried, DungeonA repopulates
			_check(not s.area_loader.is_cleared(&"dungeon_a"), "encounter clear state reset")
			s.area_loader.enter_overworld()
			_check(s.area_loader.region_for(&"dungeon_a").layout != null, "region rebuilt in fresh run")
			_check(get_nodes_in_group("enemies").size() > 0, "region enemies respawned")
			# coins
			_check((s.get_node("CurrencyWallet") as CurrencyWallet).balance() == 0, "coins: wallet back to 0")
			# spells
			var caster := s.get_node("Player/SpellCaster") as SpellCaster
			_check(not (extra in caster.spells), "spells: collected extra spell gone")
			var same := caster.spells.size() == caster.starting_spells.size()
			for sp in caster.starting_spells:
				same = same and sp in caster.spells
			_check(same, "spells: loadout == starting_spells (%d)" % caster.spells.size())
			# upgrades
			var prog := s.get_node("SpellProgress") as SpellProgress
			_check(prog.cast_count(fire_ball) == 0, "upgrades: fire ball XP back to 0")
			var tiers := 0
			for sp in caster.spells:
				tiers += prog.get_tier(sp)
			_check(tiers == 0, "upgrades: every held spell at Base tier")
			# map / persistent run state
			_check(map.resets == 1, "map: reset_run_state() called once on death (got %d)" % map.resets)
			_check(map.revealed.is_empty() and map.cleared.is_empty(), "map: revealed + cleared state wiped")
			_check(is_instance_valid(map), "map: root-parked node itself survives (only its state resets)")
			phase = 9
		9:
			print("RESULT: ", "ALL PASS" if ok else "FAILURES")
			quit(0 if ok else 1)
			phase = 10
	return false
