extends SceneTree
## #50 harness: every area Title label must live on a screen-space
## CanvasLayer (never clipped by / never under the fixed HUD zone), anchored
## top-RIGHT clear of the HUD band (HUD occupies x < ~450 at native 1152).
## World-space titles were position-dependent under the HUD zone (P5).

const AREAS := {
	"res://scenes/hub.tscn": "HUB",
	"res://scenes/dungeon_a.tscn": "DUNGEON A (placeholder, normal gate)",
	"res://scenes/dungeon_b.tscn": "DUNGEON B (placeholder, RED gate)",
}
const HUD_BAND_RIGHT := 450.0
const VIEWPORT_W := 1152.0

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[50] ", name, " -> PASS")
	else:
		failures += 1
		print("[50] ", name, " -> FAIL")

func _initialize() -> void:
	for path in AREAS:
		var scene: Node = (load(path) as PackedScene).instantiate()
		root.add_child(scene)
		var title := scene.get_node_or_null("TitleLayer/Title") as Label
		_check(title != null, path.get_file() + ": Title exists under TitleLayer")
		if title == null:
			continue
		var layer := title.get_parent() as CanvasLayer
		_check(layer != null, path.get_file() + ": Title parent is CanvasLayer (screen space)")
		_check(is_equal_approx(title.anchor_right, 1.0), path.get_file() + ": Title anchored right edge")
		var left_edge := VIEWPORT_W + title.offset_left
		_check(left_edge >= HUD_BAND_RIGHT,
			path.get_file() + ": Title box left edge %.0f clears HUD band %.0f" % [left_edge, HUD_BAND_RIGHT])
		_check(title.text == AREAS[path], path.get_file() + ": Title text preserved")
		# Old world-space Label must be gone (no direct-child Label named Title).
		_check(scene.get_node_or_null("Title") == null, path.get_file() + ": no world-space Title remains")
		root.remove_child(scene)
		scene.free()
	if failures == 0:
		print("[50] PASS")
	else:
		print("[50] DONE failures=", failures)
	quit(failures)
