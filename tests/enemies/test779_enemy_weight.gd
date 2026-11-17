extends SceneTree
## Data-only weights: serialized defaults, assignment and unchanged push behavior.
var failures := 0
const EXPECTED := {
 "beast_boss": 5.0, "bird": 0.5, "defense_wave_boss": 3.0,
 "fishy": 0.75, "head_boss": 4.0, "mustache_barricader": 1.0,
 "mustache_warlord": 3.0, "mustache_warrior": 1.0,
 "overworld_fishy": 0.75, "overworld_guard": 1.0,
 "overworld_migrant": 1.0, "overworld_patrol": 1.0,
 "red_mustache": 1.0, "scorpion": 2.0, "slime": 1.5, "slime_guard": 1.5,
 "slime_patrol": 1.5, "wolf": 1.0,
}
func check(ok: bool, label: String) -> void:
 print("[779] ", label, ": ", ok)
 if not ok: failures += 1
func _initialize() -> void:
 check(EnemyDefinition.new().weight == 1.0, "new definition baseline")
 var count := 0
 for file in DirAccess.get_files_at("res://data/enemies"):
  if not file.ends_with(".tres"): continue
  count += 1
  var key := file.get_basename()
  check(EXPECTED.has(key), "definition covered: " + key)
  var definition := load("res://data/enemies/" + file) as EnemyDefinition
  check(definition != null and definition.weight == EXPECTED.get(key, -1), "serialized weight: " + key)
  var enemy := Enemy.new()
  enemy.definition = definition
  check(enemy.weight == definition.weight, "runtime copy: " + key)
  enemy.hp = enemy.max_hp
  enemy.knockback(Vector2(500, 0))
  check(enemy._knockback == Vector2(500, 0), "weight does not scale knockback: " + key)
  enemy.free()
 check(count == EXPECTED.size(), "all definitions found")
 for scene in ["enemy", "enemy_red_mustache", "enemy_barricader", "enemy_bird", "enemy_fishy", "enemy_wolf", "enemy_slime", "enemy_scorpion", "bosses/mustache_warlord", "bosses/head_boss", "bosses/beast_boss", "bosses/defense_wave_boss"]:
  var packed := load("res://game/enemies/" + scene + ".tscn") as PackedScene
  var instance := packed.instantiate() as Enemy
  check(instance != null and instance.definition != null, "real scene definition: " + scene)
  if instance != null and instance.definition != null:
   check(instance.weight == instance.definition.weight, "real scene serialized assignment: " + scene)
  instance.free()
 var tuned := Enemy.new()
 var custom := EnemyDefinition.new()
 custom.weight = 2.25
 tuned.definition = custom
 check(tuned.weight == 2.25, "fractional assignment")
 tuned.weight = 7.5
 check(custom.weight == 2.25, "runtime override leaves resource unchanged")
 tuned.definition = EnemyDefinition.new()
 check(tuned.weight == 1.0, "definition replacement copies weight")
 tuned.free()
 quit(1 if failures else 0)
