extends SceneTree
var failures := 0
func check(ok: bool, label: String):
 print("[793] ",label,": ",ok)
 if not ok: failures += 1
func _initialize(): run.call_deferred()
func run():
 var area:=Node2D.new();root.add_child(area);current_scene=area
 var player:=load("res://game/player/player.tscn").instantiate() as Player;area.add_child(player)
 var victim:=load("res://game/enemies/bosses/beast_boss.tscn").instantiate() as Enemy;area.add_child(victim)
 victim.set_physics_process(false)
 var s:=load("res://data/spells/water_shot_tide.tres") as Spell
 check(s.water_shot_contact_interval==0.5,"existing tick retained")
 var p:=WaterShotProjectile.new();p.prepare_shape();p.setup(s,Vector2.RIGHT,player);area.add_child(p)
 p.set_physics_process(false);p.hovering=false;p._life_t=1.0
 var hp:=victim.hp
 p._on_body_entered(victim)
 check(victim.hp<hp,"initial travelling hit")
 hp=victim.hp;p._life_t=1.2;p._on_body_entered(victim)
 check(victim.hp==hp,"travelling recontact before0.5 refused")
 p._life_t=1.5;p._on_body_entered(victim)
 check(victim.hp<hp,"later travelling pass re-hits same enemy")
 hp=victim.hp;p.hovering=true;p._life_t=1.7;p._on_body_entered(victim)
 check(victim.hp==hp,"hover transition shares same timer")
 p._life_t=2.0;p._on_body_entered(victim)
 check(victim.hp<hp,"hover tick repeats")
 hp=victim.hp;p.hovering=false;p._life_t=2.5;p._on_body_entered(victim)
 check(victim.hp<hp,"second released pass repeats")
 for name in ["water_shot_hover","water_shot_reservoir"]:
  var other:=WaterShotProjectile.new();other.prepare_shape();other.setup(load("res://data/spells/"+name+".tres"),Vector2.RIGHT,player);area.add_child(other)
  other.set_physics_process(false);other._hit_bodies.append(victim);other._life_t=10.0
  check(not other._can_hit(victim),name+" remains one-hit per enemy")
 area.queue_free();await process_frame;quit(1 if failures else 0)
