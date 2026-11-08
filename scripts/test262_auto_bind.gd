extends SceneTree
## #262 harness: auto-bind picked-up spells to slots 1-6.
##
## COMMITTED NOW (policy-neutral): the EXISTING default loadout proof Daniel
## asked to preserve - Fire Ball on slot 1, Mana Shot on slot 2, slots 3-6
## empty at boot. These assertions pass on unmodified main and must keep
## passing after the #262 change lands.
##
## PENDING Daniel's policy confirmation (not asserted yet): first-free slot
## selection for a new pickup, full-slots-keeps-unlock with no overwrite,
## reward-drop and shop grant paths binding through the same funnel.
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
			# Main._ready (hub load + slot seeding) runs on the first frame.
			if scene.current_area == null:
				return false
			phase = 1; t = 0
		1:
			if t > 0.3:
				var caster: SpellCaster = scene.get_node("Player/SpellCaster")
				var slots := caster.get_slots()
				if slots.size() != SpellCaster.SLOT_COUNT:
					print("[262] FAIL slot count: ", slots.size()); ok = false
				if slots[0] == null or slots[0].spell_name != "Fire Ball":
					print("[262] FAIL default slot 1 is not Fire Ball: ", slots[0]); ok = false
				else:
					print("[262] default slot 1 = Fire Ball -> PASS")
				if slots[1] == null or slots[1].spell_name != "Mana Shot":
					print("[262] FAIL default slot 2 is not Mana Shot: ", slots[1]); ok = false
				else:
					print("[262] default slot 2 = Mana Shot -> PASS")
				var rest_empty := true
				for i in range(2, slots.size()):
					if slots[i] != null:
						rest_empty = false
				if not rest_empty:
					print("[262] FAIL slots 3-6 not empty at boot"); ok = false
				else:
					print("[262] slots 3-6 empty at boot -> PASS")
				print("[262] RESULT: ", "ALL PASS" if ok else "FAILURES")
				quit(0 if ok else 1)
	return not ok
