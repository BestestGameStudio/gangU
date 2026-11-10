extends GangTest
## #516 self-check fixture: one failing check, exits 1.

func run() -> void:
	check(true, "passing check")
	check(false, "failing check")
	eq(failures, 1, "failure counter moved")
