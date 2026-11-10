extends SceneTree
## #529 harness: Settings master_volume legacy/malformed value compatibility
## (#518/#527 regression check). The pre-#527 load coerced with float():
## "0.5"->0.5, "abc"->0.0, true->1.0, ints widen, result clamped to 0..1.
## Non-scalar values must keep failing loudly (script error) instead of
## silently forcing a wrong volume.
## Run: godot --headless --path . --script scripts/test529_settings_legacy_volume.gd

const TEST_PATH := "user://test529_settings_legacy.cfg"

var _fails := 0
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[529] ", label, " -> ", "PASS" if ok else "FAIL")

func _write(text: String) -> void:
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _run_nonscalar_child() -> Dictionary:
	var args: Array = [
		"--headless", "--fixed-fps", "60",
		"--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://scripts/test529_settings_legacy_volume.gd",
		"--", "--non-scalar-child"]
	var out: Array = []
	var code: int = OS.execute(OS.get_executable_path(), args, out, true, true)
	return {"code": code, "text": "\n".join(out)}

func _run() -> void:
	if OS.get_cmdline_user_args().has("--non-scalar-child"):
		_write("[audio]\n\nmaster_volume=[1]\n")
		print("CHILD_529 volume=", SettingsPanel.load_master_volume(TEST_PATH))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
		quit(0)
		return
	print("test529: settings legacy master_volume compatibility (#529)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	_check("no file -> default 1.0", is_equal_approx(SettingsPanel.load_master_volume(TEST_PATH), 1.0))
	_write("[audio]\n\nmaster_volume=\"0.5\"\n")
	_check("string \"0.5\" -> 0.5", is_equal_approx(SettingsPanel.load_master_volume(TEST_PATH), 0.5))
	_write("[audio]\n\nmaster_volume=0.25\n")
	_check("plain float -> 0.25", is_equal_approx(SettingsPanel.load_master_volume(TEST_PATH), 0.25))
	_write("[audio]\n\nmaster_volume=2\n")
	_check("int widens, clamps to 1.0", is_equal_approx(SettingsPanel.load_master_volume(TEST_PATH), 1.0))
	_write("[audio]\n\nmaster_volume=-0.5\n")
	_check("negative clamps to 0.0", is_equal_approx(SettingsPanel.load_master_volume(TEST_PATH), 0.0))
	_write("[audio]\n\nmaster_volume=\"abc\"\n")
	_check("garbage string -> 0.0 (base float() parity)", is_equal_approx(SettingsPanel.load_master_volume(TEST_PATH), 0.0))
	_write("[audio]\n\nmaster_volume=true\n")
	_check("bool -> 1.0", is_equal_approx(SettingsPanel.load_master_volume(TEST_PATH), 1.0))
	_write("[other]\n\nx=1\n")
	_check("missing key -> default 1.0", is_equal_approx(SettingsPanel.load_master_volume(TEST_PATH), 1.0))
	## The non-scalar leg runs in a child process: the load raises a real
	## engine error on purpose (base parity), and the CI test gate fails any
	## harness whose own output contains that engine error line. The child
	## carries the error; this process only asserts on the captured output.
	var child: Dictionary = _run_nonscalar_child()
	_check("non-scalar load raises the engine error (base parity)", "SCRIPT ERROR" in str(child.text))
	_check("non-scalar rejected loudly, aborts to 0.0 like base", "CHILD_529 volume=0" in str(child.text))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	print("test529 done: %d checks, %d failures" % [_checks, _fails])
	print("RESULT: ALL PASS" if _fails == 0 else "RESULT: FAIL")
	quit(1 if _fails > 0 else 0)
