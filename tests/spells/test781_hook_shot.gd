extends SceneTree
var failures := 0
var counts: Array[int] = []
func check(ok: bool, label: String) -> void:
 print("[781] ", label, ": ", ok)
 if not ok: failures += 1
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var area := Node2D.new(); root.add_child(area); current_scene = area
 var player := (load("res://game/player/player.tscn") as PackedScene).instantiate() as Player
 area.add_child(player); player.global_position = Vector2(100, 100)
 check(Spell.new().range == 600.0, "global projectile range default unchanged")
 var s := load("res://data/spells/hook_shot.tres") as Spell
 check(s.damage == 0 and s.cast_mode() == Spell.CastMode.HOOK, "zero damage hook definition")
 check(HookReel.speed_for(s, 0.5) == 2400 and HookReel.speed_for(s, 5) == 300, "weight speed and cap")
 s = s.duplicate(); s.displacement_force = 2
 check(HookReel.speed_for(s, 1) == 2400, "higher displacement faster")
 s.displacement_force = 1
 var near := (load("res://game/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
 var far := (load("res://game/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
 area.add_child(near); area.add_child(far)
 near.set_physics_process(false); far.set_physics_process(false)
 near.global_position = Vector2(230, 100); far.global_position = Vector2(350, 100)
 var hp := near.hp
 var hook := HookShot.new(); hook.prepare_shape(); hook.setup(s, Vector2.RIGHT, player)
 hook.destination = Vector2(500, 100); hook.resolved.connect(func(n): counts.append(n))
 area.add_child(hook); hook.global_position = player.global_position
 await physics_frame; await physics_frame
 hook._physics_process(0.5)
 check(counts == [1], "sweep acquires first enemy only")
 check(is_instance_valid(near.displacement_owner) and not is_instance_valid(far.displacement_owner), "first enemy owns reel")
 check(near.hp == hp, "hook deals no damage")
 var reel := near.displacement_owner as HookReel
 reel.set_physics_process(false)
 var initial := near.global_position
 reel._physics_process(0.05)
 check(near.global_position.x < initial.x, "reels toward player")
 player.global_position = Vector2(100, 220)
 reel._physics_process(0.05)
 check(reel.reel_velocity.y > 0 and reel.reel_velocity.x < 0, "moving player retargets with lateral velocity")
 check(reel.reel_velocity.length() <= HookReel.speed_for(s, near.weight), "inertia stays speed capped")
 check(HookReel.begin(area, near, player, s) == null, "no second owner on hooked enemy")
 reel.queue_free(); await process_frame
 check(not is_instance_valid(near.displacement_owner), "cleanup releases enemy")
 var progress := SpellProgress.new(); var caster := player.get_node("SpellCaster") as SpellCaster
 progress._caster = caster; caster.unlock_spell(s)
 var row := SpellUpgrade.new(); row.id = &"hook_test"; row.source_spell = s
 row.quest = SpellUpgradeQuest.new(); row.quest.kind = SpellUpgradeQuest.Kind.HOOK_STREAK; row.quest.goal = 3
 progress.upgrades.append(row)
 progress._on_hook_resolved(s, 1); progress._on_hook_resolved(s, 0)
 check(progress.qualification_count(row) == 0, "miss resets unfinished streak")
 for i in 3: progress._on_hook_resolved(s, 1)
 check(progress.qualification_count(row) == 3, "three consecutive hooks qualify")
 progress._on_hook_resolved(s, 0)
 check(progress.qualification_count(row) == 3, "completed quest stays complete")
 progress.free()
 for name in ["fishy", "overworld_fishy"]:
  var definition := load("res://data/enemies/" + name + ".tres") as EnemyDefinition
  var entry := definition.reward_table.roll([])
  check(entry != null and entry.spell.resource_path == "res://data/spells/hook_shot.tres", name + " guaranteed hook drop")
  check(definition.reward_table.roll([entry]) == null, name + " no repeat after grant")
 area.queue_free(); await process_frame
 quit(1 if failures else 0)
