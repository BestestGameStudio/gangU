extends GangTest
## #516 self-check fixture: hangs awaiting a condition that never comes;
## the watchdog must fire and exit 2.
## Mode via user arg (-s hang_harness.gd -- <mode>):
##   (default) - plain hang under normal time scale;
##   paused    - Engine.time_scale = 0: the watchdog must still fire on
##               wall clock, independent of the paused scene tree.

func watchdog_seconds() -> float:
	return 1.0

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] == "paused":
		Engine.time_scale = 0.0
	while true:
		await process_frame
