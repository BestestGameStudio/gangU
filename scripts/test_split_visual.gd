extends SceneTree
## FIXTURE visual (scratch integration proof, #33/#36): renders baseline
## fireball vs split placeholder (3-way 18deg fan via SpellFanout, the
## PROPOSED caster seam semantics) vs beam placeholder (fast long wide
## projectile, NOT a continuous beam) flying side by side. This is a fixture
## scene with a local spawn loop - NOT production casting; the real fan-out
## loop is the caster owner's post-#67 seam. Labeled fixture, not production
## evidence.
var t := 0.0
var caps := 0

func _fixture_cast(spell_path: String, from: Vector2, label: String) -> void:
	var spell: Spell = load(spell_path)
	var pscene: PackedScene = load("res://scenes/projectile.tscn")
	# Proposed seam semantics: one spawn per SpellFanout direction.
	for d in SpellFanout.directions(Vector2.RIGHT, spell.projectile_count, spell.spread_degrees):
		var p: Projectile = pscene.instantiate()
		p.setup(spell, d, null)
		p.position = from
		root.add_child(p)
	var lab := Label.new()
	lab.text = label
	lab.position = from + Vector2(-90, 40)
	lab.add_theme_font_size_override("font_size", 14)
	root.add_child(lab)

func _initialize() -> void:
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

func _process(delta: float) -> bool:
	t += delta
	if caps == 0 and t > 0.10:
		caps = 1
		root.get_texture().get_image().save_png("/downloads/fixture-split-beam-t010.png")
		print("[VIS] captured t=0.10 (beam in frame)")
	if caps == 1 and t > 0.28:
		caps = 2
		root.get_texture().get_image().save_png("/downloads/fixture-split-beam-t028.png")
		print("[VIS] captured t=0.28 (fan spread clear)")
	if t > 0.5:
		return true
	return false
