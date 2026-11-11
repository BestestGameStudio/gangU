extends SceneTree
## #207: the supplied spell-icon sheet packs into spell_icons.png +
## spell_icons_frames.tres; every player Spell resource binds the shared
## frames with the right prefix/upgraded flag; SpellIcon renders base,
## and (surfaces without the #238 overlay) green-chevron upgraded frames, a
## cooldown wipe that never swaps the art, and keeps the #193 placeholder
## behaviour for spells with no icon art.

var failures := 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("[207] ", label, " -> PASS")
	else:
		failures += 1
		print("[207] ", label, " -> FAIL")

func _initialize() -> void:
	var frames: SpriteFrames = load("res://resources/sprites/spell_icons_frames.tres")
	_check(frames != null, "frames resource loads")

	# A. SpriteFrames contract: 3 spells x (base + upgraded + sweep).
	var prefixes := [&"fireball", &"mana", &"bolt"]
	for p in prefixes:
		var base: StringName = p + "_base"
		var up: StringName = p + "_upgraded"
		var sweep: StringName = p + "_sweep"
		_check(frames.has_animation(base) and frames.get_frame_count(base) == 1, "%s base: 1 frame" % p)
		_check(frames.has_animation(up) and frames.get_frame_count(up) == 1, "%s upgraded: 1 frame" % p)
		_check(frames.has_animation(sweep) and frames.get_frame_count(sweep) == 4, "%s sweep: 4 frames" % p)
		_check(frames.get_animation_loop(base) and frames.get_animation_loop(up), "%s base+upgraded loop" % p)
		_check(not frames.get_animation_loop(sweep), "%s sweep does not loop" % p)
	# Frames are AtlasTextures inside the 329x144 sheet (7 cols x 3 rows of 47x48).
	var sheet: Texture2D = load("res://assets/sprites/spell_icons.png")
	_check(sheet != null and sheet.get_width() == 329 and sheet.get_height() == 144, "sheet is 329x144")
	var at := frames.get_frame_texture(&"fireball_base", 0) as AtlasTexture
	_check(at != null and at.atlas == sheet and at.region == Rect2(0, 0, 47, 48), "base frame is AtlasTexture cell (0,0)")
	var at2 := frames.get_frame_texture(&"bolt_sweep", 3) as AtlasTexture
	_check(at2 != null and at2.region == Rect2(6 * 47, 2 * 48, 47, 48), "bolt sweep frame 3 is cell (2,6)")

	# B. Sampled pixels read the intended colour family per spell row.
	var img := sheet.get_image()
	var fire_px := img.get_pixel(23, 24) # centre of fireball base cell
	var mana_px := img.get_pixel(23, 48 + 24) # mana base cell
	var bolt_px := img.get_pixel(23, 96 + 24) # bolt base cell
	_check(fire_px.r > fire_px.g and fire_px.g >= fire_px.b and fire_px.r > 0.4, "fireball centre reads warm")
	_check(mana_px.b > mana_px.r and mana_px.b > 0.4, "mana centre reads blue")
	_check(bolt_px.r > 0.4 and bolt_px.g > 0.4 and bolt_px.b < bolt_px.g, "bolt centre reads yellow")

	# C. All 13 player spell resources bind the shared frames correctly.
	var expect := {
		"fire_ball": [&"fireball", false], "fire_ball_split": [&"fireball", true],
		"fire_ball_split_wide": [&"fireball", true], "fire_ball_split_heavy": [&"fireball", true],
		"fire_ball_beam": [&"fireball", true], "fire_ball_beam_long": [&"fireball", true],
		"fire_ball_beam_piercing": [&"fireball", true], "fire_ball_beam_homing": [&"fireball", true],
		"fire_ball_beam_heavy": [&"fireball", true],
		"mana_shot": [&"mana", false], "mana_shot_volley": [&"mana", true], "mana_shot_lance": [&"mana", true],
		"placeholder_bolt": [&"bolt", false],
	}
	for res_name in expect:
		var spell: Spell = load("res://resources/spells/%s.tres" % res_name)
		_check(spell != null and spell.icon_frames == frames, "%s binds shared frames" % res_name)
		_check(spell.icon_prefix == expect[res_name][0] and spell.icon_upgraded == expect[res_name][1],
			"%s prefix/upgraded mapping" % res_name)
	# Enemy spells stay out of scope.
	for enemy in ["head_bolt", "warlord_orb"]:
		var es: Spell = load("res://resources/spells/%s.tres" % enemy)
		_check(es != null and es.icon_frames == null and es.icon_prefix == &"", "%s untouched" % enemy)

	# D. SpellIcon behaviour.
	var base_spell: Spell = load("res://resources/spells/fire_ball.tres")
	var up_spell: Spell = load("res://resources/spells/fire_ball_split.tres")
	var icon := SpellIcon.new(20.0)
	get_root().add_child(icon)
	icon.show_spell(base_spell)
	_check(icon.texture == frames.get_frame_texture(&"fireball_base", 0), "icon shows base frame")
	_check(not icon.get_node("Placeholder").visible, "placeholder hidden with art")
	icon.show_spell(up_spell)
	_check(icon.texture == frames.get_frame_texture(&"fireball_upgraded", 0), "upgraded spell shows chevron frame")

	# #238: icons with the upgrade overlay stay on the base art.
	var overlay_icon := SpellIcon.new(20.0, true)
	overlay_icon.show_spell(up_spell)
	_check(overlay_icon.texture == frames.get_frame_texture(&"fireball_base", 0), "overlay icon keeps base art for upgraded spell")
	overlay_icon.free()

	# #238: the cooldown is a wipe overlay; the art never swaps to sweep frames.
	icon.show_spell(base_spell)
	var wipe := icon.get_node("CooldownWipe") as ColorRect
	for frac in [1.0, 0.6, 0.3, 0.1]:
		icon.set_cooldown_fraction(frac)
		_check(icon.texture == frames.get_frame_texture(&"fireball_base", 0) and wipe.visible, "frac %s keeps base art under wipe" % str(frac))
	icon.set_cooldown_fraction(0.0)
	_check(icon.texture == frames.get_frame_texture(&"fireball_base", 0) and not wipe.visible, "frac 0 hides wipe")

	# #193 back-compat: a Spell.icon texture still wins; no art -> placeholder, same size.
	var img2 := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img2.fill(Color(1.0, 0.2, 0.6, 1.0))
	var tex := ImageTexture.create_from_image(img2)
	var legacy := Spell.new()
	legacy.mode = Spell.CastMode.PROJECTILE
	legacy.spell_name = "Legacy"
	legacy.icon = tex
	icon.show_spell(legacy)
	_check(icon.texture == tex and not icon.get_node("Placeholder").visible, "Spell.icon still wins (#193)")
	icon.set_cooldown_fraction(0.5)
	_check(icon.texture == tex and wipe.visible, "static icon also gets the wipe")
	var bare := Spell.new()
	bare.mode = Spell.CastMode.PROJECTILE
	icon.show_spell(bare)
	_check(icon.texture == SpellIcon.NO_ICON_TEXTURE and not icon.get_node("Placeholder").visible, "no art -> placeholder sprite (#257)")
	_check(icon.custom_minimum_size == Vector2(20, 20), "placeholder size unchanged")
	icon.show_spell(null)
	_check(icon.texture == null and icon.get_node("Placeholder").visible, "null spell -> empty box")
	icon.queue_free()

	print("[207] RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(1 if failures > 0 else 0)
