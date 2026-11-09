extends SceneTree
## #130 (foundation C3) harness: Consumable definition data + the
## Consumables carried manager (add/count/try_use, carried_changed) with the
## CONSUMPTION-SAFETY contract - try_use decrements ONLY after the effect
## handler returns true; unknown hooks and refused effects consume NOTHING.
## Plus the ReviveSatchel regression legs (auto-revive path UNTOUCHED).
## Shop-dispatch legs land with the shop.gd window once the boundary
## reconcile settles (held paths: shop.gd / shop_panel.gd).

var failures := 0
var check_count := 0
var bag: Consumables
var potion: Consumable
var emissions: Array = []

func _check(cond: bool, name: String) -> void:
	check_count += 1
	if cond:
		print("[130] ", name, " -> PASS")
	else:
		failures += 1
		print("[130] ", name, " -> FAIL")

## Stub player idiom from test129 (test93): real typed Player with the
## children its @onready lookups need BEFORE tree entry.
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
	root.add_child(p)
	return p

func _make_bag(_p: Player) -> Consumables:
	bag = Consumables.new()
	# Explicit path BEFORE tree entry (production convention): root/StubPlayer
	# and root/Consumables are siblings.
	bag.player_path = NodePath("../StubPlayer")
	root.add_child(bag)
	bag.carried_changed.connect(func(c, n): emissions.append([c, n]))
	return bag

var _legs_ran := false

## MainLoop._process true = QUIT: return false always; only _done() quits.
func _process(_delta: float) -> bool:
	if _legs_ran:
		return false
	_legs_ran = true
	_run_legs()
	return false

