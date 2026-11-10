extends SceneTree
## #516 PARTIAL A self-check: pins the GangTest contract by running three
## fixture harnesses (tests/support/fixtures/) as real subprocesses and
## asserting the runner-facing contract: exit 0 = pass, 1 = failed check,
## 2 = watchdog, with the matching summary lines. GangTest's own harness
## contract is "exit 0 before the timeout means PASS" - no output parsing
## by runners; the output assertions here are this self-check's business.

var failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("[516] ", label, " -> PASS")
	else:
		failures += 1
		print("[516] ", label, " -> FAIL")

func _run_fixture(path: String) -> Dictionary:
	var out: Array = []
	var code: int = OS.execute(OS.get_executable_path(), [
		"--headless", "--fixed-fps", "60",
		"--path", ProjectSettings.globalize_path("res://"),
		"-s", path], out, true)
	return {"code": code, "text": "\n".join(out)}

func _init() -> void:
	var base_script: Resource = load("res://tests/support/gang_test.gd")
	_check(base_script != null, "gang_test.gd loads from tests/support")

	var passed: Dictionary = _run_fixture("res://tests/support/fixtures/pass_harness.gd")
	var pass_code: int = passed.code
	_check(pass_code == 0, "pass fixture exits 0 (got %d)" % pass_code)
	_check("DONE failures=0" in str(passed.text), "pass fixture prints DONE failures=0")
	_check("boot_main instances the main scene -> PASS" in str(passed.text), "boot_main works in a harness")
	_check("frames awaits real physics frames" in str(passed.text), "frames works in a harness")
	_check("until held -> PASS" in str(passed.text), "until works in a harness")

	var failed: Dictionary = _run_fixture("res://tests/support/fixtures/fail_harness.gd")
	var fail_code: int = failed.code
	_check(fail_code == 1, "fail fixture exits 1 (got %d)" % fail_code)
	_check("DONE failures=1" in str(failed.text), "fail fixture prints DONE failures=1")
	_check("failing check -> FAIL" in str(failed.text), "failing check is reported")

	var hung: Dictionary = _run_fixture("res://tests/support/fixtures/hang_harness.gd")
	var hang_code: int = hung.code
	_check(hang_code == 2, "hang fixture exits 2 via watchdog (got %d)" % hang_code)
	_check("TIMEOUT" in str(hung.text), "watchdog prints TIMEOUT")

	print("[516] DONE failures=", failures)
	quit(1 if failures > 0 else 0)
