extends SceneTree
## #514: Spell.id() is the .tres file name, unique across shipped spells, and
## the id-keyed projectile sprite table agrees with the old name-keyed one.

var _fails: int = 0

func _check(ok: bool, msg: String) -> void:
	print("[test514_spell_id] %s -> %s" % [msg, "PASS" if ok else "FAIL"])
	if not ok:
		_fails += 1

func _initialize() -> void:
	await process_frame
	var seen: Dictionary = {}
	var n := 0
	for f in DirAccess.get_files_at("res://resources/spells"):
		if not f.ends_with(".tres"):
			continue
		var s := load("res://resources/spells/" + f) as Spell
		if s == null:
			continue
		n += 1
		_check(s.id() == StringName(f.get_basename()), "%s id is its file name" % f)
		_check(not seen.has(s.id()), "%s id unique" % f)
		seen[s.id()] = true
		var by_name: StringName = Projectile.SPELL_SPRITE_ANIMS.get(s.spell_name, &"")
		_check(Projectile.sprite_anim_for(s) == by_name, "%s sprite row unchanged vs name table" % f)
		# Renaming the display name must not change the row for a mapped spell.
		var old_name := s.spell_name
		s.spell_name = "Renamed Spell"
		_check(Projectile.sprite_anim_for(s) == by_name, "%s row survives a display-name change" % f)
		s.spell_name = old_name
	# Dispatch probe: the real projectile scene picks the id-keyed row and starts
	# its "<row>_start" animation (source/animator compatibility, not a render).
	var dispatched := 0
	for f in DirAccess.get_files_at("res://resources/spells"):
		if not f.ends_with(".tres"):
			continue
		var sp := load("res://resources/spells/" + f) as Spell
		var row: StringName = Projectile.sprite_anim_for(sp)
		var proj: Projectile = load("res://scenes/projectile.tscn").instantiate()
		proj.setup(sp, Vector2.RIGHT, null)
		root.add_child(proj)
		var spr := proj.get_node_or_null("Sprite") as AnimatedSprite2D
		if row == &"":
			_check(spr == null, "%s has no sprite row, stays code-drawn" % f)
		else:
			dispatched += 1
			_check(spr != null and spr.animation == StringName("%s_start" % row) and spr.sprite_frames.has_animation(row), "%s plays %s_start with a %s flight row" % [f, row, row])
		proj.free()
	_check(dispatched >= 25, "%d spells dispatched to a sprite row" % dispatched)
	_check(n >= 40, "scanned %d shipped spells" % n)
	var code := Spell.new()
	code.mode = Spell.CastMode.PROJECTILE
	code.spell_name = "Fire Ball"
	_check(code.id() == &"", "code-built spell has empty id")
	_check(Projectile.sprite_anim_for(code) == &"fire_ball", "code-built spell falls back to the name table")
	_check(Projectile.sprite_anim_for(null) == &"", "null spell has no row")
	print("[test514_spell_id] DONE fails=%d" % _fails)
	quit(1 if _fails > 0 else 0)
