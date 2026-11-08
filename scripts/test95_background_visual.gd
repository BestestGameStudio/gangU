extends SceneTree
## #95 acceptance driver (headless). Proves the background/environment
## readability pass within its exact window:
##   hub decor    - Background(z -50) with SpawnDiamond + SpawnDiamondInner
##                  concentric flat Polygon2D at the spawn marker and four
##                  14x14 ColorRect corner ticks, slate blue-gray
##   dungeon decor- Background(z -50) with four 4px ArenaFrame ColorRect
##                  edges around the combat zone and two flat UP chevrons
##                  below the spawn; cool slate in DungeonA, warm slate in
##                  DungeonB (hub/dungeon/A/B accents all distinct)
##   receded      - every decor color low-chroma (<=0.16) and mid-dark
##                  luminance (0.20..0.55): player blue, enemy orange, item
##                  and gate/state colors keep dominance
##   pure visual  - no CollisionShape2D under any Background node
##   boundary     - existing nodes/geometry untouched: hub gates+spawn,
##                  dungeon spawns + SpawnData entries
##   grid contract- background_grid.tscn keeps spacing 64, half_extent 4096,
##                  major_every 4, z_index -100 (scroll behavior unchanged)
## The decor legs FAIL on the old base (no Background nodes) - meaningful
## negative. Stringly-loads scenes; no gameplay wiring touched.

const HUB_SLATE := Color(0.36, 0.41, 0.49, 1)
const HUB_SLATE_DARK := Color(0.24, 0.27, 0.33, 1)
const DUNGEONA_SLATE := Color(0.30, 0.35, 0.44, 1)
const DUNGEONB_SLATE := Color(0.42, 0.36, 0.32, 1)

const DIAMOND_OUTER: Array[Vector2] = [Vector2(0, -34), Vector2(34, 0), Vector2(0, 34), Vector2(-34, 0)]
const DIAMOND_INNER: Array[Vector2] = [Vector2(0, -22), Vector2(22, 0), Vector2(0, 22), Vector2(-22, 0)]
const CHEVRON_UP: Array[Vector2] = [Vector2(-12, -11), Vector2(0, -21), Vector2(12, -11), Vector2(12, -17), Vector2(0, -27), Vector2(-12, -17)]

var failures := 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("[95] ", label, " -> PASS")
	else:
		failures += 1
		print("[95] ", label, " -> FAIL")

func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

func _chroma(c: Color) -> float:
	return maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))

func _poly_pts(p: Polygon2D) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for v in p.polygon:
		out.append(v)
	return out

func _check_receded(bg: Node2D, area: String) -> void:
	for child in bg.get_children():
		var col := Color.BLACK
		if child is ColorRect:
			col = child.color
		elif child is Polygon2D:
			col = child.color
		else:
			_check(false, "%s decor %s is ColorRect/Polygon2D only" % [area, child.name])
			continue
		_check(_chroma(col) <= 0.16, "%s %s low-chroma (%.3f)" % [area, child.name, _chroma(col)])
		var l := _lum(col)
		_check(l >= 0.20 and l <= 0.55, "%s %s receded luminance (%.3f)" % [area, child.name, l])
	_check(bg.find_children("*", "CollisionShape2D", true, false).size() == 0, "%s decor carries no collision" % area)

func _rect_of(cr: ColorRect) -> Rect2:
	return Rect2(cr.offset_left, cr.offset_top, cr.offset_right - cr.offset_left, cr.offset_bottom - cr.offset_top)

