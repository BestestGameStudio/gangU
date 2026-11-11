extends SceneTree
## Test runner: runs every harness in its own headless Godot process.
##
##   godot --headless --path . --script res://tools/run_tests.gd -- [filter ...] [-j N] [--timeout S] [--list]
##
## A harness is a scripts/test*.gd that `extends SceneTree`. Each child runs with
## `--headless --fixed-fps 60` and its own user:// dir (XDG_DATA_HOME, Linux).
## A filter keeps tests whose name contains any of the given substrings.
## Pass = exit code 0 before the timeout, with no script diagnostics. Exits 1 if anything failed.

const TEST_DIR := "res://scripts"
const TAIL_LINES := 40
## Godot exits 0 when the --script itself fails to parse or load.
const LOAD_FAILURES: Array[String] = [
	"Parse Error:",
	"Failed to load script",
]

var _jobs := maxi(1, mini(8, OS.get_processor_count() / 2))
var _timeout_s := 180.0
var _filters: PackedStringArray = []
var _list_only := false

var _queue: Array[Dictionary] = []
var _running: Array[Dictionary] = []
var _results: Array[Dictionary] = []
var _started_ms := 0
var _exe := OS.get_executable_path()
var _project := ProjectSettings.globalize_path("res://")
var _runs_dir := OS.get_user_data_dir().path_join("test_runs")

func _initialize() -> void:
	if not _parse_args(OS.get_cmdline_user_args()):
		quit(2)
		return
	_queue = _discover()
	if _list_only:
		for t in _queue:
			print(t.name)
		quit(0)
		return
	if _queue.is_empty():
		push_error("run_tests: no tests match %s" % [_filters])
		quit(2)
		return
	print("run_tests: %d tests, %d parallel, %.0fs timeout" % [_queue.size(), _jobs, _timeout_s])
	OS.set_environment("GANGU_AUTOTEST", "1")
	_started_ms = Time.get_ticks_msec()

func _process(_delta: float) -> bool:
	if _list_only or _started_ms == 0:
		return false
	while _running.size() < _jobs and not _queue.is_empty():
		_start(_queue.pop_front())
	for t in _running.duplicate():
		_poll(t)
	if _running.is_empty() and _queue.is_empty():
		_summary()
		return true
	OS.delay_msec(20)
	return false

func _parse_args(args: PackedStringArray) -> bool:
	var i := 0
	while i < args.size():
		var a := args[i]
		if a == "-j" and i + 1 < args.size():
			_jobs = maxi(1, args[i + 1].to_int())
			i += 1
		elif a == "--timeout" and i + 1 < args.size():
			_timeout_s = maxf(1.0, args[i + 1].to_float())
			i += 1
		elif a == "--list":
			_list_only = true
		elif a.begins_with("-"):
			push_error("run_tests: unknown option %s" % a)
			return false
		else:
			_filters.append(a)
		i += 1
	return true

func _discover() -> Array[Dictionary]:
	var tests: Array[Dictionary] = []
	var files := DirAccess.get_files_at(TEST_DIR)
	files.sort()
	for f in files:
		if not (f.begins_with("test") and f.ends_with(".gd")):
			continue
		var name := f.get_basename()
		var path := TEST_DIR.path_join(f)
		if not _is_scene_tree_script(path):
			continue
		tests.append({name = name, args = ["--script", path]})
	return tests.filter(_matches)

func _is_scene_tree_script(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	return f != null and f.get_line().strip_edges() == "extends SceneTree"

func _matches(t: Dictionary) -> bool:
	if _filters.is_empty():
		return true
	for f in _filters:
		if f in t.name:
			return true
	return false

func _start(t: Dictionary) -> void:
	var user_dir := _runs_dir.path_join(t.name)
	_remove_tree(user_dir)
	DirAccess.make_dir_recursive_absolute(user_dir)
	OS.set_environment("XDG_DATA_HOME", user_dir)
	var args := PackedStringArray(["--headless", "--fixed-fps", "60", "--path", _project])
	args.append_array(t.args)
	var proc := OS.execute_with_pipe(_exe, args, false)
	if proc.is_empty():
		_finish(t, "ERROR", "could not start %s" % _exe)
		return
	t.pid = proc.pid
	t.stdio = proc.stdio
	t.stderr = proc.stderr
	t.out = PackedByteArray()
	t.t0 = Time.get_ticks_msec()
	_running.append(t)

func _poll(t: Dictionary) -> void:
	_drain(t)
	if OS.is_process_running(t.pid):
		if Time.get_ticks_msec() - t.t0 > _timeout_s * 1000.0:
			OS.kill(t.pid)
			_drain(t)
			_running.erase(t)
			_finish(t, "TIMEOUT", t.out.get_string_from_utf8())
		return
	_drain(t)
	_running.erase(t)
	var code: int = OS.get_process_exit_code(t.pid)
	var output: String = t.out.get_string_from_utf8()
	var status := "PASS"
	if code != 0:
		status = "FAIL (exit %d)" % code
	elif LOAD_FAILURES.any(func(m): return m in output):
		status = "FAIL (script did not load)"
	elif output.count("SCRIPT ERROR") > 0:
		status = "FAIL (runtime script error)"
	_finish(t, status, output)

func _drain(t: Dictionary) -> void:
	for pipe: FileAccess in [t.stdio, t.stderr]:
		while true:
			var chunk := pipe.get_buffer(65536)
			if chunk.is_empty():
				break
			t.out.append_array(chunk)

func _finish(t: Dictionary, status: String, output: String) -> void:
	var secs: float = (Time.get_ticks_msec() - int(t.get("t0", Time.get_ticks_msec()))) / 1000.0
	var errors: int = output.count("SCRIPT ERROR")
	_results.append({name = t.name, status = status, secs = secs, errors = errors})
	print("%-8s %6.1fs  %s%s" % [status.get_slice(" ", 0), secs, t.name, "  (%d SCRIPT ERROR)" % errors if errors > 0 else ""])
	if status != "PASS":
		var lines := output.split("\n")
		print("    --- %s: %s, last %d lines ---" % [t.name, status, TAIL_LINES])
		for line in lines.slice(maxi(0, lines.size() - TAIL_LINES)):
			print("    | ", line)

func _summary() -> void:
	var failed := _results.filter(func(r): return r.status != "PASS")
	var secs := (Time.get_ticks_msec() - _started_ms) / 1000.0
	print("")
	print("run_tests: %d passed, %d failed, %d total in %.1fs" % [_results.size() - failed.size(), failed.size(), _results.size(), secs])
	for r in failed:
		print("  %s  %s" % [r.status, r.name])
	print("RESULT: ALL PASS" if failed.is_empty() else "RESULT: FAILED")
	quit(1 if not failed.is_empty() else 0)

func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for f in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(path)
