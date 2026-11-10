extends SceneTree
## #436 harness: the explorable overworld is twice its old size in each
## direction (Daniel, 2026-11-09: "expand the overworld map" -> the world
## itself, 2x, same terrain mix for now).
##   (A) the field's radii doubled: 4x the explorable area.
##   (B) ground coverage: points inside the doubled ellipse are covered,
##       points beyond it (wobble margin included) are not.
##   (C) same terrain mix at the same density: decor covers the new ring
##       (decor exists past the old field edge), keeps out of the arrival,
##       gate and road clear zones, and every existing decor item inside
##       the old field kept its exact position and size.
##   (D) gates and the arrival point stay covered and untouched.

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[436] ", label, " -> ", "PASS" if ok else "FAIL")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var area: Node2D = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(area)
	await physics_frame
	await physics_frame
	var ground := area.get_node("Ground") as OverworldGround
	_check(ground != null, "ground node present")
	if ground == null:
		print("[436] failures: ", failures)
		quit(1)
		return

	# (A) doubled radii
	_check(ground.RADII == Vector2(2400, 2100), "radii doubled to (2400, 2100)")
	var old_area := PI * 1200.0 * 1050.0
	var new_area := PI * ground.RADII.x * ground.RADII.y
	_check(is_equal_approx(new_area / old_area, 4.0), "explorable area is 4x")

	# (B) coverage inside and outside the doubled ellipse. The outline
	# wobbles up to 6% past RADII, so probes stay clear of the edge band.
	_check(ground.covers(OverworldGround.CENTER + Vector2(2100, 0)), "covered at +2100 x (past the old 1200 edge)")
	_check(ground.covers(OverworldGround.CENTER + Vector2(-2100, 0)), "covered at -2100 x")
	_check(ground.covers(OverworldGround.CENTER + Vector2(0, 1800)), "covered at +1800 y (past the old 1050 edge)")
	_check(ground.covers(OverworldGround.CENTER + Vector2(0, -1800)), "covered at -1800 y")
	_check(not ground.covers(OverworldGround.CENTER + Vector2(2700, 0)), "not covered at +2700 x (beyond max wobble)")
	_check(not ground.covers(OverworldGround.CENTER + Vector2(0, 2400)), "not covered at +2400 y (beyond max wobble)")

	# (C) terrain mix fills the new ring at the old density
	var old_field := Rect2(OverworldGround.CENTER - Vector2(1200, 1050), Vector2(2400, 2100))
	var in_old := 0
	var in_new_ring := 0
	for d in ground.decor:
		if old_field.has_point(d["at"]):
			in_old += 1
		elif ground.covers(d["at"]):
			in_new_ring += 1
	_check(in_old > 100, "old field still has decor (%d items)" % in_old)
	_check(in_new_ring > in_old, "new ring is populated at the old density (%d new-ring vs %d old-field items)" % [in_new_ring, in_old])
	# existing world untouched: every decor item inside the OLD inner blob
	# keeps its exact kind, position and size (hash pinned from main).
	# #446 re-pinned: spreading the gates out moved their roads, pads and
	# guard beats (decor clear zones), so the old-field decor changed with
	# them by design.
	var poly := PackedVector2Array()
	for i in 64:
		var a := TAU * i / 64.0
		var wob := 1.0 + (OverworldGround._hash01(i, 0, 11) - 0.5) * 0.12
		poly.append(OverworldGround.CENTER + Vector2(cos(a) * (1200.0 * wob - 60.0), sin(a) * (1050.0 * wob - 60.0)))
	var lines := []
	for d in ground.decor:
		if Geometry2D.is_point_in_polygon(d["at"], poly):
			lines.append("%s %s %s" % [d["kind"], d["at"], d["r"]])
	lines.sort()
	_check("\n".join(lines).md5_text() == "102c8692992e1f144aeccb49bf63f7e4", "old-field decor identical to main (%d items, hash-pinned)" % lines.size())

	# clear zones hold across the whole field
	var clear_ok := true
	for d in ground.decor:
		if not ground._clear_spot(d["at"]):
			clear_ok = false
	_check(clear_ok, "decor keeps out of arrival/gate/road clear zones")

	# (D) gates and arrival untouched and covered
	_check(ground.spawn == Vector2(576, 480), "arrival point unchanged")
	_check(ground.landmarks.size() == 8, "all 8 gates present")
	for l in ground.landmarks:
		_check(ground.covers(l), "gate at %s covered" % l)

	print("[436] failures: ", failures)
	quit(1 if failures > 0 else 0)
