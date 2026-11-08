extends SceneTree
## Track A (#59) harness: enemy death -> reward drop spawns at the kill spot;
## walk-over auto-pick-up removes the spell from the run-scoped pool.
## Synthetic apply_damage is a named headless complement only; browser
## real-input evidence follows separately. The harness REUSES the production
## reward pool when the E main.gd mount is present and mounts its own only
## when the group is empty. The
## caster unlock seam is now live (B unlock_spell on main): pickup must call
## caster.unlock_spell and emit spell_unlocked with the granted spell.
## Fixture isolation: assertions run against a deterministic in-code
## bolt-only RewardTable fixture mounted on the pool/enemy below - the
## production demo_table.tres gained a second entry (Summon Ally, #241),
## which made drop content and exhaustion assertions table-content-dependent.
var scene: Node
var p: Player
var pool: RewardPool
var enemy: Enemy
var table: RewardTable
var caster: Node
var bolt: Spell
var unlock_signals: Array = []
var kill_pos := Vector2.ZERO
var phase := 0
var t := 0.0
var ok := true

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			# In a SceneTree driver, Main._ready (hub load) runs on the first
			# frame, not during add_child - wait for current_area first.
			if scene.current_area == null:
				return false
			# Deterministic fixture table: one bolt entry, built in code (no
			# new resource file). The SAME fixture table feeds the harness
			# pool mount, the enemy drop roll and every assertion below, so
			# production table contents can no longer break this driver.
			table = RewardTable.new()
			var bolt_entry := RewardEntry.new()
			bolt_entry.kind = RewardEntry.Kind.SPELL
			bolt_entry.spell = load("res://resources/spells/placeholder_bolt.tres")
			bolt_entry.weight = 1.0
			var fixture_entries: Array[RewardEntry] = [bolt_entry]
			table.entries = fixture_entries
			# Reuse the production reward pool when present (group-first
			# semantics: drops and grants resolve to the FIRST pool in the
			# reward_pool group, so a second harness mount would be bypassed).
			# Mount a harness-local pool only when the group is empty. The
			# pool has no reset API, so a pool that already granted this
			# entry fails loudly below instead of passing on stale state.
			pool = get_first_node_in_group("reward_pool") as RewardPool
			if pool == null:
				pool = RewardPool.new()
				pool.name = "RewardPool"
				scene.add_child(pool)
				pool.setup(table)
			enemy = load("res://scenes/enemy.tscn").instantiate()
			enemy.position = Vector2(576, 300)
			enemy.player_path = NodePath("../../Player")
			enemy.reward_table = table
			scene.current_area.add_child(enemy)
			caster = p.get_node_or_null("SpellCaster")
			bolt = load("res://resources/spells/placeholder_bolt.tres")
			if caster == null:
				print("[A] FAIL no SpellCaster on Player"); ok = false
			elif caster.has_signal("spell_unlocked"):
				caster.spell_unlocked.connect(func(sp): unlock_signals.append(sp))
			if caster != null and caster.get_unlocked().has(bolt):
				print("[A] FAIL bolt unexpectedly unlocked pre-kill"); ok = false
			# Isolation: with no pool reset API, a pre-granted entry would
			# make the grant assertions meaningless. Fail loudly instead.
			if not pool.is_eligible(table.entries[0]):
				print("[A] FAIL pool already granted bolt entry pre-kill (stale state, no reset API)"); ok = false
			phase = 1; t = 0
		1:
			if t > 0.5:
				# Synthetic kill (headless complement, not a combat claim).
				kill_pos = enemy.global_position
				enemy.apply_damage(999)
				phase = 2; t = 0
		2:
			if t > 0.5:
				var drops := get_nodes_in_group("reward_drops")
				if drops.size() != 1:
					print("[A] FAIL drop count after kill: ", drops.size()); ok = false
				elif drops[0].global_position.distance_to(kill_pos) > 1.0:
					print("[A] FAIL drop position: ", drops[0].global_position); ok = false
				else:
					print("[A] drop spawned at kill spot OK")
				if drops.size() == 1:
					p.global_position = drops[0].global_position
				phase = 3; t = 0
		3:
			if t > 0.6:
				var entry: RewardEntry = table.entries[0]
				if pool.granted().has(entry) and not pool.is_eligible(entry):
					print("[A] pool removal on grant OK")
				else:
					print("[A] FAIL pool grant state"); ok = false
				if table.roll(pool.granted()) != null:
					print("[A] FAIL exhausted pool still rolls"); ok = false
				else:
					print("[A] exhausted pool rolls null OK")
				var drops := get_nodes_in_group("reward_drops")
				var alive := false
				for d in drops:
					if is_instance_valid(d) and d.monitoring:
						alive = true
				if alive:
					print("[A] FAIL drop not consumed"); ok = false
				else:
					print("[A] drop consumed on pickup OK")
				if caster != null:
					if caster.get_unlocked().has(bolt):
						print("[A] caster unlock seam OK: bolt unlocked on pickup")
					else:
						print("[A] FAIL bolt not unlocked on caster"); ok = false
					if unlock_signals.size() == 1 and unlock_signals[0] == bolt:
						print("[A] spell_unlocked fired once with granted spell OK")
					else:
						print("[A] FAIL spell_unlocked count/content: ", unlock_signals.size()); ok = false
				print("[A] ", "PASS" if ok else "FAIL")
				return true
		_:
			return true
	if t > 6.0:
		print("[A] FAIL timeout in phase ", phase)
		return true
	return false
