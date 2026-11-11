extends SceneTree
## #262 harness: auto-bind picked-up spells to slots 1-6.
## Policy settled by Daniel (2026-11-08): "yes first empty slots, and without
## replacement" - a new grant binds the FIRST EMPTY slot; when all six slots
## are occupied the spell still unlocks and no existing binding is replaced.
##
## Coverage:
##   1. Boot defaults preserved: Fire Ball slot 1, Mana Shot slot 2, 3-6 empty.
##   2. Walk-over SpellPickup binds the first empty slot.
##   3. Enemy RewardDrop spell grant binds the first empty slot (same funnel).
##   4. Full slots: grant stays unlock-only, every existing binding untouched.
##   5. Duplicate grant keeps its existing slot (no double-bind).
##   6. A cleared slot is the next first-empty target for a later grant.
var scene: Node
var p: Player
var caster: SpellCaster
var phase := 0
var t := 0.0
var ok := true

var bolt: Spell = load("res://resources/spells/placeholder_bolt.tres")
var summon: Spell = load("res://resources/spells/summon_ally.tres")
var head_bolt: Spell = load("res://resources/spells/head_bolt.tres")
var warlord_orb: Spell = load("res://resources/spells/warlord_orb.tres")
var lance: Spell = load("res://resources/spells/mana_shot_lance.tres")
var beam: Spell = load("res://resources/spells/fire_ball_beam.tres")

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")
	caster = p.get_node("SpellCaster")

func _fail(msg: String, extra: Variant = null) -> void:
	print("[262] FAIL ", msg, "" if extra == null else str(": ", extra))
	ok = false

func _pass(msg: String) -> void:
	print("[262] ", msg, " -> PASS")

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			# Main._ready (hub load + slot seeding) runs on the first frame.
			if scene.area_loader.current_area == null:
				return false
			phase = 1; t = 0
		1:
			if t > 0.3:
				var slots := caster.get_slots()
				if slots.size() != SpellCaster.SLOT_COUNT:
					_fail("slot count", slots.size())
				if slots[0] == null or slots[0].spell_name != "Fire Ball":
					_fail("default slot 1 is not Fire Ball", slots[0])
				else:
					_pass("default slot 1 = Fire Ball")
				if slots[1] == null or slots[1].spell_name != "Mana Shot":
					_fail("default slot 2 is not Mana Shot", slots[1])
				else:
					_pass("default slot 2 = Mana Shot")
				var rest_empty := true
				for i in range(2, slots.size()):
					if slots[i] != null:
						rest_empty = false
				if not rest_empty:
					_fail("slots 3-6 not empty at boot")
				else:
					_pass("slots 3-6 empty at boot")
				phase = 2; t = 0
		2:
			# Walk-over pickup (SpellPickup -> add_spell) binds first empty.
			var pickup: SpellPickup = load("res://scenes/spell_pickup.tscn").instantiate()
			pickup.spell_path = "res://resources/spells/placeholder_bolt.tres"
			scene.area_loader.current_area.add_child(pickup)
			pickup._on_body_entered(p)
			if caster.get_slots()[2] == bolt:
				_pass("walk-over pickup binds first empty slot (3)")
			else:
				_fail("pickup not bound to slot 3", caster.get_slots()[2])
			phase = 3; t = 0
		3:
			# Enemy reward drop (RewardDrop -> unlock_spell) binds first empty.
			var entry := RewardEntry.new()
			entry.kind = RewardEntry.Kind.SPELL
			entry.spell = summon
			var drop: RewardDrop = load("res://scenes/reward_drop.tscn").instantiate()
			drop.setup(entry)
			scene.area_loader.current_area.add_child(drop)
			drop._on_body_entered(p)
			if caster.get_slots()[3] == summon:
				_pass("reward-drop spell binds first empty slot (4)")
			else:
				_fail("reward drop not bound to slot 4", caster.get_slots()[3])
			phase = 4; t = 0
		4:
			# Fill slots 5-6, then a further grant with all six occupied.
			caster.unlock_spell(head_bolt)
			caster.unlock_spell(warlord_orb)
			var before := caster.get_slots()
			caster.unlock_spell(lance)
			var after := caster.get_slots()
			if not caster.get_unlocked().has(lance):
				_fail("full-slot grant lost the unlock (lance missing)")
			elif after != before:
				_fail("full-slot grant changed existing bindings", after)
			elif after.has(lance):
				_fail("full-slot grant replaced a binding with lance")
			else:
				_pass("full slots: grant stays unlock-only, no binding replaced")
			phase = 5; t = 0
		5:
			# Duplicate grant of an already-slotted spell keeps its slot.
			caster.unlock_spell(bolt)
			var slots := caster.get_slots()
			if slots[2] == bolt and slots.count(bolt) == 1:
				_pass("duplicate grant keeps existing slot, no double-bind")
			else:
				_fail("duplicate grant altered binding", slots)
			phase = 6; t = 0
		6:
			# A cleared slot becomes the next first-empty target.
			if not caster.clear_slot(1):
				_fail("clear_slot(2) refused")
			caster.unlock_spell(beam)
			var slots := caster.get_slots()
			if slots[1] == beam and slots[0].spell_name == "Fire Ball":
				_pass("cleared slot is the next first-empty target; Fire stays slot 1")
			else:
				_fail("grant after clear did not bind slot 2", slots[1])
			print("[262] RESULT: ", "ALL PASS" if ok else "FAILURES")
			quit(0 if ok else 1)
	return not ok
