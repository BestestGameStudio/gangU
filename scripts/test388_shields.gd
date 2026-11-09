extends SceneTree
## #388 shields foundation: a temporary pool beyond max HP that takes damage
## before HP, uncapped and additive, decaying after a delay (refreshed by new
## grants), shown as a white bar under the HP bar.

var failures := 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("[388] ", label, " -> PASS")
	else:
		failures += 1
		print("[388] ", label, " -> FAIL")

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(5)
	var player: Player = main.get_node("Player")
	var hud: HUD = main.get_node("HUD")
	var hp_bar := hud.get_node("Root/HPBar") as ProgressBar
	var bar := hud.get_node("Root/ShieldBar") as ProgressBar
	var label := hud.get_node("Root/ShieldBar/ShieldLabel") as Label
	var grid := hud.get_node("Root/SpellGrid") as Control

	var health_events: Array = []
	var shield_events: Array = []
	player.health_changed.connect(func(c, m): health_events.append([c, m]))
	player.shield_changed.connect(func(c): shield_events.append(c))

	# Starting state.
	_check(player.shield == 0, "player starts with no shield")
	_check(not bar.visible, "shield bar hidden at 0")
	var grid_y0 := grid.global_position.y

	# Granting.
	player.add_shield(30)
	await process_frame
	_check(player.shield == 30 and shield_events == [30], "add_shield grants and emits shield_changed")
	_check(player.hp == player.max_hp, "shield does not touch HP")
	_check(bar.visible and label.text == "30", "white bar shows with the value (got '%s')" % label.text)
	_check(bar.get_global_rect().position.y >= hp_bar.get_global_rect().end.y, "shield bar sits under the HP bar")
	var fill := bar.get_theme_stylebox("fill") as StyleBoxFlat
	_check(fill != null and fill.bg_color == Color.WHITE, "shield fill is white")
	_check(is_equal_approx(bar.ratio, 30.0 / player.max_hp), "bar fraction scaled to max HP (ratio %.2f)" % bar.ratio)
	_check(not grid.get_global_rect().intersects(bar.get_global_rect()), "spell grid moved clear of the shield bar")
	_check(hud.reserved_rect().encloses(bar.get_global_rect()), "reserved_rect includes the shield bar")

	# Absorb fully: HP untouched, no health_changed.
	health_events.clear()
	player.apply_damage(10)
	_check(player.shield == 20 and player.hp == player.max_hp, "damage below shield is fully absorbed")
	_check(health_events.is_empty(), "fully absorbed hit emits no health_changed")
	_check(label.text == "20", "label follows shield damage")

	# Overflow: shield empties, remainder hits HP.
	player.apply_damage(25)
	_check(player.shield == 0 and player.hp == player.max_hp - 5, "overflow reaches HP (hp %d)" % player.hp)
	_check(health_events.size() == 1, "overflow emits health_changed once")
	_check(not bar.visible, "bar hides once the shield is gone")
	player.heal(5)
	_check(player.shield == 0, "heal does not grant shield")

	# Unbounded + stacking.
	player.add_shield(player.max_hp * 3)
	player.add_shield(7)
	var big := player.max_hp * 3 + 7
	_check(player.shield == big, "shield is uncapped and grants stack additively (%d)" % player.shield)
	_check(label.text == str(big) and is_equal_approx(bar.ratio, 1.0), "bar full and label shows the uncapped value")
	player.add_shield(0)
	player.add_shield(-5)
	_check(player.shield == big, "non-positive grants are ignored")

	# Invulnerability window wins over the shield.
	player.set_invulnerable(true)
	player.apply_damage(50)
	_check(player.shield == big, "invulnerable hits do not consume shield")
	player.set_invulnerable(false)

	# Clearing.
	player.clear_shield()
	_check(player.shield == 0 and not bar.visible, "clear_shield empties the pool")

	# Max HP rescale keeps the bar in sync.
	player.add_shield(50)
	player.stats.add(StatModifier.flat(PlayerStats.MAX_HP, player.max_hp))
	await process_frame
	_check(is_equal_approx(bar.ratio, 50.0 / player.max_hp), "max HP change rescales the shield bar (ratio %.2f)" % bar.ratio)
	player.clear_shield()

	# Decay (owner-clarified): hold for the delay, then gradually drain; a new
	# grant refreshes the pooled clock, damage does not. Physics is paused on
	# the player so the clock is stepped deterministically (binary-exact
	# deltas, so no float slop).
	player.set_physics_process(false)
	player.shield_decay_delay = 2.0
	player.shield_decay_rate = 10.0
	var hp_before := player.hp
	player.add_shield(50)
	_check(is_equal_approx(player.shield_decay_delay_left(), 2.0), "grant starts the delay clock at shield_decay_delay")
	player.tick_shield_decay(1.5)
	_check(player.shield == 50, "no drain before the delay (1.5s of 2s, shield %d)" % player.shield)
	player.tick_shield_decay(0.5)
	_check(player.shield == 50, "no drain exactly at the delay boundary (shield %d)" % player.shield)
	player.tick_shield_decay(0.25)
	_check(player.shield == 48, "gradual drain after the delay: 0.25s @10/s = -2 (shield %d)" % player.shield)
	player.tick_shield_decay(0.25)
	_check(player.shield == 45, "drain carries fractions: 0.5s total = -5 (shield %d)" % player.shield)
	await process_frame
	_check(bar.visible and label.text == "45", "HUD label tracks the draining value (got '%s')" % label.text)
	_check(player.hp == hp_before, "decay never touches HP")

	# New grant mid-drain refreshes the delay for the whole pool.
	player.add_shield(10)
	_check(player.shield == 55 and is_equal_approx(player.shield_decay_delay_left(), 2.0), "new grant refreshes the pooled delay (shield %d, delay %.2f)" % [player.shield, player.shield_decay_delay_left()])
	player.tick_shield_decay(1.5)
	player.tick_shield_decay(0.5)
	_check(player.shield == 55, "refreshed pool holds again for the full delay (shield %d)" % player.shield)
	# Grant during the delay also restarts it.
	player.add_shield(5)
	player.tick_shield_decay(1.5)
	_check(player.shield == 60 and is_equal_approx(player.shield_decay_delay_left(), 0.5), "grant during the delay restarts it (delay %.2f)" % player.shield_decay_delay_left())
	player.add_shield(1)
	_check(is_equal_approx(player.shield_decay_delay_left(), 2.0), "second grant resets 0.5s left back to 2s")

	# Damage during the clock consumes shield but does not refresh the delay.
	player.tick_shield_decay(1.0)
	player.apply_damage(11)
	_check(player.shield == 50 and player.hp == hp_before, "damage during the delay drains shield first (shield %d)" % player.shield)
	_check(is_equal_approx(player.shield_decay_delay_left(), 1.0), "damage does not refresh the delay clock (%.2f)" % player.shield_decay_delay_left())
	player.tick_shield_decay(1.0)
	_check(player.shield == 50, "no drain until the original delay ends")
	player.tick_shield_decay(0.5)
	_check(player.shield == 45, "decay starts on the original schedule (shield %d)" % player.shield)
	# Damage while draining: shield still absorbs first, overflow reaches HP.
	player.apply_damage(50)
	_check(player.shield == 0 and player.hp == hp_before - 5, "overflow while draining reaches HP (hp %d)" % player.hp)
	player.heal(5)

	# Eventual zero hides the HUD bar.
	player.add_shield(30)
	player.tick_shield_decay(100.0)
	await process_frame
	_check(player.shield == 0 and not bar.visible, "decay ends at exactly 0 and the bar hides")
	player.tick_shield_decay(1.0)
	_check(player.shield == 0, "decay never goes negative")

	# Rate is configurable: 0 disables drain.
	player.shield_decay_rate = 0.0
	player.add_shield(20)
	player.tick_shield_decay(50.0)
	_check(player.shield == 20, "shield_decay_rate 0 disables decay")
	player.clear_shield()

	# Real-time wiring: _physics_process drives the clock.
	player.shield_decay_delay = 0.25
	player.shield_decay_rate = 200.0
	player.set_physics_process(true)
	player.add_shield(40)
	await physics_frame
	_check(player.shield == 40, "live: no drain in the first frame")
	for i in 90:
		await physics_frame
		if player.shield == 0:
			break
	await process_frame
	_check(player.shield == 0 and not bar.visible, "live: _physics_process decays to 0 and hides the bar")
	player.shield_decay_delay = 3.0
	player.shield_decay_rate = 10.0

	# Death: lethal hit through a shield, then no grants while dead.
	player.add_shield(10)
	player.apply_damage(player.hp + 10)
	_check(player.hp == 0 and player.shield == 0, "lethal overflow kills through the shield")
	player.add_shield(10)
	_check(player.shield == 0, "no shield granted while dead")

	await process_frame
	_check(grid.global_position.y == grid_y0, "layout returns to normal with no shield")

	print("[388] RESULT: ", "ALL PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(1 if failures > 0 else 0)
