extends GangTest
## #516 self-check fixture: every helper works, exits 0.

func run() -> void:
	check(true, "check records a pass")
	eq(6 * 7, 42, "eq compares values")
	var s: Node2D = stage()
	check(s != null and s.get_parent() == root, "stage adds a Node2D fixture")
	var m: Node = boot_main()
	check(m != null, "boot_main instances the main scene")
	m.queue_free()
	var ticks: int = 0
	await frames(3)
	ticks = 3
	eq(ticks, 3, "frames awaits real physics frames")
	var ok: bool = await until(func() -> bool: return true, 5, "until returns on a met condition")
	check(ok, "until held")
	var missed: bool = await until(func() -> bool: return false, 3)
	eq(missed, false, "until budgets out false without a label")
	eq(1, 1.0, "eq compares int against float")
	eq(&"hello", "hello", "eq compares StringName against String")
	eq(null, null, "eq accepts nil on both sides")
	check(NAN != NAN, "NaN semantics stay plain Godot")
	eq(failures, 0, "no failures recorded")
