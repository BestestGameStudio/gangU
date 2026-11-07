extends SceneTree
## FIXTURE visual (scratch integration proof, #33/#36): renders baseline
## fireball vs split placeholder (3-way 18deg fan via SpellFanout, the
## PROPOSED caster seam semantics) vs beam placeholder (fast long wide
## projectile, NOT a continuous beam) flying side by side. This is a fixture
## scene with a local spawn loop - NOT production casting; the real fan-out
## loop is the caster owner's post-#67 seam. Labeled fixture, not production
## evidence.
##
## Repair (test-side only, 2026-11-07): headless runs use the dummy renderer,
## so the old unconditional root.get_texture().get_image().save_png crashed
## with "Cannot call method 'save_png' on a null value". Pixel capture now
## runs only when a real renderer exists; headless instead asserts the same
## visual facts from live scene state (lane composition, fan geometry,
## distinct colors, relative travel) against the loaded spell resources.

var t := 0.0
var caps := 0
var fails := 0
var headless := false
var lanes := {} ## label -> {origin: Vector2, spell: Spell, shots: Array[Projectile]}

func check(cond: bool, label: String) -> void:
	if cond:
		print("[VIS] PASS: " + label)
	else:
		fails += 1
		printerr("[VIS] FAIL: " + label)

func _fixture_cast(spell_path: String, from: Vector2, label: String) -> void:
	var spell: Spell = load(spell_path)
	var pscene: PackedScene = load("res://scenes/projectile.tscn")
	var shots: Array[Projectile] = []
	# Proposed seam semantics: one spawn per SpellFanout direction.
	for d in SpellFanout.directions(Vector2.RIGHT, spell.projectile_count, spell.spread_degrees):
		var p: Projectile = pscene.instantiate()
		p.setup(spell, d, null)
		p.position = from
		root.add_child(p)
		shots.append(p)
	lanes[label] = {"origin": from, "spell": spell, "shots": shots}
	var lab := Label.new()
	lab.text = label
	lab.position = from + Vector2(-90, 40)
	lab.add_theme_font_size_override("font_size", 14)
	root.add_child(lab)

func _initialize() -> void:
	headless = DisplayServer.get_name() == "headless"
	root.content_scale_size = Vector2i(1152, 648)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.10, 0.16)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var note := Label.new()
	note.text = "FIXTURE scratch visual - proposed fanout seam semantics, not production casting (#33/#36)"
	note.position = Vector2(16, 12)
	note.add_theme_font_size_override("font_size", 14)
	root.add_child(note)
	_fixture_cast("res://resources/spells/fire_ball.tres", Vector2(120, 320), "baseline fireball")
	_fixture_cast("res://resources/spells/fire_ball_split.tres", Vector2(420, 320), "split [placeholder] 3 x 18deg")
	_fixture_cast("res://resources/spells/fire_ball_beam.tres", Vector2(760, 320), "beam [placeholder projectile]")
	if headless:
		print("[VIS] headless dummy renderer: asserting scene-state visual facts (pixel capture needs a real renderer)")

func _headless_composition_checks() -> void:
	check(lanes["baseline fireball"].shots.size() == 1, "baseline lane: exactly 1 projectile")
	var split: Array = lanes["split [placeholder] 3 x 18deg"].shots
	check(split.size() == 3, "split lane: exactly 3 projectiles (3-way fan)")
	var angles: Array = []
	for p in split:
		angles.append(p.direction.angle())
	angles.sort()
	check(angles.size() == 3 and absf(angles[1]) < 0.02, "split fan centered on cast direction (RIGHT)")
	var expected_spread := deg_to_rad(lanes["split [placeholder] 3 x 18deg"].spell.spread_degrees)
	check(absf((angles[2] - angles[0]) - expected_spread) < 0.02, "split fan total spread matches spell.spread_degrees (SpellFanout: total fan width)")
	check(lanes["beam [placeholder projectile]"].shots.size() == 1, "beam lane: exactly 1 projectile")
	var c_base: Color = lanes["baseline fireball"].spell.projectile_color
	var c_split: Color = lanes["split [placeholder] 3 x 18deg"].spell.projectile_color
	var c_beam: Color = lanes["beam [placeholder projectile]"].spell.projectile_color
	check(c_base != c_split and c_base != c_beam and c_split != c_beam, "baseline/split/beam colors pairwise distinct")

func _headless_motion_checks() -> void:
	var base = lanes["baseline fireball"]
	var split = lanes["split [placeholder] 3 x 18deg"]
	var beam = lanes["beam [placeholder projectile]"]
	var dy: Array = []
	for p in split.shots:
		dy.append(absf(p.position.y - split.origin.y))
	dy.sort()
	check(dy[0] < 2.0 and dy[2] > 20.0, "split fan: center shot straight, outer shots laterally separated")
	var beam_travel: float = beam.shots[0].position.x - beam.origin.x
	var base_travel: float = base.shots[0].position.x - base.origin.x
	check(beam_travel > base_travel * 1.5, "beam (fast) traveled well ahead of baseline fireball")

func _process(delta: float) -> bool:
	t += delta
	if headless:
		if caps == 0 and t > 0.10:
			caps = 1
			_headless_composition_checks()
			print("[VIS] t=0.10 composition asserted (beam in frame)")
		if caps == 1 and t > 0.28:
			caps = 2
			_headless_motion_checks()
			print("[VIS] t=0.28 motion asserted (fan spread clear)")
	else:
		if caps == 0 and t > 0.10:
			caps = 1
			root.get_texture().get_image().save_png("/downloads/fixture-split-beam-t010.png")
			print("[VIS] captured t=0.10 (beam in frame)")
		if caps == 1 and t > 0.28:
			caps = 2
			root.get_texture().get_image().save_png("/downloads/fixture-split-beam-t028.png")
			print("[VIS] captured t=0.28 (fan spread clear)")
	if t > 0.5:
		if headless:
			print("[VIS] DONE failures=%d" % fails)
			quit(fails)
		return true
	return false
