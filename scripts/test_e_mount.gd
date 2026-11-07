extends SceneTree
## E production mount + first playable config harness: Main mounts the
## reward/progression children ONCE, wired with the approved 2026-11-07
## package: single-Bolt pool table, two fork upgrades at 10 Fire Ball casts,
## DungeonA demo enemies carrying that table. Asserts mount shape and the
## approved config only - Mastery/Signature remain unbuilt.
var scene: Node
var phase := 0
var t := 0.0
var ok := true

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if scene.current_area == null:
				return false
			var pool := scene.get_node_or_null("RewardPool")
			var progress := scene.get_node_or_null("SpellProgress")
			var panel := scene.get_node_or_null("EquipPanel")
			if pool == null or progress == null or panel == null:
				print("[E] FAIL missing mount: pool=", pool != null, " progress=", progress != null, " panel=", panel != null); ok = false
				return _done()
			if get_nodes_in_group("reward_pool").size() != 1:
				print("[E] FAIL reward_pool group size"); ok = false
			else:
				print("[E] reward pool mounted once OK")
			if get_nodes_in_group("spell_progress").size() != 1:
				print("[E] FAIL spell_progress group size"); ok = false
			# Provider wiring: caster resolved, exactly the two approved fork
			# paths for Fire Ball, both gated at 10 casts (equal-cost choice).
			var fireball: Spell = load("res://resources/spells/fire_ball.tres")
			var mana: Spell = load("res://resources/spells/mana_shot.tres")
			var paths: Array = progress.get_upgrade_paths(fireball)
			if paths.size() == 2:
				print("[E] provider exposes both fork paths OK")
			else:
				print("[E] FAIL fork path count: ", paths.size()); ok = false
			for u in paths:
				if u.xp_threshold != 10:
					print("[E] FAIL threshold: ", u.id, "=", u.xp_threshold); ok = false
			if not progress.get_upgrade_paths(mana).is_empty():
				print("[E] FAIL unexpected Mana Shot paths"); ok = false
			# Threshold gate via the REAL signal path: 9 casts no, 10 yes.
			var caster: Node = scene.get_node("Player/SpellCaster")
			for i in 9:
				caster.spell_cast.emit(fireball)
			if progress.can_upgrade(fireball):
				print("[E] FAIL can_upgrade below 10 casts"); ok = false
			caster.spell_cast.emit(fireball)
			if progress.can_upgrade(fireball):
				print("[E] fork unlocks at exactly 10 casts OK")
			else:
				print("[E] FAIL cannot upgrade at 10 casts"); ok = false
			# Panel: hidden at boot, player resolved, provider wired.
			if panel.visible:
				print("[E] FAIL panel visible at boot"); ok = false
			else:
				print("[E] panel hidden at boot OK")
			# Pool carries the approved single-Bolt table, eligible at boot.
			var demo: RewardTable = load("res://resources/rewards/demo_table.tres")
			if pool.is_eligible(demo.entries[0]):
				print("[E] pool bolt entry eligible at boot OK")
			else:
				print("[E] FAIL pool bolt entry not eligible"); ok = false
			# DungeonA demo enemies mount with that table (production geometry:
			# area is a Main child, Player resolves at ../../Player).
			var area := Node2D.new()
			area.name = "DungeonA"
			scene.add_child(area)
			scene._mount_demo_enemies(area)
			var mounted := 0
			var tables_ok := true
			for c in area.get_children():
				if c is Enemy:
					mounted += 1
					if c.reward_table != demo:
						tables_ok = false
			if mounted == 3 and tables_ok:
				print("[E] 3 DungeonA enemies carry the bolt table OK")
			else:
				print("[E] FAIL enemy mounts/tables: ", mounted, " tables_ok=", tables_ok); ok = false
			area.queue_free()
			phase = 1; t = 0
		1:
			if t > 0.3:
				# Tab toggles the panel via its own registered action.
				var panel := scene.get_node("EquipPanel")
				var ev := InputEventAction.new()
				ev.action = &"equip_panel"
				ev.pressed = true
				panel._unhandled_input(ev)
				if panel.visible and get_nodes_in_group("modal_ui").size() == 1:
					print("[E] Tab opens panel + modal_ui join OK")
				else:
					print("[E] FAIL panel toggle/modal: visible=", panel.visible); ok = false
				ev = InputEventAction.new()
				ev.action = &"equip_panel"
				ev.pressed = true
				panel._unhandled_input(ev)
				if not panel.visible and get_nodes_in_group("modal_ui").is_empty():
					print("[E] Tab closes panel + modal_ui leave OK")
				else:
					print("[E] FAIL panel close"); ok = false
				return _done()
		_:
			return true
	if t > 6.0:
		print("[E] FAIL timeout in phase ", phase)
		return true
	return false

func _done() -> bool:
	print("[E] ", "PASS" if ok else "FAIL")
	return true
