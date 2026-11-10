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

func _run() -> void:
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
	print("[529] note: the next load logs one SCRIPT ERROR on purpose (base parity)")
	_write("[audio]\n\nmaster_volume=[1]\n")
	_check("non-scalar rejected loudly, aborts to 0.0 like base", is_equal_approx(SettingsPanel.load_master_volume(TEST_PATH), 0.0))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	print("test529 done: %d checks, %d failures" % [_checks, _fails])
	print("RESULT: ALL PASS" if _fails == 0 else "RESULT: FAIL")
	quit(1 if _fails > 0 else 0)
