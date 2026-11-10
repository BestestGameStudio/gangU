extends SceneTree
## #245: real ungrouped Player ownership, cosmetics, and unchanged summon contract.
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("[245] ", label, " -> ", "PASS" if ok else "FAIL")

func _initialize() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var p: Player = load("res://scenes/player.tscn").instantiate()
	stage.add_child(p)
	p.position = Vector2(100, 100)
	var manager := SummonManager.new()
	manager.caster_path = NodePath("../Player/SpellCaster")
	stage.add_child(manager)
	await process_frame
	var spell: Spell = load("res://resources/spells/summon_ally.tres")
	var caster: SpellCaster = p.get_node("SpellCaster")
	# #262: default spells self-bind at caster._ready; clear BOTH default
	# slots BEFORE the grant so the fixture's slot-0 flow is unchanged.
	caster.clear_slot(0)
	caster.clear_slot(1)
	caster.unlock_spell(spell)
	caster.assign_slot(0, spell)
	caster.cast_slot(0)
	await process_frame
	check(manager.live_count() == 1, "real spell cast through manager spawns one summon")
	var ally: Summon = get_first_node_in_group("summons")
	check(ally.player == p and ally._has_player_glow(), "real ungrouped Player wired before tree entry qualifies")
	check(ally.hp == 30 and ally.max_hp == 30, "health unchanged")
	check(ally._behavior != null, "existing guard behavior retained")
	var body: Polygon2D = ally.get_node("Body")
	check(body.color == Color(0.5, 0.7, 1, 1) and body.polygon.size() == 4, "placeholder Body preserved")
	check(ally.get_node("CollisionShape2D").shape.size == Vector2(20, 20), "collision unchanged")
	check(ally.GLOW_BLUE.b > ally.GLOW_BLUE.g and ally.GLOW_BLUE.g > ally.GLOW_BLUE.r, "halo is blue")
	ally._glow_time = ally.GLOW_PERIOD * 0.25
	check(is_equal_approx(ally._glow_strength(), 1.0), "gentle pulse peak")
	ally._glow_time = ally.GLOW_PERIOD * 0.75
	check(is_equal_approx(ally._glow_strength(), 0.76), "gentle pulse trough stays visible")
	ally._process(ally.GLOW_PERIOD * 3.0)
	check(ally._glow_time >= 0 and ally._glow_time < ally.GLOW_PERIOD, "pulse phase bounded")
	ally.player = null
	check(not ally._has_player_glow(), "unowned summon has no halo")
	var other := Node2D.new()
	stage.add_child(other)
	other.add_to_group(ActorCollision.PLAYER_GROUP)
	ally.player = other
	check(not ally._has_player_glow(), "nonPlayer even in player group has no halo")
	ally.player = p
	p.free()
	check(not ally._has_player_glow(), "freed Player owner has no halo")
	ally.player = null
	var signals_seen := [0, 0]
	ally.health_changed.connect(func(_a, _b): signals_seen[0] += 1)
	ally.died.connect(func(): signals_seen[1] += 1)
	ally.apply_damage(5)
	check(ally.hp == 25 and signals_seen[0] == 1, "damage and HP signal unchanged")
	ally.apply_damage(100)
	check(ally.hp == 0 and signals_seen[1] == 1, "death signal unchanged")
	await process_frame
	check(not is_instance_valid(ally), "dead summon tears down with halo")
	stage.queue_free()
	await process_frame
	print("[245] ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)
