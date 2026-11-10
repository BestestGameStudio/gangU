class_name GangTest
extends SceneTree
## #516 PARTIAL A: shared test-harness base, so harnesses stop
## re-implementing the test contract (152 private _check copies, 161
## failure counters, 44 _frames on main). In-house, not GUT/gdUnit4.
##
## Usage: a harness script extends GangTest and overrides run(); it may
## await inside run(). The base arms a watchdog, runs it, then quits:
##   exit 0 - run() finished before the watchdog, every check passed,
##            and no engine/script error fired;
##   exit 1 - a check failed, an engine/script error fired, or run()
##            finished without recording a single check;
##   exit 2 - the watchdog fired (harness truly hung).
## Runners treat "exit 0 before the timeout" as PASS - no output parsing.
## (GDScript parse errors in a harness exit 1 natively under -s.)
##
## Engine/script errors are counted synchronously via a custom Logger
## (OS.add_logger, Godot 4.5): a mid-run GDScript error aborts run() but
## the caller otherwise continues, which used to let a broken harness
## exit 0. Now any counted error forces exit 1. Only actual engine errors
## (incl. push_error) and GDScript script errors count - warnings and
## shader errors are deliberately excluded. The run is NOT continued
## after an error; later checks are skipped by the engine.
##
## This PARTIAL ships the base and its self-check only; adopting it in
## existing harnesses and the tests/<feature>/ move are later slices.

var failures: int = 0
var checks_run: int = 0
var engine_errors: int = 0

var _finished: bool = false
var _timed_out: bool = false
var _logger: ErrorCounter = null

func _init() -> void:
	_logger = ErrorCounter.new(_on_engine_error)
	OS.add_logger(_logger)
	_arm_watchdog()
	await run()
	finish()

## Override with the harness body. May await (physics_frame, timers).
## The base body awaits one frame so the base call site can await run()
## whether or not the override suspends.
func run() -> void:
	await process_frame

## Watchdog budget; override for faster or slower harnesses.
func watchdog_seconds() -> float:
	return 60.0

## Short name used in output lines; defaults to the script filename.
func tag() -> String:
	var path: String = get_script().resource_path
	return path.get_file().get_basename()

func check(ok: bool, label: String) -> void:
	checks_run += 1
	if ok:
		print("[", tag(), "] ", label, " -> PASS")
	else:
		failures += 1
		print("[", tag(), "] ", label, " -> FAIL")

func eq(got: Variant, expected: Variant, label: String) -> void:
	# GDScript's == is not total: some cross-type pairs raise a runtime
	# SCRIPT ERROR instead of returning false (e.g. int vs String, bool
	# vs int, Vector2 vs Vector3, Object vs int). Same-type pairs are
	# always defined; verified safe cross-type pairs are int/float,
	# String/StringName, and nil against anything (compares false).
	# Anything else fails closed WITHOUT evaluating the comparison.
	var ta: int = typeof(got)
	var te: int = typeof(expected)
	var comparable: bool = ta == te
	if not comparable:
		var got_num: bool = ta == TYPE_INT or ta == TYPE_FLOAT
		var exp_num: bool = te == TYPE_INT or te == TYPE_FLOAT
		var got_str: bool = ta == TYPE_STRING or ta == TYPE_STRING_NAME
		var exp_str: bool = te == TYPE_STRING or te == TYPE_STRING_NAME
		comparable = (got_num and exp_num) or (got_str and exp_str) \
			or ta == TYPE_NIL or te == TYPE_NIL
	if not comparable:
		check(false, "%s (incomparable types %s vs %s)" % [label, type_string(ta), type_string(te)])
		return
	var same: bool = got == expected
	check(same, "%s (expected %s, got %s)" % [label, expected, got])

## Await n physics frames (fixed-fps harnesses run with --fixed-fps 60).
func frames(n: int) -> void:
	for i in n:
		await physics_frame

## Await cond until it holds or the frame budget runs out. Returns whether
## it held; with a label, also records the outcome as a check.
func until(cond: Callable, max_frames: int = 120, label: String = "") -> bool:
	var held: bool = false
	for i in max_frames:
		if cond.call():
			held = true
			break
		await physics_frame
	if label != "":
		check(held, label)
	return held

## Boot the real main scene as a fixture; returns the instance.
func boot_main() -> Node:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node = scene.instantiate()
	root.add_child(main)
	return main

## Minimal stage fixture: a bare Node2D added to the root, for harnesses
## that place their own bodies instead of booting a scene.
func stage() -> Node2D:
	var s := Node2D.new()
	root.add_child(s)
	return s

## Print the summary and quit with the contract exit code. Idempotent;
## the watchdog path (exit 2) wins over a later normal finish.
func finish() -> void:
	if _finished:
		return
	_finished = true
	if _logger != null:
		OS.remove_logger(_logger)
		_logger = null
	if _timed_out:
		print("[", tag(), "] TIMEOUT after ", watchdog_seconds(), "s")
		quit(2)
	elif failures == 0 and engine_errors == 0 and checks_run > 0:
		print("[", tag(), "] DONE failures=0 errors=0 checks=", checks_run)
		quit(0)
	else:
		print("[", tag(), "] DONE failures=", failures, " errors=", engine_errors, " checks=", checks_run)
		quit(1)

func _on_engine_error() -> void:
	engine_errors += 1

func _arm_watchdog() -> void:
	await create_timer(watchdog_seconds()).timeout
	if not _finished:
		_timed_out = true
		finish()


class ErrorCounter:
	extends Logger
	## Counts actual engine errors (including push_error) and GDScript
	## script errors synchronously, while they happen, so a mid-run
	## runtime error can never let a harness exit 0. Warnings and shader
	## errors are not counted. Logger error_type values: 0 engine error,
	## 1 warning, 2 script error, 3 shader error.
	var _note: Callable

	func _init(note: Callable) -> void:
		_note = note

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == 0 or error_type == 2:
			_note.call()
