extends GangTest
## #516 self-check fixture: failing checks exit 1 with NO engine/script
## error. Pins the eq type guard: every == pair that would raise a
## runtime SCRIPT ERROR (or surprise, like NaN) is a plain recorded FAIL
## instead, with errors staying 0.

func run() -> void:
	check(true, "passing check")
	check(false, "failing check")
	eq(failures, 1, "failure counter moved")
	eq(1, "1", "int vs String is an incomparable-types failure, not an error")
	eq(Vector2.ONE, Vector3.ONE, "Vector2 vs Vector3 is an incomparable-types failure, not an error")
	var n: Node = Node.new()
	eq(n, 1, "Object vs int is an incomparable-types failure, not an error")
	n.free()
	eq(true, 1, "bool vs int is an incomparable-types failure, not an error")
	eq(NAN, NAN, "NaN never equals itself: a plain failure, not an error")
	eq(null, 5, "nil vs value compares false, not an error")
