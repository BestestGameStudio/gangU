extends SceneTree
## #177 harness: Mustache Warrior art for the common enemy + the Mustache
## Warlord boss built from the same sheet.
## Run: godot --headless --path . --script res://scripts/test177_mustache_warrior.gd
##
## Legs:
##   (A) sheet + SpriteFrames: every animation row present with the expected
##       frame count and loop flag; the packed sheet is 512x480.
##   (B) enemy.tscn: animated "Sprite" (EnemySprite, nearest filter) replaces
##       the Spikes polygon; collision r13 and hp 30 unchanged; idles on mount.
##   (C) hurt: a non-lethal hit plays "hurt", then locomotion resumes.
##   (D) contact swing: a real chase/contact hit plays "attack". REAL frames.
##   (E) death: enemy still frees itself (#110 contract); a detached corpse
##       plays "death" and frees itself afterwards.
##   (F) warlord scene: Enemy + definition (hp 300) + warlord behavior,
##       2x sprite, telegraph + health bar nodes.
##   (G) ELIMINATION path: the warlord as boss_scene spawns after the mob,
##       joins "boss", and its kill completes the objective.
##   (H) attacks (REAL frames, collisions off like #99): mid range -> lunge
##       wind-up line telegraph -> dash hit; close -> spin ring -> damage;
##       far -> volley cone -> >= 5 orbs; enraged volley -> two wider waves.
##   (I) orb art: boss orbs carry the WarlordOrbVisual override (code-drawn
##       Dart/Visual hidden), player spells keep the default look, and an
##       orb hit damages the player and spawns the impact pop.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[177] ", name, " -> PASS")
	else:
		failures += 1
		print("[177] ", name, " -> FAIL")

