extends SceneTree
## #278: the cooldown wipe is translucent, so the spell art stays visible
## beneath it. Headless: checks the wipe colour and that compositing it over
## the real Fire Ball art keeps the art's contrast. Rendered (xvfb, opengl3):
## also reads back the viewport and checks the covered half still shows the
## art, and saves a screenshot when a path is given after "--":
##   godot --rendering-driver opengl3 -s scripts/test278_cooldown_translucent.gd -- /tmp/ci/media/x.png

const SIDE := 96.0
const MIN_VISIBLE_SPREAD := 0.08

var failures := 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("[278] ", label, " -> PASS")
	else:
		failures += 1
		print("[278] ", label, " -> FAIL")

func _luma(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b

## Max - min luma over opaque pixels of img, after an optional overlay blend.
func _spread(img: Image, overlay: Color, use_overlay: bool) -> float:
	var lo := 1.0
	var hi := 0.0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			if use_overlay:
				c = c.lerp(Color(overlay.r, overlay.g, overlay.b, 1.0), overlay.a)
			var l := _luma(c)
			lo = minf(lo, l)
			hi = maxf(hi, l)
	return hi - lo

func _initialize() -> void:
	var wipe_color := UiStyle.COOLDOWN_WIPE
	_check(wipe_color.a > 0.0 and wipe_color.a < 1.0, "wipe colour is translucent (a=%.2f)" % wipe_color.a)

	var fire: Spell = load("res://resources/spells/fire_ball.tres")
	var icon := SpellIcon.new(SIDE, true)
	icon.position = Vector2(40, 40)
	root.add_child(icon)
	icon.show_spell(fire)
	icon.set_cooldown_fraction(0.5)
	var wipe := icon.get_node("CooldownWipe") as ColorRect
	_check(wipe.visible and wipe.color == wipe_color, "icon wipe uses the translucent colour")
	_check(icon.get_child_count() > 0 and wipe.get_index() > icon.get_node("Placeholder").get_index(), "wipe draws above the art")

	var art := icon.texture.get_image()
	if art.is_compressed():
		art.decompress()
	var raw := _spread(art, wipe_color, false)
	var covered := _spread(art, wipe_color, true)
	_check(covered >= MIN_VISIBLE_SPREAD and covered >= raw * (1.0 - wipe_color.a) * 0.99,
		"art keeps contrast under the wipe (raw %.3f, covered %.3f)" % [raw, covered])

	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(320, 180)
		var bg := ColorRect.new()
		bg.color = Color(0.1, 0.1, 0.12)
		bg.size = Vector2(320, 180)
		root.add_child(bg)
		root.move_child(bg, 0)
		var ready_icon := SpellIcon.new(SIDE, true)
		ready_icon.position = Vector2(180, 40)
		root.add_child(ready_icon)
		ready_icon.show_spell(fire)
		for i in 10:
			await process_frame
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		# Bottom half of the cooling icon is under the wipe.
		var lo := 1.0
		var hi := 0.0
		for y in range(92, 134):
			for x in range(42, 134):
				var l := _luma(shot.get_pixel(x, y))
				lo = minf(lo, l)
				hi = maxf(hi, l)
		_check(hi - lo >= MIN_VISIBLE_SPREAD, "rendered: art visible through the wipe (spread %.3f)" % (hi - lo))
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			var scaled := shot.duplicate() as Image
			scaled.resize(shot.get_width() * 4, shot.get_height() * 4, Image.INTERPOLATE_NEAREST)
			scaled.save_png(args[0])
			print("[278] saved ", args[0])

	print("RESULT: ", "ALL PASS" if failures == 0 else "%d FAIL" % failures)
	quit(0 if failures == 0 else 1)
