extends GangTest
## #516 self-check fixture: hangs awaiting a condition that never comes;
## the watchdog must fire and exit 2.

func watchdog_seconds() -> float:
	return 1.0

func run() -> void:
	while true:
		await physics_frame