func _physics(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	await _leg_frames()
	await _leg_enemy()
	await _leg_warlord_scene()
	await _leg_elimination()
	await _leg_attacks()
	await _leg_orb_visual()
	print("[177] DONE failures=", failures)
	quit(failures)

# (A) -----------------------------------------------------------------------
func _leg_frames() -> void:
	var tex: Texture2D = load("res://assets/sprites/mustache_warrior.png")
	_check(tex != null and tex.get_width() == 512 and tex.get_height() == 480,
		"(A) packed sheet loads at 512x480")
	var sf: SpriteFrames = load("res://resources/sprites/mustache_warrior_frames.tres")
	_check(sf != null, "(A) SpriteFrames loads")
	if sf == null:
		return
	var want := {
		&"idle": [4, true], &"walk": [8, true], &"attack": [4, false],
		&"hurt": [3, false], &"death": [6, false], &"lunge": [2, false],
		&"spin": [3, true], &"ranged": [3, false], &"windup_lunge": [1, true],
		&"windup_spin": [1, true], &"windup_ranged": [2, true],
	}
	for anim in want:
		var ok: bool = sf.has_animation(anim) \
			and sf.get_frame_count(anim) == want[anim][0] \
			and sf.get_animation_loop(anim) == want[anim][1]
		_check(ok, "(A) %s: %d frames, loop=%s" % [anim, want[anim][0], want[anim][1]])

# (B)-(E) -------------------------------------------------------------------
func _leg_enemy() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var e: Enemy = load("res://scenes/enemy.tscn").instantiate()
	e.position = Vector2(200, 200)
	world.add_child(e)
	await process_frame
	var spr := e.get_node_or_null("Sprite") as EnemySprite
	_check(spr != null, "(B) enemy has an EnemySprite 'Sprite' child")
	_check(e.sprite == spr, "(B) Enemy.sprite resolves the art")
	_check(not e.has_node("Spikes"), "(B) legacy Spikes polygon retired")
	_check(spr != null and spr.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "(B) nearest filter (pixel art)")
	var cs := e.get_node("CollisionShape2D") as CollisionShape2D
	_check(is_equal_approx((cs.shape as CircleShape2D).radius, 13.0), "(B) collision radius unchanged (13)")
	_check(e.hp == 30, "(B) hp 30 unchanged")
	_check(spr != null and spr.animation == &"idle" and spr.is_playing(), "(B) idles on mount (no player)")
	if spr == null:
		world.queue_free()
		return

	# (C) hurt one-shot, then back to locomotion.
	e.apply_damage(5)
	_check(spr.animation == &"hurt", "(C) non-lethal hit plays hurt")
	await _physics(40)
	_check(spr.current_action() == &"" and spr.animation == &"idle", "(C) locomotion resumes after hurt")

	# (E) death: enemy frees, corpse plays death then frees.
	e.apply_damage(999)
	await process_frame
	await process_frame
	_check(not is_instance_valid(e), "(E) enemy freed on death (contract unchanged)")
	var corpses := get_nodes_in_group(&"enemy_corpses")
	_check(corpses.size() == 1, "(E) one corpse spawned")
	if corpses.size() == 1:
		var c := corpses[0] as AnimatedSprite2D
		_check(c.animation == &"death" and c.is_playing(), "(E) corpse plays death")
		_check(c.get_parent() == world, "(E) corpse parented to the area")
		await _physics(150)
		_check(not is_instance_valid(c), "(E) corpse frees itself after the animation")

	# (D) contact swing via the real chase/contact behavior.
	var p: Player = load("res://scenes/player.tscn").instantiate()
	p.position = Vector2(400, 200)
	p.collision_layer = 0
	p.collision_mask = 0
	world.add_child(p)
	var e2: Enemy = load("res://scenes/enemy.tscn").instantiate()
	e2.position = Vector2(370, 200)
	e2.collision_layer = 0
	e2.collision_mask = 0
	p.add_to_group("player")
	world.add_child(e2)
	var swung := false
	for i in 120:
		await physics_frame
		if p.hp < p.max_hp:
			swung = e2.sprite.animation == &"attack"
			break
	_check(p.hp < p.max_hp, "(D) contact hit landed")
	_check(swung, "(D) contact hit plays the attack swing")
	_check(e2.sprite.flip_h == false, "(D) faces right toward a player on the right")
	p.remove_from_group("player")
	world.queue_free()
	await process_frame

# (F) -----------------------------------------------------------------------
func _leg_warlord_scene() -> void:
	var scene: PackedScene = load("res://scenes/mustache_warlord.tscn")
	_check(scene != null, "(F) mustache_warlord.tscn loads")
	if scene == null:
		return
	var world := Node2D.new()
	root.add_child(world)
	var b: Enemy = scene.instantiate() as Enemy
	_check(b != null, "(F) warlord root is an Enemy")
	if b == null:
		world.queue_free()
		return
	world.add_child(b)
	await process_frame
	_check(b.max_hp == 300 and b.hp == 300, "(F) definition applied (hp 300)")
	_check(b._behavior is EnemyBehaviorWarlord, "(F) warlord behavior slotted via the #99 seam")
	_check(b.sprite != null and b.sprite.scale == Vector2(2, 2), "(F) 2x Mustache Warrior sprite")
	_check(b.get_node_or_null("Telegraph") is BossTelegraph, "(F) telegraph node")
	_check(b.get_node_or_null("HealthBar") is BossHealthBar, "(F) health bar node")
	_check(b.has_signal("died"), "(F) died signal (boss_scene contract)")
	world.queue_free()
	await process_frame

# (G) -----------------------------------------------------------------------
func _leg_elimination() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var mob: Enemy = load("res://scenes/enemy.tscn").instantiate()
	mob.position = Vector2(100, 100)
	world.add_child(mob)
	var obj := DungeonObjective.new()
	obj.objective_type = DungeonObjective.ObjectiveType.ELIMINATION
	obj.target_count = 1
	obj.boss_scene = load("res://scenes/mustache_warlord.tscn")
	obj.boss_spawn_position = Vector2(300, 300)
	var spawned: Array = []
	obj.boss_spawned.connect(func(boss: Node) -> void: spawned.append(boss))
	world.add_child(obj)
	await process_frame
	mob.apply_damage(999)
	await process_frame
	await process_frame
	_check(spawned.size() == 1 and spawned[0] is Enemy, "(G) warlord spawned by ELIMINATION after the mob")
	if spawned.size() != 1:
		world.queue_free()
		return
	var boss: Enemy = spawned[0]
	_check(boss.is_inside_tree() and boss.is_in_group(&"boss"), "(G) boss in tree and in 'boss' group")
	_check(boss.global_position == Vector2(300, 300), "(G) spawned at boss_spawn_position")
	boss.apply_damage(999)
	await process_frame
	_check(obj.is_cleared(), "(G) warlord kill completes the objective")
	world.queue_free()
	await process_frame

# (H) -----------------------------------------------------------------------
func _arena(player_offset: Vector2) -> Array:
	var world := Node2D.new()
	root.add_child(world)
	var p: Player = load("res://scenes/player.tscn").instantiate()
	p.position = Vector2(500, 300) + player_offset
	p.collision_layer = 0
	p.collision_mask = 0
	world.add_child(p)
	var b: Enemy = load("res://scenes/mustache_warlord.tscn").instantiate()
	b.position = Vector2(500, 300)
	b.collision_layer = 0
	b.collision_mask = 0
	p.add_to_group("player")
	world.add_child(b)
	return [world, p, b]

func _orbs(world: Node) -> Array:
	var out: Array = []
	for c in world.get_children():
		if c is Projectile:
			out.append(c)
	return out

func _count_projectiles(world: Node) -> int:
	var n := 0
	for c in world.get_children():
		if c is Projectile:
			n += 1
	return n

func _leg_attacks() -> void:
	# Lunge: mid range, boss held in place so the range pick is exact.
	var a := _arena(Vector2(200, 0))
	var world: Node2D = a[0]
	var p: Player = a[1]
	var b: Enemy = a[2]
	await process_frame
	b.speed = 0.0
	var beh := b._behavior as EnemyBehaviorWarlord
	var tele := b.get_node("Telegraph") as BossTelegraph
	var saw_line := false
	var saw_lunge_anim := false
	var saw_glow := false
	for i in 200:
		await physics_frame
		if beh.state == EnemyBehaviorWarlord.State.WINDUP and tele.mode == BossTelegraph.Mode.LINE:
			saw_line = true
			saw_glow = saw_glow or b.sprite.self_modulate != Color.WHITE
		if beh.state == EnemyBehaviorWarlord.State.LUNGE and b.sprite.animation == &"lunge":
			saw_lunge_anim = true
		if beh.state == EnemyBehaviorWarlord.State.RECOVER:
			break
	_check(saw_line, "(H) lunge wind-up shows the line telegraph")
	_check(saw_glow, "(H) wind-up glows the sprite")
	_check(saw_lunge_anim, "(H) dash plays the lunge animation")
	_check(p.hp == p.max_hp - EnemyBehaviorWarlord.LUNGE_DAMAGE, "(H) lunge hits once (hp %d)" % p.hp)
	p.remove_from_group("player")
	world.queue_free()
	await process_frame

	# Spin: close range.
	a = _arena(Vector2(60, 0))
	world = a[0]
	p = a[1]
	b = a[2]
	await process_frame
	b.speed = 0.0
	beh = b._behavior as EnemyBehaviorWarlord
	tele = b.get_node("Telegraph") as BossTelegraph
	var saw_ring := false
	var saw_spin := false
	for i in 220:
		await physics_frame
		if beh.state == EnemyBehaviorWarlord.State.WINDUP and tele.mode == BossTelegraph.Mode.RING:
			saw_ring = true
		if beh.state == EnemyBehaviorWarlord.State.SPIN and b.sprite.animation == &"spin":
			saw_spin = true
		if beh.state == EnemyBehaviorWarlord.State.RECOVER:
			break
	_check(saw_ring and saw_spin, "(H) close range: ring telegraph then spin animation")
	_check(p.hp <= p.max_hp - EnemyBehaviorWarlord.SPIN_DAMAGE, "(H) spin damages the player (hp %d)" % p.hp)
	p.remove_from_group("player")
	world.queue_free()
	await process_frame

	# Volley: far range, then enraged.
	for enraged in [false, true]:
		a = _arena(Vector2(400, 0))
		world = a[0]
		p = a[1]
		b = a[2]
		await process_frame
		b.speed = 0.0
		if enraged:
			b.apply_damage(200)
		beh = b._behavior as EnemyBehaviorWarlord
		tele = b.get_node("Telegraph") as BossTelegraph
		var saw_cone := false
		var most := 0
		for i in 220:
			await physics_frame
			if beh.state == EnemyBehaviorWarlord.State.WINDUP and tele.mode == BossTelegraph.Mode.CONE:
				saw_cone = true
			most = maxi(most, _count_projectiles(world))
			if beh.state == EnemyBehaviorWarlord.State.RECOVER:
				await physics_frame
				most = maxi(most, _count_projectiles(world))
				break
		var want: int = 2 * EnemyBehaviorWarlord.VOLLEY_SHOTS_ENRAGED if enraged else EnemyBehaviorWarlord.VOLLEY_SHOTS
		_check(saw_cone, "(H) volley shows the cone telegraph (enraged=%s)" % enraged)
		_check(most >= want, "(H) volley fires >= %d orbs (got %d, enraged=%s)" % [want, most, enraged])
		p.remove_from_group("player")
		world.queue_free()
		await process_frame

# (I) -----------------------------------------------------------------------
func _leg_orb_visual() -> void:
	# Boss volley at a COLLIDING player in the orb lane: art + hit + pop.
	var world := Node2D.new()
	root.add_child(world)
	var p: Player = load("res://scenes/player.tscn").instantiate()
	p.position = Vector2(800, 300)
	world.add_child(p)
	p.add_to_group("player")
	var b: Enemy = load("res://scenes/mustache_warlord.tscn").instantiate()
	b.position = Vector2(500, 300)
	b.collision_layer = 0
	b.collision_mask = 0
	world.add_child(b)
	await process_frame
	b.speed = 0.0
	var beh := b._behavior as EnemyBehaviorWarlord
	var checked := false
	var art_ok := false
	var pops := 0
	for i in 400:
		await physics_frame
		pops = maxi(pops, get_nodes_in_group(&"warlord_orb_pops").size())
		var orbs := _orbs(world)
		if not checked and orbs.size() > 0:
			checked = true
			art_ok = true
			for o: Projectile in orbs:
				var v := o.get_node_or_null("VisualOverride")
				if not (v is WarlordOrbVisual and not o.get_node("Dart").visible and not o.get_node("Visual").visible):
					art_ok = false
		if checked and p.hp < p.max_hp and pops > 0:
			break
	_check(checked and art_ok, "(I) boss orbs wear WarlordOrbVisual (default Dart/Visual hidden)")
	_check(p.hp < p.max_hp, "(I) orb hit damages the player (hp %d)" % p.hp)
	_check(pops > 0, "(I) orb impact pop spawned")
	_check(beh != null, "(I) warlord behavior present")
	p.remove_from_group("player")
	world.queue_free()
	await process_frame
	# Player spells are untouched by the #177 override machinery: no override.
	# (#210: the DEFAULT visual for a mapped spell like Mana Shot is now the
	# supplied-art sprite, with the code-drawn Dart/Visual hidden.)
	var w2 := Node2D.new()
	root.add_child(w2)
	var pr: Projectile = load("res://scenes/projectile.tscn").instantiate()
	pr.setup(load("res://resources/spells/mana_shot.tres"), Vector2.RIGHT, null)
	w2.add_child(pr)
	await process_frame
	_check(pr.get_node_or_null("VisualOverride") == null and pr.get_node_or_null("Sprite") != null
		and not pr.get_node("Dart").visible and not pr.get_node("Visual").visible,
		"(I) player projectiles keep the default visual (no override; #210 sprite for mapped spells)")
	w2.queue_free()
	await process_frame
