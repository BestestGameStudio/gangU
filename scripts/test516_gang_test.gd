extends SceneTree
## #516 PARTIAL A self-check: pins the GangTest contract by running four
## fixture harnesses (tests/support/fixtures/) as real subprocesses and
## asserting the runner-facing contract: exit 0 = pass, 1 = failed check
## or engine/script error or zero checks, 2 = watchdog, with the matching
## summary lines. The hang fixture runs in two modes: a plain hang, and a
## hang under Engine.time_scale = 0 (the watchdog runs on wall clock, so
## paused time cannot suppress it). GangTest's own harness contract is "exit 0 before the
## timeout means PASS" - no output parsing by runners; the output
## assertions here are this self-check's business. The error fixture is
## run in three modes via user args: a runtime error before the first
## await, mid-run after awaits (both were false passes before the
## fail-closed logger repair), and a harness that records no checks.

var failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("[516] ", label, " -> PASS")
	else:
		failures += 1
		print("[516] ", label, " -> FAIL")

func _run_fixture(path: String, mode: String = "") -> Dictionary:
	var args: Array = [
		"--headless", "--fixed-fps", "60",
		"--path", ProjectSettings.globalize_path("res://"),
		"-s", path]
	if mode != "":
		args += ["--", mode]
	var out: Array = []
	var code: int = OS.execute(OS.get_executable_path(), args, out, true, true)
	return {"code": code, "text": "\n".join(out)}

func _init() -> void:
	var base_script: Resource = load("res://tests/support/gang_test.gd")
	_check(base_script != null, "gang_test.gd loads from tests/support")

	var passed: Dictionary = _run_fixture("res://tests/support/fixtures/pass_harness.gd")
	var pass_code: int = passed.code
	_check(pass_code == 0, "pass fixture exits 0 (got %d)" % pass_code)
	_check("DONE failures=0 errors=0" in str(passed.text), "pass fixture prints DONE failures=0 errors=0")
	_check("boot_main instances the main scene -> PASS" in str(passed.text), "boot_main works in a harness")
	_check("frames awaits real physics frames" in str(passed.text), "frames works in a harness")
	_check("until held -> PASS" in str(passed.text), "until works in a harness")

	var failed: Dictionary = _run_fixture("res://tests/support/fixtures/fail_harness.gd")
	var fail_code: int = failed.code
	_check(fail_code == 1, "fail fixture exits 1 (got %d)" % fail_code)
	_check("DONE failures=7 errors=0" in str(failed.text), "fail fixture prints DONE failures=7 errors=0")
	_check("failing check -> FAIL" in str(failed.text), "failing check is reported")
	_check("incomparable types" in str(failed.text), "eq type guard reports incomparable types")
	_check(not ("SCRIPT ERROR" in str(failed.text)), "fail fixture raises no script error")

	var error_path: String = "res://tests/support/fixtures/error_harness.gd"
	var error_before: Dictionary = _run_fixture(error_path, "before")
	var before_code: int = error_before.code
	_check(before_code == 1, "error fixture (before first await) exits 1 (got %d)" % before_code)
	_check("DONE failures=0 errors=1 checks=1" in str(error_before.text), "error fixture (before) counts the script error")
	_check("SCRIPT ERROR" in str(error_before.text), "error fixture (before) really raised a script error")

	var error_after: Dictionary = _run_fixture(error_path, "after")
	var after_code: int = error_after.code
	_check(after_code == 1, "error fixture (mid-run, after awaits) exits 1 (got %d)" % after_code)
	_check("DONE failures=0 errors=1 checks=1" in str(error_after.text), "error fixture (after) counts the script error")
	_check("SCRIPT ERROR" in str(error_after.text), "error fixture (after) really raised a script error")

	var error_zero: Dictionary = _run_fixture(error_path, "zero")
	var zero_code: int = error_zero.code
	_check(zero_code == 1, "error fixture (zero checks) exits 1 (got %d)" % zero_code)
	_check("DONE failures=0 errors=0 checks=0" in str(error_zero.text), "zero-check guard reports checks=0")
	_check(not ("SCRIPT ERROR" in str(error_zero.text)), "zero mode raises no script error")

	var hung: Dictionary = _run_fixture("res://tests/support/fixtures/hang_harness.gd")
	var hang_code: int = hung.code
	_check(hang_code == 2, "hang fixture exits 2 via watchdog (got %d)" % hang_code)
	_check("TIMEOUT" in str(hung.text), "watchdog prints TIMEOUT")

	var paused: Dictionary = _run_fixture("res://tests/support/fixtures/hang_harness.gd", "paused")
	var paused_code: int = paused.code
	_check(paused_code == 2, "paused hang fixture exits 2 via watchdog (got %d)" % paused_code)
	_check("TIMEOUT" in str(paused.text), "watchdog fires under time_scale 0")

	print("[516] DONE failures=", failures)
	quit(1 if failures > 0 else 0)
