extends SceneTree
## #205 harness: player invincibility window foundation (headless).
## Proves: default OFF, baseline damage unchanged, window ON ignores damage
## (no HP change, no health_changed, no died, lethal included), OFF restores
## damage, heal and death unaffected, and a fresh Player instance starts OFF
## even after another instance left its window open.
## Logic-only harness: no concrete spell exists, so there is no in-game trigger.

var failures := 0
var _changes: Array[int] = []
var _died := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[205] ", name, " -> ", "PASS" if cond else "FAIL")

func _one(v: int) -> bool:
	return _changes.size() == 1 and _changes[0] == v

func _make() -> Player:  # caller awaits one frame so Player._ready sets hp
	var p: Player = load("res://scenes/player.tscn").instantiate()
	root.add_child(p)
	_changes.clear()
	_died = 0
	p.health_changed.connect(func(cur: int, _m: int) -> void: _changes.append(cur))
	p.died.connect(func() -> void: _died += 1)
	return p

func _initialize() -> void:
	var p := _make()
	await process_frame
	_check(not p.is_invulnerable(), "window defaults OFF")
	p.apply_damage(10)
	_check(p.hp == 90 and _one(90), "OFF: apply_damage(10) -> HP 90, one health_changed(90)")

	_changes.clear()
	p.set_invulnerable(true)
	_check(p.is_invulnerable(), "set_invulnerable(true) opens the window")
	p.apply_damage(10)
	_check(p.hp == 90, "ON: apply_damage(10) leaves HP at 90")
	_check(_changes.is_empty(), "ON: no health_changed emitted")
	_check(_died == 0, "ON: no died emitted")
	p.apply_damage(9999)
	_check(p.hp == 90 and _died == 0 and _changes.is_empty(), "ON: lethal damage ignored (HP 90, no died, no signal)")

	p.heal(5)
	_check(p.hp == 95 and _one(95), "ON: heal still works (HP 95, health_changed(95))")

	_changes.clear()
	p.set_invulnerable(false)
	_check(not p.is_invulnerable(), "set_invulnerable(false) closes the window")
	p.apply_damage(10)
	_check(p.hp == 85 and _one(85), "OFF again: damage applies (HP 85, health_changed(85))")

	p.apply_damage(9999)
	_check(p.hp == 0 and _died == 1, "OFF: lethal damage clamps to 0 and emits died once")
	p.set_invulnerable(true)
	p.heal(30)
	_check(p.hp == 30, "heal revives from 0 while window open (heal untouched)")
	p.free()

	# Fresh instance: a window left open on another instance does not leak.
	var a := _make()
	a.set_invulnerable(true)
	var b := _make()
	await process_frame
	_check(not b.is_invulnerable(), "fresh Player instance starts OFF while another instance is ON")
	b.apply_damage(10)
	_check(b.hp == 90, "fresh instance takes damage normally")
	a.free()
	b.free()

	print("[205] failures: ", failures)
	quit(1 if failures > 0 else 0)
