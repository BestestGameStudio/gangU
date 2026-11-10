class_name GangTest
extends SceneTree
## #516 PARTIAL A: shared test-harness base, so harnesses stop
## re-implementing the test contract (152 private _check copies, 161
## failure counters, 44 _frames on main). In-house, not GUT/gdUnit4.
##
## Usage: a harness script extends GangTest and overrides run(); it may
## await inside run(). The base arms a watchdog, runs it, then quits:
##   exit 0 - every check passed and run() finished before the watchdog;
##   exit 1 - at least one check failed;
##   exit 2 - the watchdog fired (harness hung or errored out).
## Runners treat "exit 0 before the timeout" as PASS - no output parsing.
##
## This PARTIAL ships the base and its self-check only; adopting it in
## existing harnesses and the tests/<feature>/ move are later slices.

var failures: int = 0

var _finished: bool = false
var _timed_out: bool = false

func _init() -> void:
	_arm_watchdog()
	await run()
	finish()

## Override with the harness body. May await (physics_frame, timers).
func run() -> void:
	pass

## Watchdog budget; override for faster or slower harnesses.
func watchdog_seconds() -> float:
	return 60.0

## Short name used in output lines; defaults to the script filename.
func tag() -> String:
	var path: String = get_script().resource_path
	return path.get_file().get_basename()

func check(ok: bool, label: String) -> void:
	if ok:
		print("[", tag(), "] ", label, " -> PASS")
	else:
		failures += 1
		print("[", tag(), "] ", label, " -> FAIL")

func eq(got: Variant, expected: Variant, label: String) -> void:
	var same: bool = false
	if got == expected:
		same = true
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
	if _timed_out:
		print("[", tag(), "] TIMEOUT after ", watchdog_seconds(), "s")
		quit(2)
	elif failures == 0:
		print("[", tag(), "] DONE failures=0")
		quit(0)
	else:
		print("[", tag(), "] DONE failures=", failures)
		quit(1)

func _arm_watchdog() -> void:
	await create_timer(watchdog_seconds()).timeout
	if not _finished:
		_timed_out = true
		finish()
