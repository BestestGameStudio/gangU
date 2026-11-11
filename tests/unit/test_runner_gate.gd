extends SceneTree
## Runner contract self-check. Uses an isolated scratch project, never the
## production scripts directory. Each case invokes the real runner copy.
var failures := 0
func _initialize() -> void:
 var scratch := OS.get_user_data_dir().path_join("runner_gate_selfcheck")
 DirAccess.make_dir_recursive_absolute(scratch.path_join("tests/unit"))
 _write(scratch.path_join("project.godot"), "config_version=5\n")
 _write(scratch.path_join("run_tests.gd"), FileAccess.get_file_as_string("res://tools/run_tests.gd"))
 var cases := [
  ["clean", "extends SceneTree\nfunc _initialize() -> void:\n print('clean control')\n quit(0)\n", 0, "PASS"],
  ["runtime", "extends SceneTree\nfunc broken() -> void:\n var missing: Variant = null\n missing.nonexistent_method()\nfunc _initialize() -> void:\n broken()\n print('caller continued')\n quit(0)\n", 1, "FAIL (runtime script error)"],
  ["nonzero", "extends SceneTree\nfunc _initialize() -> void:\n quit(7)\n", 1, "FAIL (exit 7)"],
  ["parse", "extends SceneTree\nfunc _initialize( -> void:\n quit(0)\n", 1, "FAIL"],
  ["load", "extends SceneTree\nconst Missing = preload('res://does_not_exist.gd')\nfunc _initialize() -> void:\n quit(0)\n", 1, "FAIL"],
  ["timeout", "extends SceneTree\nfunc _initialize() -> void:\n pass\n", 1, "TIMEOUT"],
 ]
 for c in cases:
  _write(scratch.path_join("tests/unit/test_gate_" + c[0] + ".gd"), c[1])
 for c in cases:
  var output: Array = []
  var args := PackedStringArray(["--headless", "--path", scratch, "--script", "run_tests.gd", "--", "test_gate_" + c[0], "-j", "1", "--timeout", "1"])
  var code := OS.execute(OS.get_executable_path(), args, output, true)
  var text := "\n".join(output)
  var ok: bool = code == c[2] and c[3] in text
  if c[0] == "runtime":
   ok = ok and "caller continued" in text and "RESULT: FAILED" in text and not "RESULT: ALL PASS" in text
  if not ok:
   failures += 1
   print(text)
  print("[runner gate] ", c[0], " exit=", code, " expected=", c[2], " -> ", "PASS" if ok else "FAIL")
 _remove_tree(scratch)
 print("RESULT: ALL PASS" if failures == 0 else "RESULT: FAILED")
 quit(0 if failures == 0 else 1)
func _write(path: String, contents: String) -> void:
 var f := FileAccess.open(path, FileAccess.WRITE)
 f.store_string(contents)
func _remove_tree(path: String) -> void:
 var d := DirAccess.open(path)
 if d == null: return
 for sub in d.get_directories(): _remove_tree(path.path_join(sub))
 for f in d.get_files(): d.remove(f)
 DirAccess.remove_absolute(path)
