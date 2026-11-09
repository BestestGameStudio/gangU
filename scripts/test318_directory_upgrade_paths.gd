extends SceneTree
## #318 harness: the hub spell directory shows each unlocked spell's upgrade
## paths. Uses the PRODUCTION main.tscn composition (real SpellProgress with
## the main.gd upgrade list, real SpellDirectoryPanel), opening the panel
## the way the hub directory does. Read-only contract preserved: rendering
## the tree never applies an upgrade or mutates the caster.

var scene: Node
var p: Player
var caster: SpellCaster
var prog: SpellProgress
var panel: SpellDirectoryPanel
var phase := 0
var failures := 0
var checks := 0

var fireball: Spell = load("res://resources/spells/fire_ball.tres")
var mana: Spell = load("res://resources/spells/mana_shot.tres")
var split: Spell = load("res://resources/spells/fire_ball_split.tres")

func _check(cond: bool, name: String) -> void:
	checks += 1
	if cond:
		print("[318] PASS ", name)
	else:
		failures += 1
		print("[318] FAIL ", name)

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene

func _row(spell_name: String) -> Control:
	var rows := panel.get_node("Backdrop/Margin/VBox/Scroll/Rows")
	for row in rows.get_children():
		var l := row.find_children("NameLabel", "Label", true, false)
		if not l.is_empty() and l[0].text == spell_name:
			return row
	return null

func _lines(row: Control) -> Array:
	# Sibling lines share a base name, so Godot auto-renames them; match on
	# the upgrade_id meta the panel stamps on each line instead.
	return row.find_children("*", "HBoxContainer", true, false).filter(func(n): return n.has_meta("upgrade_id"))

func _line(row: Control, id: StringName) -> Control:
	for l in _lines(row):
		if l.get_meta("upgrade_id") == id:
			return l
	return null

func _text(line: Control, label: String) -> String:
	return (line.find_child(label, true, false) as Label).text

func _process(_delta: float) -> bool:
	match phase:
		0:
			if scene.current_area == null:
				return false
			p = scene.get_node("Player")
			caster = p.get_node("SpellCaster")
			prog = scene.get_node("SpellProgress")
			panel = scene.get_node("SpellDirectoryPanel")
			phase = 1
		1:
			_run()
			print("test318 done: %d checks, %d failures" % [checks, failures])
			print("---\n[318] %s" % ("ALL PASS" if failures == 0 else "FAILURES PRESENT"))
			quit(1 if failures > 0 else 0)
			phase = 2
	return false

func _run() -> void:
	var dir_node := scene.current_area.get_node_or_null("SpellDirectory") as SpellDirectory
	_check(dir_node != null, "hub has a spell directory location")
	var directory: Array[SpellDirectory] = [dir_node]
	var unlocked_before := caster.get_unlocked().duplicate()
	var slots_before := caster.get_slots().duplicate()
	directory[0]._on_body_entered(p)
	_check(panel.visible, "walk-up opens the directory")

	## 1. Fire Ball: both Specialization forks at depth 0, every Mastery
	## follow-up nested at depth 1 under them.
	var fb := _row("Fire Ball")
	_check(fb != null, "Fire Ball row present")
	_check(_lines(fb).size() == 8, "Fire Ball shows its full tree (2 Spec + 6 Mastery = 8 lines), got %d" % _lines(fb).size())
	var split_line := _line(fb, &"fireball_split")
	var beam_line := _line(fb, &"fireball_beam")
	_check(split_line != null and beam_line != null, "Split shot and Beam paths listed")
	_check(split_line.get_meta("depth") == 0 and beam_line.get_meta("depth") == 0, "Specialization forks are direct paths (depth 0)")
	_check(_text(split_line, "PathLabel").contains("Split shot") and _text(split_line, "PathLabel").contains("Specialization"), "path label names the upgrade and its tier")
	_check(_text(split_line, "RequirementLabel") == "0/10 casts", "direct path shows live cast progress (0/10)")
	var wide := _line(fb, &"fireball_m2_split_wide")
	_check(wide != null and wide.get_meta("depth") == 1, "Wide split nested under Split shot (depth 1)")
	_check(_text(wide, "PathLabel").contains("Mastery") and _text(wide, "RequirementLabel") == "15 casts", "deeper path shows tier + threshold")
	var order: Array = _lines(fb).map(func(l): return l.get_meta("upgrade_id"))
	_check(order.find(&"fireball_m2_split_wide") == order.find(&"fireball_split") + 1, "Mastery children render directly under their parent fork")
	_check((fb.find_child("TierLabel", true, false) as Label).text == "Base", "row shows the held spell's tier (Base)")

	## 2. Mana Shot: its own two forks, no Fire Ball leakage.
	var ms := _row("Mana Shot")
	_check(ms != null and _lines(ms).size() == 2, "Mana Shot shows exactly its 2 paths")
	_check(_line(ms, &"manashot_volley") != null and _line(ms, &"manashot_lance") != null, "Mana Volley + Mana Lance listed")

	## 3. Read-only: rendering mutated nothing.
	_check(caster.get_unlocked() == unlocked_before and caster.get_slots() == slots_before, "read-only: caster untouched by rendering")
	_check(panel.find_children("*", "Button", true, false).is_empty(), "no upgrade buttons in the directory")

	## 4. Progress reaches READY after enough casts (re-open refreshes).
	for i in 10:
		prog._on_spell_cast(fireball)
	directory[0]._on_body_exited(p)
	directory[0]._on_body_entered(p)
	fb = _row("Fire Ball")
	_check(_text(_line(fb, &"fireball_split"), "RequirementLabel") == "READY", "qualified path reads READY")

	## 5. After an upgrade the row follows the new spell's remaining tree.
	_check(prog.apply_upgrade(fireball, &"fireball_split"), "apply Split shot via the real provider")
	var sr := _row(split.spell_name)
	_check(sr != null and _row("Fire Ball") == null, "row switched to the upgraded spell (live spell_replaced refresh)")
	_check((sr.find_child("TierLabel", true, false) as Label).text == "Specialization", "upgraded row shows Specialization tier")
	_check(_lines(sr).size() == 2 and _line(sr, &"fireball_m2_split_wide").get_meta("depth") == 0, "upgraded row lists only its 2 Mastery paths as direct paths")
	_check(_text(_line(sr, &"fireball_m2_split_wide"), "RequirementLabel") == "0/15 casts", "Mastery progress counted from the new spell")

	## 6. A spell with no configured paths says so.
	var bare := Spell.new()
	bare.spell_name = "Bare Test Spell"
	caster.unlock_spell(bare)
	var br := _row("Bare Test Spell")
	_check(br != null and _lines(br).is_empty() and br.find_child("NoPathsLabel", true, false) != null, "spell without paths shows 'No further upgrades'")
	directory[0]._on_body_exited(p)
	_check(not panel.visible, "walk-away still closes")