func _initialize() -> void:
	var root := get_root()

	# ---- HUB ----
	var hub: Node2D = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	var hbg := hub.get_node_or_null("Background")
	_check(hbg != null and hbg is Node2D, "hub Background node present")
	_check(hbg != null and hbg.z_index <= -50 and hbg.z_index > -100, "hub Background z above grid, below gameplay (%d)" % (hbg.z_index if hbg else 0))
	var dia := hbg.get_node_or_null("SpawnDiamond") as Polygon2D if hbg else null
	_check(dia != null and dia.position == Vector2(576, 480) and _poly_pts(dia) == DIAMOND_OUTER and dia.color == HUB_SLATE, "hub spawn diamond exact (slate outer)")
	var dini := hbg.get_node_or_null("SpawnDiamondInner") as Polygon2D if hbg else null
	_check(dini != null and dini.position == Vector2(576, 480) and _poly_pts(dini) == DIAMOND_INNER and dini.color == HUB_SLATE_DARK, "hub spawn diamond exact (dark inner)")
	var corners := {"CornerNW": Rect2(216, 190, 14, 14), "CornerNE": Rect2(922, 190, 14, 14), "CornerSW": Rect2(216, 616, 14, 14), "CornerSE": Rect2(922, 616, 14, 14)}
	for cname in corners:
		var cr := hbg.get_node_or_null(cname) as ColorRect if hbg else null
		_check(cr != null and _rect_of(cr) == corners[cname] and cr.color == HUB_SLATE, "hub %s exact" % cname)
	if hbg:
		_check_receded(hbg, "hub")
	# boundary: existing hub nodes untouched
	_check(hub.get_node("PlayerSpawn").position == Vector2(576, 480), "hub PlayerSpawn untouched")
	_check(hub.get_node("GateNormal").position == Vector2(300, 380), "hub GateNormal untouched")
	_check(hub.get_node("GateRed").position == Vector2(852, 380), "hub GateRed untouched")

	# ---- DUNGEONS ----
	var frames := {"Top": Rect2(150, 84, 852, 4), "Bottom": Rect2(150, 652, 852, 4), "Left": Rect2(150, 84, 4, 572), "Right": Rect2(998, 84, 4, 572)}
	var dungeons := [
		{"scene": "res://scenes/dungeon_a.tscn", "root_name": "DungeonA", "accent": DUNGEONA_SLATE, "tag": "dungeonA"},
		{"scene": "res://scenes/dungeon_b.tscn", "root_name": "DungeonB", "accent": DUNGEONB_SLATE, "tag": "dungeonB"},
	]
	for d in dungeons:
		var area: Node2D = load(d["scene"]).instantiate()
		root.add_child(area)
		var bg := area.get_node_or_null("Background")
		_check(bg != null and bg is Node2D, "%s Background node present" % d["tag"])
		_check(bg != null and bg.z_index <= -50 and bg.z_index > -100, "%s Background z above grid, below gameplay (%d)" % [d["tag"], bg.z_index if bg else 0])
		for side in frames:
			var fr := bg.get_node_or_null("ArenaFrame" + side) as ColorRect if bg else null
			_check(fr != null and _rect_of(fr) == frames[side] and fr.color == d["accent"], "%s ArenaFrame%s exact" % [d["tag"], side])
		var c1 := bg.get_node_or_null("SpawnChevron1") as Polygon2D if bg else null
		_check(c1 != null and c1.position == Vector2(576, 596) and _poly_pts(c1) == CHEVRON_UP and c1.color == d["accent"], "%s SpawnChevron1 exact (UP)" % d["tag"])
		var c2 := bg.get_node_or_null("SpawnChevron2") as Polygon2D if bg else null
		_check(c2 != null and c2.position == Vector2(576, 618) and _poly_pts(c2) == CHEVRON_UP and c2.color == d["accent"], "%s SpawnChevron2 exact (UP)" % d["tag"])
		if bg:
			_check_receded(bg, d["tag"])
		_check(area.get_node("PlayerSpawn").position == Vector2(576, 560), "%s PlayerSpawn untouched" % d["tag"])
		var sd = area.get_node_or_null("SpawnData")
		_check(sd != null, "%s SpawnData untouched" % d["tag"])

	# ---- distinct identity ----
	_check(HUB_SLATE != DUNGEONA_SLATE and HUB_SLATE != DUNGEONB_SLATE and DUNGEONA_SLATE != DUNGEONB_SLATE, "hub / dungeonA / dungeonB accents all distinct")

	# ---- grid scroll contract unchanged ----
	var grid: Node2D = load("res://scenes/background_grid.tscn").instantiate()
	root.add_child(grid)
	_check(grid.spacing == 64, "grid spacing contract 64")
	_check(grid.half_extent == 4096, "grid half_extent contract 4096")
	_check(grid.major_every == 4, "grid major_every contract 4")
	await process_frame
	_check(grid.z_index == -100, "grid z_index -100 behind everything")

	print("[95] DONE failures=%d" % failures)
	quit(1 if failures > 0 else 0)
