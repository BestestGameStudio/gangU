extends SceneTree
## #528 harness: Bestiary legacy/malformed save compatibility (#518/#527
## regression check). Hand-edited or legacy bestiary.cfg files can hold
## non-int counts; the pre-#527 loader coerced them with int(). The loader
## must keep coercing ("3"->3, "abc"->0, 2.7->2, true->1) and must keep
## rejecting non-scalar values loudly (script error, load aborts) rather
## than silently zeroing the record.

const TEST_SAVE := "user://test528_bestiary_legacy.cfg"

var failures := 0
var check_count := 0

func _check(cond: bool, name: String) -> void:
	check_count += 1
	if cond:
		print("[528] ", name, " -> PASS")
	else:
		failures += 1
		print("[528] ", name, " -> FAIL")

func _write_save(text: String) -> void:
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("test528: bestiary legacy save compatibility (#528)")
	Bestiary.save_path = TEST_SAVE

	## 1. Legacy scalar shapes coerce exactly like the pre-#527 int() loader.
	_write_save("[encountered]\n\nzombie=\"3\"\nskeleton=\"abc\"\nghost=2.7\nbat=true\nslime=5\n")
	Bestiary.reload_from_disk()
	_check(Bestiary.encounter_count(&"zombie") == 3, "string number coerces (\"3\" -> 3)")
	_check(Bestiary.encounter_count(&"skeleton") == 0 and not Bestiary.has_seen(&"skeleton"), "garbage string coerces to 0")
	_check(Bestiary.encounter_count(&"ghost") == 2, "float count truncates (2.7 -> 2)")
	_check(Bestiary.encounter_count(&"bat") == 1, "bool count coerces (true -> 1)")
	_check(Bestiary.encounter_count(&"slime") == 5, "plain int loads")
	_check(Bestiary.seen_count() == 4, "seen_count counts coerced entries")
	Bestiary.record(&"slime")
	_check(Bestiary.encounter_count(&"slime") == 6, "record() still increments the coerced record")

	## 2. Non-scalar values keep failing loudly, as base int() did: the
	##    script error aborts _ensure_loaded, so later valid keys stay
	##    unloaded too (parity assertion, not a new behavior).
	print("[528] note: the next load logs one SCRIPT ERROR on purpose (base parity)")
	_write_save("[encountered]\n\nzombie=[1]\nslime=5\n")
	Bestiary.reload_from_disk()
	_check(Bestiary.encounter_count(&"zombie") == 0, "non-scalar value rejected, not silently kept")
	_check(Bestiary.encounter_count(&"slime") == 0, "load aborts on rejection, as base did")

	Bestiary.clear()
	Bestiary.save_path = Bestiary.DEFAULT_SAVE_PATH
	print("test528 done: %d checks, %d failures" % [check_count, failures])
	print("RESULT: ALL PASS" if failures == 0 else "RESULT: FAIL")
	quit(1 if failures > 0 else 0)
