extends SceneTree
## #208: damage number color follows the hit's ROLLED crit tier (#206), not
## the raw crit chance stat. Tier 0 white, 1 yellow, 2 orange, 3+ red.
## Proves the color table, direct apply_damage tiers, and real ENGINE
## projectile hits (enemy + container) carrying DamageResult.crit_tier
## through to the spawned number.
## Run: godot --headless --path . -s res://scripts/test208_crit_number_colors.gd

var failures := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[208] ", name, " -> ", "PASS" if cond else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _numbers(parent: Node) -> Array[DamageNumber]:
	var out: Array[DamageNumber] = []
	for n in parent.get_children():
		if n is DamageNumber and not n.is_queued_for_deletion():
			out.append(n)
	return out

func _color(n: DamageNumber) -> Color:
	return (n.get_child(0) as Label).get_theme_color("font_color")

func _area(stage: Node2D) -> Node2D:
	var a := Node2D.new()
	stage.add_child(a)
	return a

func _spell(p_damage: float) -> Spell:
	var s := Spell.new()
	s.spell_name = "Fixture Bolt"
	s.damage = p_damage
	s.radius = 4.0
	s.range = 600.0
	s.projectile_speed = 500.0
	return s

func _fire(parent: Node2D, p_spell: Spell, target: Vector2, p_source: Node2D) -> void:
	var pr: Projectile = preload("res://scenes/projectile.tscn").instantiate()
	pr.setup(p_spell, Vector2.DOWN, p_source)
	parent.add_child(pr)
	pr.global_position = target + Vector2(0, -60)

func _initialize() -> void:
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)
	current_scene = stage
	await process_frame

	# --- color table ---
	var white := Color(1, 1, 1)
	var yellow := DamageNumber.color_for_tier(1)
	var orange := DamageNumber.color_for_tier(2)
	var red := DamageNumber.color_for_tier(3)
	_check(DamageNumber.color_for_tier(0) == white, "tier 0 (non-crit) is white")
	_check(yellow.r > 0.9 and yellow.g > 0.8 and yellow.b < 0.4, "tier 1 is yellow")
	_check(orange.r > 0.9 and orange.g > 0.4 and orange.g < 0.7 and orange.b < 0.3, "tier 2 is orange")
	_check(red.r > 0.9 and red.g < 0.3 and red.b < 0.3, "tier 3 is red")
	_check(DamageNumber.color_for_tier(5) == red, "tiers above 3 clamp to red")
	_check(DamageNumber.color_for_tier(-1) == white, "negative tier clamps to white")
	_check(white != yellow and yellow != orange and orange != red, "all four tiers are distinct")

	# --- direct apply_damage: tier per hit, default stays white ---
	var areas: Array[Node2D] = []
	for t in 4:
		var a := _area(stage)
		var e: Enemy = preload("res://scenes/enemy.tscn").instantiate()
		e.position = Vector2(200 + 150 * t, 200)
		a.add_child(e)
		areas.append(a)
	var legacy_area := _area(stage)
	var legacy: Enemy = preload("res://scenes/enemy.tscn").instantiate()
	legacy.position = Vector2(900, 200)
	legacy_area.add_child(legacy)
	await process_frame
	for t in 4:
		(areas[t].get_child(0) as Enemy).apply_damage(3, t)
	legacy.apply_damage(3)
	await process_frame
	for t in 4:
		var nums := _numbers(areas[t])
		_check(nums.size() == 1 and nums[0].crit_tier == t and _color(nums[0]) == DamageNumber.color_for_tier(t),
			"apply_damage(3, tier %d) spawns one number in the tier %d color" % [t, t])
		_check((areas[t].get_child(0) as Enemy).hp == 27, "tier %d: HP math ignores the tier (30 - 3 = 27)" % t)
	var ln := _numbers(legacy_area)
	_check(ln.size() == 1 and ln[0].crit_tier == 0 and _color(ln[0]) == white, "legacy apply_damage(amount) stays white")

	# --- real engine projectile hits carry the rolled tier ---
	var player: Player = preload("res://scenes/player.tscn").instantiate()
	player.add_to_group("player")
	stage.add_child(player)
	player.global_position = Vector2(2000, 2000)
	await _frames(2)

	var hit_area := _area(stage)
	var target: Enemy = preload("res://scenes/enemy.tscn").instantiate()
	target.position = Vector2(400, 600)
	hit_area.add_child(target)
	await _frames(2)

	# 0% crit -> white, 5 damage.
	_fire(stage, _spell(5.0), target.global_position, player)
	await _frames(20)
	var n0 := _numbers(hit_area)
	_check(n0.size() == 1 and (n0[0].get_child(0) as Label).text == "5" and _color(n0[0]) == white,
		"projectile, 0% crit: \"5\" in white")

	# 200% crit at x2.0 -> guaranteed tier 2: 5 * 3 = 15, orange.
	var crit200 := DamageModifier.crit(2.0, 2.0)
	player.damage_modifiers.add(crit200)
	for n in n0:
		n.queue_free()
	await process_frame
	_fire(stage, _spell(5.0), target.global_position, player)
	await _frames(20)
	var n2 := _numbers(hit_area)
	_check(n2.size() == 1 and (n2[0].get_child(0) as Label).text == "15" and n2[0].crit_tier == 2 and _color(n2[0]) == orange,
		"projectile, 200% crit: \"15\" in orange (tier 2)")

	# 300% -> guaranteed tier 3, red, on a gated container hit.
	player.damage_modifiers.add(DamageModifier.crit(1.0, 2.0))
	var box_area := _area(stage)
	var def := ContainerDefinition.new()
	def.max_hp = 999
	var box: DestroyableContainer = preload("res://scenes/destroyable_container.tscn").instantiate()
	box.definition = def
	box.position = Vector2(800, 600)
	box_area.add_child(box)
	await _frames(2)
	_fire(stage, _spell(5.0), box.global_position, player)
	await _frames(20)
	var nb := _numbers(box_area)
	_check(nb.size() == 1 and (nb[0].get_child(0) as Label).text == "20" and nb[0].crit_tier == 3 and _color(nb[0]) == red,
		"container projectile, 300% crit: \"20\" in red (tier 3)")

	# 100% exactly -> tier 1 yellow (chance 1.0 alone).
	player.damage_modifiers = DamageModifiers.new()
	player.damage_modifiers.add(DamageModifier.crit(1.0, 2.0))
	var y_area := _area(stage)
	var ye: Enemy = preload("res://scenes/enemy.tscn").instantiate()
	ye.position = Vector2(1200, 600)
	y_area.add_child(ye)
	await _frames(2)
	_fire(stage, _spell(5.0), ye.global_position, player)
	await _frames(20)
	var ny := _numbers(y_area)
	_check(ny.size() == 1 and (ny[0].get_child(0) as Label).text == "10" and ny[0].crit_tier == 1 and _color(ny[0]) == yellow,
		"projectile, 100% crit: \"10\" in yellow (tier 1)")

	print("[208] failures: ", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)
