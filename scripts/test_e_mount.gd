extends SceneTree
## E production mount harness: Main mounts the reward/progression children
## ONCE, wired but INERT until content lands. Asserts the mount shape and
## inertness only - no gameplay/content claims.
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
			# Provider wiring: caster resolved, upgrade list EMPTY (inert)
			# until the human playable-config choice lands content.
			var fireball: Spell = load("res://resources/spells/fire_ball.tres")
			var paths: Array = progress.get_upgrade_paths(fireball)
			if paths.is_empty() and not progress.can_upgrade(fireball):
				print("[E] provider inert (no paths, cannot upgrade) OK")
			else:
				print("[E] FAIL provider not inert: paths=", paths.size()); ok = false
			# Panel: hidden at boot, player resolved, provider wired.
			if panel.visible:
				print("[E] FAIL panel visible at boot"); ok = false
			else:
				print("[E] panel hidden at boot OK")
			# Enemies carry no reward_table: nothing can drop.
			var enemies := get_nodes_in_group("enemies")
			var any_table := false
			for e in enemies:
				if e.reward_table != null:
					any_table = true
			if any_table:
				print("[E] FAIL enemy reward_table assigned (content leak)"); ok = false
			else:
				print("[E] no enemy loot tables (inert) OK")
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