func _run_legs() -> void:
	## 1. Definition data: defaults + field round-trip. No real content.
	var blank := Consumable.new()
	_check(blank.consumable_name == "Consumable", "definition default name")
	_check(blank.effect_hook == &"", "definition default empty hook")
	potion = Consumable.new()
	potion.consumable_name = "Test Potion"
	potion.effect_hook = &"test_heal"
	_check(potion.consumable_name == "Test Potion" and potion.effect_hook == &"test_heal", "definition fields round-trip")

	var p := _make_player()
	_make_bag(p)
	_check(bag._player == p, "manager player_path resolved to the stub player")

	## 2. add/count + carried_changed emissions.
	bag.add(potion)
	_check(bag.count(potion) == 1, "add one -> count 1")
	bag.add(potion)
	_check(bag.count(potion) == 2, "add again -> count 2 (repeat purchases accrue)")
	_check(emissions == [[potion, 1], [potion, 2]], "carried_changed emitted [1] then [2]")

	## 3. add guards: null consumable / non-positive amount are no-ops.
	bag.add(null)
	bag.add(potion, 0)
	_check(bag.count(potion) == 2 and emissions.size() == 2, "null/zero add are no-ops")

	## 4. try_use on empty: false, nothing emitted.
	var other := Consumable.new()
	other.effect_hook = &"test_heal"
	_check(not bag.try_use(other), "try_use with none carried refuses")
	_check(emissions.size() == 2, "empty try_use emits nothing")

	## 5. UNKNOWN hook: refuse WITHOUT consuming (no handler registered yet).
	_check(not bag.try_use(potion), "unknown hook refuses the use")
	_check(bag.count(potion) == 2, "unknown hook consumes NOTHING (count still 2)")
	_check(emissions.size() == 2, "unknown hook emits nothing")

	## 6. REFUSED effect: handler returns false -> consume nothing.
	var refused_calls: Array = []
	bag.register_effect(&"test_heal", func(_pl): refused_calls.append(true); return false)
	_check(not bag.try_use(potion), "refused effect returns false")
	_check(refused_calls.size() == 1, "refused handler was invoked once")
	_check(bag.count(potion) == 2, "refused effect consumes NOTHING (count still 2)")
	_check(emissions.size() == 2, "refused effect emits nothing")

	## 7. SUCCESS effect: handler true -> decrement, emission, player passed.
	var seen_players: Array = []
	bag.register_effect(&"test_heal", func(pl): seen_players.append(pl); return true)
	_check(bag.try_use(potion), "successful effect uses the consumable")
	_check(bag.count(potion) == 1, "success decrements exactly one (2 -> 1)")
	_check(emissions.size() == 3 and emissions[2] == [potion, 1], "success emits the new count")
	_check(seen_players == [p], "effect handler received the wired player")

	## 8. Drain to zero, then refuse again.
	_check(bag.try_use(potion), "second success use")
	_check(bag.count(potion) == 0, "count drained to zero")
	_check(not bag.try_use(potion), "try_use at zero refuses again")
	_check(seen_players.size() == 2, "handler ran exactly twice across successes")

	## 9. Independent hooks: a second definition with its own hook.
	var bomb := Consumable.new()
	bomb.effect_hook = &"test_bomb"
	bag.add(bomb)
	_check(bag.count(bomb) == 1 and bag.count(potion) == 0, "counts tracked per definition")
	_check(not bag.try_use(bomb), "second definition's unregistered hook refuses unconsumed")

	## 10. ReviveSatchel regression (auto-revive path untouched).
	var satchel := ReviveSatchel.new()
	satchel.player_path = NodePath("../StubPlayer")
	root.add_child(satchel)
	var collected: Array = []
	var used: Array = []
	satchel.revive_collected.connect(func(n): collected.append(n))
	satchel.revive_used.connect(func(rem, hp): used.append([rem, hp]))
	p.apply_damage(100)
	_check(p.hp == 0, "stub player at 0 hp for the revive leg")
	_check(not satchel.try_revive(), "empty satchel refuses revive")
	satchel.collect()
	_check(satchel.carried == 1 and collected == [1], "satchel collect -> carried 1 + signal")
	_check(satchel.try_revive(), "satchel try_revive succeeds")
	_check(p.hp == 50, "revive healed exactly revive_hp (0 -> 50)")
	_check(satchel.carried == 0 and used == [[0, 50]], "revive consumed one + revive_used signal")
	_check(not satchel.try_revive(), "second revive refuses with nothing carried")

	## 11. The two carried systems stay independent.
	bag.add(potion)
	_check(bag.count(potion) == 1 and satchel.carried == 0, "bag and satchel counts independent")

	## 12. Dedicated key with SEVERAL types carried: refuse (selection
	## mechanic is an open human decision), even with both handlers ready.
	var bomb_used := [0]
	bag.register_effect(&"test_bomb", func(_pl): bomb_used[0] += 1; return true)
	_check(not bag.try_use_dedicated_key(), "dedicated key refuses ambiguous multi-type carry")
	_check(bag.count(potion) == 1 and bag.count(bomb) == 1, "ambiguity refusal consumes nothing")
	_check(bomb_used[0] == 0 and emissions.size() == 6, "ambiguity refusal runs no handler, emits nothing")

	## 13. Drain the bomb; exactly one type remains.
	_check(bag.try_use(bomb), "direct try_use of the bomb succeeds")
	_check(bag.count(bomb) == 0, "bomb drained")

	## 14. Dedicated key with EXACTLY ONE type carried: uses it.
	_check(bag.try_use_dedicated_key(), "dedicated key uses the single carried type")
	_check(bag.count(potion) == 0, "dedicated key consumed one potion")
	_check(emissions.size() == 8 and emissions[7] == [potion, 0], "dedicated-key use emitted the decrement")

	## 15. Dedicated key with nothing carried: refuse.
	_check(not bag.try_use_dedicated_key(), "dedicated key refuses with empty bag")

	## 16. use_consumable action registered at runtime on the E key.
	_check(InputMap.has_action(&"use_consumable"), "use_consumable action registered")
	var bound_e := false
	for ev in InputMap.action_get_events(&"use_consumable"):
		if ev is InputEventKey and ev.physical_keycode == KEY_C:
			bound_e = true
	_check(bound_e, "use_consumable bound to physical KEY_C (#319: E is now spell slot 4)")

	_done()

func _done() -> bool:
	print("[130] checks=", check_count)
	if failures == 0:
		print("[130] PASS")
	else:
		print("[130] DONE failures=", failures)
	quit(0 if failures == 0 else 1)
	return true
