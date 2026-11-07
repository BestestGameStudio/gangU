extends Node2D
## #6 EVIDENCE driver (test-only). Proves: death restarts the run, collected
## spells reset to the starting spell only, restart is repeatable, no leftover
## state. GANGU_AUTOTEST=1 prints diagnostics for headless evidence.

static var run_count := 0

@onready var debug: Label = $DebugLabel
var _status := ""

func _ready() -> void:
	run_count += 1
	var p = get_tree().get_first_node_in_group("player")
	var caster = p.get_node_or_null("SpellCaster")
	var spells: int = -1 if caster == null else caster.spells.size()
	print("[run] start run=", run_count, " hp=", p.hp, " enemies=", get_tree().get_nodes_in_group("enemies").size(), " spells=", spells)
	if run_count == 1 and caster != null:
		var picked := Spell.new()
		picked.spell_name = "PickedUpTestSpell"
		caster.add_spell(picked)
		print("[run] collected extra spell, spells=", caster.spells.size())
	p.died.connect(func(): print("[run] died, restart pending"); _status = "died, restarting")
	var rm := $RunManager
	rm.run_restarting.connect(func(): print("[run] run_restarting emitted"))
	if OS.get_environment("GANGU_AUTOTEST") == "1":
		get_tree().create_timer(20.0).timeout.connect(func(): get_tree().quit())

func _process(_delta: float) -> void:
	var p = get_tree().get_first_node_in_group("player")
	var caster = p.get_node_or_null("SpellCaster")
	var spells: int = -1 if caster == null else caster.spells.size()
	debug.text = "run " + str(run_count) + " | hp " + str(p.hp) + " | spells " + str(spells) + " | " + _status
