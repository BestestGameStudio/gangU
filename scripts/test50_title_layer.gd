extends SceneTree
## #50 harness: every area Title label must live on a screen-space
## CanvasLayer (never clipped by / never under the fixed HUD zone), anchored
## top-RIGHT clear of the HUD band (HUD occupies x < ~450 at native 1152).
## World-space titles were position-dependent under the HUD zone (P5).
##
## #88 legs: the wide HUD backing plate (long spell names) can extend over
## the title rect, so the TitleLayer CanvasLayer must stack ABOVE the HUD
## CanvasLayer (HUD stays at its default layer; title layer strictly
## greater). New legs below: per-area layer ordering, then a geometry proof
## with the ACTUAL HUD scene driven to wide content (the 69-char piercing
## apply entry) against the ACTUAL DungeonA title rect, plus mutation legs
## proving the layer check discriminates. The old base (both layers equal)
## fails the ordering and combined legs.

const AREAS := {
	"res://scenes/hub.tscn": "HUB",
	"res://scenes/dungeon_a.tscn": "DUNGEON A",
	"res://scenes/dungeon_b.tscn": "DUNGEON B (RED gate)",
}
## #124 regression: the 8 renamed upgraded spell resources and all area titles
## must never re-grow a bracketed dev note.
const RENAMED_SPELLS := [
	"res://resources/spells/fire_ball_split.tres",
	"res://resources/spells/fire_ball_split_wide.tres",
	"res://resources/spells/fire_ball_split_heavy.tres",
	"res://resources/spells/fire_ball_beam.tres",
	"res://resources/spells/fire_ball_beam_long.tres",
	"res://resources/spells/fire_ball_beam_heavy.tres",
	"res://resources/spells/fire_ball_beam_piercing.tres",
	"res://resources/spells/fire_ball_beam_homing.tres",
]
const HUD_BAND_RIGHT := 450.0
const VIEWPORT_W := 1152.0
## Synthetic 69-char HPLabel stress string (NOT a live spell name) - the #88
## wide-plate trigger. Kept after #124 renamed live strings; injects worst-case
## width directly into HPLabel so the masking-geometry legs stay discriminating.
const WIDE_CONTENT := "Fire Ball Beam Piercing [placeholder projectile, not continuous beam]"

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[50] ", name, " -> PASS")
	else:
		failures += 1
		print("[50] ", name, " -> FAIL")

func _initialize() -> void:
	# Host-independent logical viewport for the screen-space geometry legs
	# (same content-scale trick as 50b; headless window size is unreliable).
	root.size = Vector2i(1152, 648)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(1152, 648)

	# The ACTUAL HUD scene's CanvasLayer layer (default 1 at base a02ab51).
	var hud_scene := load("res://scenes/hud.tscn") as PackedScene
	var hud_probe := hud_scene.instantiate() as CanvasLayer
	var hud_layer: int = hud_probe.layer
	hud_probe.free()

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
		_check(not title.text.contains("["), path.get_file() + ": Title carries no bracketed dev note (#124)")
		# Old world-space Label must be gone (no direct-child Label named Title).
		_check(scene.get_node_or_null("Title") == null, path.get_file() + ": no world-space Title remains")
		# #88: title layer stacks strictly above the HUD layer so a wide HUD
		# plate cannot mask it. Old base (equal layers) fails this leg.
		if layer != null:
			_check(layer.layer > hud_layer,
				path.get_file() + ": TitleLayer layer %d above HUD layer %d" % [layer.layer, hud_layer])
		root.remove_child(scene)
		scene.free()

	for sp in RENAMED_SPELLS:
		var res: Resource = load(sp)
		_check(res != null and not (res.spell_name as String).contains("["),
			sp.get_file() + ": spell_name carries no bracketed dev note (#124)")

	# #88 geometry proof: ACTUAL HUD driven to wide content vs the ACTUAL
	# DungeonA title rect. The plate must genuinely reach under the title
	# (intersection real), and the title must still render above it.
	var hud := hud_scene.instantiate()
	root.add_child(hud)
	hud.get_node("Root/HPLabel").text = WIDE_CONTENT
	var da := (load("res://scenes/dungeon_a.tscn") as PackedScene).instantiate()
	root.add_child(da)
	var da_title := da.get_node("TitleLayer/Title") as Label
	var da_layer := da.get_node("TitleLayer") as CanvasLayer

	# Condition wait for the plate rebuild, never a fixed frame budget.
	var frames := 0
	while hud.reserved_rect().size.x <= 400.0 and frames < 600:
		await process_frame
		frames += 1
	_check(hud.reserved_rect().size.x > 400.0, "HUD plate rebuilt wide after 69-char content")
	await process_frame # let Control layout settle before reading the title rect
	var plate: Rect2 = hud.reserved_rect()
	var trect: Rect2 = da_title.get_global_rect()
	print("[50] #88: plate=", plate, " title=", trect, " title_layer=", da_layer.layer, " hud_layer=", hud_layer)
	var intersects := plate.intersects(trect)
	_check(intersects, "DungeonA wide plate rect intersects title rect (masking geometry is real)")
	var above: bool = da_layer.layer > hud_layer
	_check(above, "title layer above HUD layer (renders over the wide plate)")
	_check(intersects and above, "combined: wide plate reaches title AND title above (old base fails both-equal)")
	# Mutation legs: the ordering check must discriminate, not vacuously pass.
	da_layer.layer = hud_layer
	_check(not (da_layer.layer > hud_layer), "mutation layer=HUD: above-condition false (leg discriminates)")
	da_layer.layer = 0
	_check(not (da_layer.layer > hud_layer), "mutation layer=0: above-condition false (leg discriminates)")
	da_layer.layer = 2 # restore the shipped value

	root.remove_child(da)
	da.free()
	root.remove_child(hud)
	hud.free()
	if failures == 0:
		print("[50] PASS")
	else:
		print("[50] DONE failures=", failures)
	quit(failures)
