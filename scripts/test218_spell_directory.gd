extends SceneTree
## #218 harness: hub spell directory - a walk-up LOCATION (ShopVendor
## idiom) whose panel READ-ONLY lists the caster's current-run unlocked
## spells (get_unlocked, #60), live-refreshed on spell_unlocked, closing
## on walk-away. Read-only contract: no unlock/equip/wallet mutation.

var failures := 0
var check_count := 0
var caster: SpellCaster
var panel: SpellDirectoryPanel
var directory: SpellDirectory
var fireball: Spell = preload("res://resources/spells/fire_ball.tres")
var mana: Spell = preload("res://resources/spells/mana_shot.tres")
var bolt: Spell = preload("res://resources/spells/placeholder_bolt.tres")

func _check(cond: bool, name: String) -> void:
	check_count += 1
	if cond:
		print("[218] ", name, " -> PASS")
	else:
		failures += 1
		print("[218] ", name, " -> FAIL")

## Stub player: real typed Player + real SpellCaster child, no gameplay
## wiring, so the panel's group lookup and `body is Player` checks work
## (test129 stub idiom).
func _make_player() -> Player:
	var p := Player.new()
	p.name = "StubPlayer"
	p.set_process(false)
	p.set_physics_process(false)
	var aim := Node2D.new()
	aim.name = "AimIndicator"
	p.add_child(aim)
	var bod := Polygon2D.new()
	bod.name = "Body"
	p.add_child(bod)
	var nose := Polygon2D.new()
	nose.name = "NoseEdge"
	p.add_child(nose)
	caster = SpellCaster.new()
	caster.name = "SpellCaster"
	p.add_child(caster)
	p.add_to_group("player")
	root.add_child(p)
	return p

func _rows() -> VBoxContainer:
	return panel.get_node("Backdrop/Margin/VBox/Scroll/Rows") as VBoxContainer

func _row_named(spell_name: String) -> Control:
	for row in _rows().get_children():
		var label := row.find_children("NameLabel", "Label", true, false)
		if not label.is_empty() and label[0].text == spell_name:
			return row
	return null

var _legs_ran := false

func _process(_delta: float) -> bool:
	if _legs_ran:
		return false
	_legs_ran = true
	_run_legs()
	quit(1 if failures > 0 else 0)
	return false

func _run_legs() -> void:
	print("test218: hub spell directory (#218)")
	var p := _make_player()
	directory = preload("res://scenes/spell_directory.tscn").instantiate()
	root.add_child(directory)
	panel = preload("res://scenes/spell_directory_panel.tscn").instantiate()
	root.add_child(panel)

	var wallet := CurrencyWallet.new()
	root.add_child(wallet)
	wallet.add(25)
	panel.open(caster)
	_check(_rows().get_node_or_null("EmptyLabel") != null, "empty inventory displays an honest empty state")
	panel.close()

	## 1. Panel: hidden by default, outside modal_ui.
	_check(not panel.visible, "panel hidden by default")
	_check(not panel.is_in_group("modal_ui"), "panel not modal while hidden")

	## 2. Walk-up opens; rows list exactly the current unlock set.
	caster.unlock_spell(fireball)
	caster.unlock_spell(bolt)
	# #262: both grants auto-bind on arrival now; snapshot the actual slots
	# AFTER the grants, BEFORE the walk-up, so the read-only check below
	# still proves opening/rendering changed nothing.
	var slots_before_open := caster.get_slots()
	directory._on_body_entered(p)
	_check(panel.visible and panel.is_in_group("modal_ui"), "walk-up opens panel (visible + modal_ui)")
	_check(_rows().get_child_count() == 2, "one row per unlocked spell (2)")
	_check(_row_named("Fire Ball") != null and _row_named("Placeholder Bolt") != null, "rows named for both unlocked spells")
	_check(_row_named("Mana Shot") == null, "locked spell has no row")
	_check(panel.get_node("Backdrop/Margin/VBox/CountLabel").text == "2 spell(s) unlocked this run", "count label matches unlock set")

	## 3. READ-ONLY: opening/rendering changed nothing.
	_check(caster.get_unlocked() == [fireball, bolt], "read-only: unlock inventory untouched")
	_check(caster.get_slots() == slots_before_open, "read-only: equip slots untouched")

	## 4. Live refresh: a new unlock while open adds a row.
	caster.unlock_spell(mana)
	_check(_rows().get_child_count() == 3, "spell_unlocked live-refreshes the open panel (3 rows)")
	_check(_row_named("Mana Shot") != null, "new unlock row rendered by name")

	var split: Spell = preload("res://resources/spells/fire_ball_split.tres")
	_check(caster.replace_spell(fireball, split), "real upgrade replacement accepted")
	_check(_row_named("Fire Ball") == null and _row_named(split.spell_name) != null, "spell_replaced refreshes current inventory, no stale base spell")
	_check(wallet.balance() == 25, "read-only: wallet unchanged")

	## 5. Walk-away closes; a later unlock does not resurrect it.
	directory._on_body_exited(p)
	_check(not panel.visible and not panel.is_in_group("modal_ui"), "walk-away closes panel")
	caster.unlock_spell(preload("res://resources/spells/fire_ball_split.tres"))
	_check(not panel.visible, "unlock while closed stays closed")

	## 6. Non-player bodies do not open it.
	var stranger := Node2D.new()
	root.add_child(stranger)
	directory._on_body_entered(stranger)
	_check(not panel.visible, "non-player body does not open the panel")

	## 7. Reopen reflects the grown unlock set (4 spells).
	directory._on_body_entered(p)
	_check(panel.visible and _rows().get_child_count() == 4, "reopen renders the current unlock set (4 rows)")
	directory._on_body_exited(p)

	## 8. PRODUCTION composition (real player.tscn, NOT in the "player"
	## group - the group is a test-only idiom): the panel's group fallback
	## finds no caster, so the walk-up body must hand its caster over.
	p.queue_free()
	stranger.queue_free()
	panel.close()
	var real_player: Player = preload("res://scenes/player.tscn").instantiate()
	real_player.name = "RealPlayer"
	root.add_child(real_player)
	_check(not real_player.is_in_group("player"), "real player.tscn is NOT in the player group (production fact)")
	var real_caster: SpellCaster = real_player.get_node("SpellCaster")
	_check(real_caster != null and real_caster.get_unlocked().size() >= 2, "real player starts with its scene starting spells")
	directory._on_body_entered(real_player)
	_check(panel.visible, "production walk-up opens the panel")
	_check(_row_named("Fire Ball") != null and _row_named("Mana Shot") != null, "production rows come from the real caster, not the group")
	directory._on_body_exited(real_player)
	_check(not panel.visible, "production walk-away closes")

	for i in range(20):
		var extra := Spell.new()
		extra.spell_name = "Extra %d" % i
		real_caster.unlock_spell(extra)
	directory._on_body_entered(real_player)
	_check(_rows().get_child_count() == real_caster.get_unlocked().size(), "large inventory lists ALL unlocked spells")
	_check(_rows().get_parent() is ScrollContainer, "large listing has scroll access, not clipped overflow")
	_check(_rows().find_children("*", "Button", true, false).is_empty(), "directory has no purchase/equip/grant buttons")
	directory._on_body_exited(real_player)

	print("test218 done: %d checks, %d failures" % [check_count, failures])

func _done() -> bool:
	return true
