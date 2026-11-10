extends GangTest
## #516 self-check fixture: a GDScript runtime error must fail closed.
## Mode via user arg (-s error_harness.gd -- <mode>):
##   before (default) - error before the first await;
##   after            - error after awaits, mid-run;
##   zero             - no checks at all (zero-check guard).
## Error modes exit 1 with errors=1; zero exits 1 via the zero-check
## guard. Without the ErrorCounter logger both error modes used to be
## false passes: the error aborts run(), the caller continues, and the
## old base quit 0 with failures=0.

func run() -> void:
	var mode: String = "before"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	if mode == "zero":
		return
	check(true, "passing check before the error")
	if mode == "after":
		await frames(2)
	# Runtime SCRIPT ERROR (error_type 2): property access on Nil.
	var broken: Variant = null
	var _boom: Variant = broken.anything
