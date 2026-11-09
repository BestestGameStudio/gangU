extends SceneTree
## E production mount + first playable config harness: Main mounts the
## reward/progression children ONCE, wired with the approved 2026-11-07
## package: single-Bolt pool table, two fork upgrades at 10 Fire Ball casts,
## DungeonA demo enemies carrying that table. Asserts mount shape and the
## approved config only - Mastery/Signature remain unbuilt.
var scene: Node
var phase := 0
var step := 0
var sig_log: Array = []
var _p2_spell_btn: Button = null
var _kb_nav_ok := false


func _press_key(code: Key) -> void:
	# Faithful keys: a real keyboard sets BOTH keycode and physical_keycode;
	# ui_focus_next's default binding is logical-keycode, so keycode-less
	# synthetic events never exercised the GUI-consumption path (live bug).
	for pr in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = pr
		get_root().push_input(k)


## #238: the upgrade indicator is the chevron on the spell's HUD slot square.
func _chevron_shown(hud: Node, caster: Node, spell: Spell) -> bool:
	var index: int = caster.get_slots().find(spell)
	if index == -1:
		return false
	return hud.get_node("Root/SpellGrid").get_child(index).get_node("UpgradeChevron").visible

func _press_tab() -> void:
	_press_key(KEY_TAB)
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
			# #211: Mana Shot now has its two Specialization paths (Volley +
			# Lance), same 10-cast tier-1 gate as the Fire Ball forks.
			var mana_paths: Array = progress.get_upgrade_paths(mana)
			if mana_paths.size() == 2 and mana_paths[0].id == &"manashot_volley" and mana_paths[1].id == &"manashot_lance":
				print("[E] provider exposes both Mana Shot paths OK")
			else:
				print("[E] FAIL Mana Shot paths: ", mana_paths.map(func(u): return u.id)); ok = false
			for u in mana_paths:
				if u.xp_threshold != 10 or u.tier != 1:
					print("[E] FAIL mana threshold/tier: ", u.id); ok = false
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
			# area is a Main child, Player resolves at ../../Player). #100: the
			# synthetic area carries a SpawnData fixture and mounts through the
			# generic mounter - same three positions, SAME table assert retained.
			var area := Node2D.new()
			area.name = "DungeonA"
			scene.add_child(area)
			var carrier := AreaSpawnData.new()
			carrier.name = "SpawnData"
			var enemy_scene: PackedScene = load("res://scenes/enemy.tscn")
			for pos in [Vector2(250, 280), Vector2(576, 220), Vector2(900, 280)]:
				carrier.entries.append({"position": pos, "enemy": enemy_scene, "reward_table": demo})
			area.add_child(carrier)
			scene._mount_area_spawns(area)
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
			# Frame-separated faithful Tab toggles: push_input is synchronous,
			# but CanvasLayer visibility/grab propagation needs one frame.
			var panel1 := scene.get_node("EquipPanel")
			match step:
				0:
					if t > 0.3:
						# HUD arrow after phase 0's 10 casts: Fire Ball only.
						var hud1: Node = scene.get_node("HUD")
						var fb1: Spell = load("res://resources/spells/fire_ball.tres")
						var ms1: Spell = load("res://resources/spells/mana_shot.tres")
						var caster1: Node = scene.get_node("Player/SpellCaster")
						var fb_shown := _chevron_shown(hud1, caster1, fb1)
						var ms_shown := _chevron_shown(hud1, caster1, ms1)
						if fb_shown and not ms_shown:
							print("[E] HUD chevron on Fire Ball only at 10 casts OK")
						else:
							print("[E] FAIL HUD chevron: fb=", fb_shown, " ms=", ms_shown); ok = false
						_press_tab()
						step = 1
				1:
					if panel1.visible and get_nodes_in_group("modal_ui").size() == 1:
						print("[E] Tab opens panel + modal_ui join OK")
					else:
						print("[E] FAIL panel toggle/modal: visible=", panel1.visible); ok = false
					_press_tab()
					step = 2
				2:
					if not panel1.visible and get_nodes_in_group("modal_ui").is_empty():
						print("[E] Tab closes panel + modal_ui leave OK")
					else:
						print("[E] FAIL panel close"); ok = false
					step = 0
					phase = 2; t = 0
		2:
			# Apply path through the REAL panel buttons: the 10 casts emitted in
			# phase 0 qualify both forks; open the panel, select, click.
			var panel := scene.get_node("EquipPanel")
			var progress := scene.get_node("SpellProgress")
			var caster: Node = scene.get_node("Player/SpellCaster")
			var fireball: Spell = load("res://resources/spells/fire_ball.tres")
			var split: Spell = load("res://resources/spells/fire_ball_split.tres")
			match step:
				0:
					progress.upgrades_changed.connect(func(sp): sig_log.append(sp))
					_press_tab()
					step = 1
				1:
					panel._on_slot_pressed(0) # #375: select the equipped Fire Ball via its slot
					var texts: Array = []
					var buttons: Array = []
					for c in panel._upgrade_box.find_children("*", "UpgradeCard", true, false):
						if c is UpgradeCard and not c.get_parent().get_parent().is_queued_for_deletion():
							texts.append(c.name_label.text)
							buttons.append(c)
					texts.sort()
					if texts != ["Beam [S]", "Split shot [S]"] or buttons.size() != 2:
						print("[E] FAIL fork buttons: ", texts); ok = false
						return _done()
					print("[E] both fork buttons render after fix OK")
					# Focus regression (live Chrome bug): with any panel button
					# holding GUI focus, a faithful Tab must STILL close the panel;
					# before the fix the focused button consumed Tab as
					# ui_focus_next and the panel could never be closed.
					buttons[0].grab_focus()
					if get_root().gui_get_focus_owner() != buttons[0]:
						print("[E] FAIL upgrade focus not held"); ok = false
						return _done()
					_press_tab()
					step = 2
				2:
					if panel.visible:
						print("[E] FAIL focused upgrade button consumed Tab"); ok = false
						return _done()
					print("[E] focused UPGRADE button: Tab still closes OK")
					_press_tab()
					step = 3
				3:
					panel._on_slot_pressed(0) # select Fire Ball via its slot
					panel._slot_buttons[0].grab_focus()
					if get_root().gui_get_focus_owner() != panel._slot_buttons[0]:
						print("[E] FAIL slot focus not held"); ok = false
						return _done()
					_press_tab()
					step = 4
				4:
					if panel.visible:
						print("[E] FAIL focused slot button consumed Tab"); ok = false
						return _done()
					print("[E] focused SLOT button: Tab still closes OK")
					_press_tab()
					step = 5
				5:
					# Keyboard controls retained: arrows move focus, Enter activates.
					# #375: the unlocked rows are gone, so the SLOT buttons are the
					# focusable spell surface.
					_p2_spell_btn = panel._slot_buttons[0]
					_p2_spell_btn.grab_focus()
					if get_root().gui_get_focus_owner() != _p2_spell_btn:
						print("[E] FAIL slot focus not held"); ok = false
						return _done()
					_press_key(KEY_DOWN)
					step = 6
				6:
					var f1: Control = get_root().gui_get_focus_owner()
					_kb_nav_ok = f1 != null and f1 != _p2_spell_btn
					_press_key(KEY_ENTER)
					step = 7
				7:
					if _kb_nav_ok and panel._selected != null:
						print("[E] keyboard focus nav + Enter activation retained OK")
					else:
						print("[E] FAIL keyboard operability: nav=", _kb_nav_ok, " selected=", panel._selected); ok = false
					_p2_spell_btn = panel._slot_buttons[0]
					_p2_spell_btn.grab_focus()
					if get_root().gui_get_focus_owner() != _p2_spell_btn:
						print("[E] FAIL slot refocus not held"); ok = false
						return _done()
					_press_tab()
					step = 8
				8:
					if panel.visible:
						print("[E] FAIL focused slot button consumed Tab (keyboard leg)"); ok = false
						return _done()
					print("[E] focused slot button (keyboard leg): Tab still closes OK")
					_press_tab()
					step = 9
				9:
					panel._on_slot_pressed(0) # select Fire Ball via its slot
					# Click Fire Ball's own slot again (deselects under #375),
					# re-select, then a manual click on Split shot -> apply -> slot
					# replacement. Buttons are rebuilt on refresh, so re-capture
					# after re-selecting.
					panel._slot_buttons[0].pressed.emit()
					panel._on_slot_pressed(0)
					var buttons2: Array = []
					for c2 in panel._upgrade_box.find_children("*", "UpgradeCard", true, false):
						if c2 is UpgradeCard and not c2.get_parent().get_parent().is_queued_for_deletion():
							buttons2.append(c2)
					var split_btn: Button = buttons2[0] if buttons2[0].name_label.text.begins_with("Split shot") else buttons2[1]
					split_btn.pressed.emit()
					if sig_log.size() != 1 or sig_log[0] != fireball:
						print("[E] FAIL upgrades_changed: ", sig_log.size(), " calls"); ok = false
					else:
						print("[E] upgrades_changed fired once with source spell OK")
					if not caster.get_unlocked().has(fireball) and caster.get_unlocked().has(split):
						print("[E] click applied split, fire ball replaced OK")
					else:
						print("[E] FAIL replacement: unlocked=", caster.get_unlocked().map(func(x): return x.spell_name)); ok = false
					var slot_texts: Array = []
					for b2 in panel._slot_buttons:
						slot_texts.append(b2.text)
					var shown := false
					for st2 in slot_texts:
						if st2.find("Split") >= 0:
							shown = true
					if shown:
						print("[E] slot shows replaced spell OK")
					else:
						print("[E] FAIL slot replacement not shown: ", slot_texts); ok = false
					if progress.can_upgrade(split):
						print("[E] FAIL split upgradable at 0 casts"); ok = false
					# Stale-selection safety (Mitra repro): after the upgrade,
					# EXPLICITLY hold the removed base resource as the selection,
					# then click the OCCUPIED slot: the refusal must not pre-clear
					# the occupant. (#375: the UI can no longer select an unslotted
					# resource, so the harness sets the stale selection directly.)
					panel._selected = fireball
					panel._slot_buttons[0].pressed.emit()
					if caster.get_slots()[0] == split:
						print("[E] stale-selection click preserves occupied slot OK")
					else:
						print("[E] FAIL stale click cleared slot: ", caster.get_slots()[0]); ok = false
					# Successful reselection + rearrange still works: Split moves to
					# slot 2, swapping with its occupant.
					panel._on_slot_pressed(0)
					panel._slot_buttons[1].pressed.emit()
					if caster.get_slots()[1] == split:
						print("[E] reselect + rearrange to slot 2 OK")
					else:
						print("[E] FAIL reselect/rearrange: ", caster.get_slots()[1]); ok = false
					step = 10
				10:
					# Arrow clears on replacement: Fire Ball row is gone, the
					# Split replacement row (0 casts) shows none.
					var hud2: Node = scene.get_node("HUD")
					if caster.get_slots().has(fireball):
						print("[E] FAIL fireball still slotted after replace"); ok = false
					elif not caster.get_slots().has(split):
						print("[E] FAIL split not slotted after replace"); ok = false
					elif _chevron_shown(hud2, caster, split):
						print("[E] FAIL chevron on fresh Split slot"); ok = false
					else:
						print("[E] chevron clears after Split apply OK")
					step = 0
					phase = 3; t = 0
					return false
		3:
			# Second scenario on a FRESH scene: per-run reset (no arrows at 0
			# casts), then the Beam fork applied - arrow must clear the same.
			match step:
				0:
					scene.queue_free()
					scene = load("res://scenes/main.tscn").instantiate()
					root.add_child(scene)
					current_scene = scene
					step = 1
				1:
					if t < 0.4:
						return false
					var hud3: Node = scene.get_node("HUD")
					var progress3: Node = scene.get_node("SpellProgress")
					var caster3: Node = scene.get_node("Player/SpellCaster")
					var fb3: Spell = load("res://resources/spells/fire_ball.tres")
					if progress3.cast_count(fb3) != 0:
						print("[E] FAIL cast count not reset: ", progress3.cast_count(fb3)); ok = false
					elif _chevron_shown(hud3, caster3, fb3):
						print("[E] FAIL chevron at 0 casts after reset"); ok = false
					else:
						print("[E] fresh-run reset: no arrows at 0 casts OK")
					for i in 10:
						caster3.spell_cast.emit(fb3)
					step = 2
				2:
					var hud4: Node = scene.get_node("HUD")
					var fb4: Spell = load("res://resources/spells/fire_ball.tres")
					if _chevron_shown(hud4, scene.get_node("Player/SpellCaster"), fb4):
						print("[E] chevron returns at 10 casts after reset OK")
					else:
						print("[E] FAIL chevron missing after reset+10"); ok = false
						return _done()
					var progress4: Node = scene.get_node("SpellProgress")
					progress4.apply_upgrade(fb4, &"fireball_beam")
					step = 3
				3:
					var hud5: Node = scene.get_node("HUD")
					var fb5: Spell = load("res://resources/spells/fire_ball.tres")
					var beam: Spell = load("res://resources/spells/fire_ball_beam.tres")
					var caster5: Node = scene.get_node("Player/SpellCaster")
					if caster5.get_slots().has(fb5):
						print("[E] FAIL fireball still slotted after Beam apply"); ok = false
					elif not caster5.get_slots().has(beam):
						print("[E] FAIL beam not slotted after apply"); ok = false
					elif _chevron_shown(hud5, caster5, beam):
						print("[E] FAIL chevron on fresh Beam slot"); ok = false
					else:
						print("[E] chevron clears after Beam apply OK")
					return _done()
		_:
			return true
	if t > 6.0:
		print("[E] FAIL timeout in phase ", phase)
		return true
	return false

func _done() -> bool:
	print("[E] ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
	return true
