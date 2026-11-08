extends SceneTree
## #109 acceptance driver (headless). Proves Fire Ball responsiveness fixes:
##   swept   - at 18 physics tps (50px steps > 2x envelope) the projectile
##             still registers on a stationary enemy for EVERY phase offset
##             (pre-fix tunneling misses phases)
##   flash   - apply_damage triggers the over-bright hit flash, then restores
##   radius  - shipped Fire Ball hit radius is the more forgiving 9.0
##   feel    - projectile Visual spins and pulses while flying
## Legs swept/flash/radius/feel FAIL on the old base - meaningful negative.

var fails := 0
var phase := 0
var t := 0.0

var _enemy: CharacterBody2D
var _projs: Array = []
var _fireball: Spell
var _root2d: Node2D
var _sweep_idx := 0
var _sweep_misses := 0
const SWEEP_DISTANCES: Array[float] = [100.0, 104.0, 108.0, 112.0, 116.0, 120.0, 124.0, 128.0]

func _check(label: String, ok: bool) -> void:
	if not ok:
		fails += 1
	print("[109] ", label, " -> ", "PASS" if ok else "FAIL")

func _initialize() -> void:
	_root2d = Node2D.new()
	root.add_child(_root2d)
	_fireball = load("res://resources/spells/fire_ball.tres")
	_check("radius: shipped Fire Ball radius is 9.0 (was 7.0)", is_equal_approx(_fireball.radius, 9.0))
	# degraded frame rate: ~50px steps (#263 slowed Fire Ball to 520px/s, so
	# the tick rate drops from 18 to 10 to keep the tunneling stress intact)
	Engine.physics_ticks_per_second = 10
	_spawn_enemy(Vector2(SWEEP_DISTANCES[0], 0))
	_fire_at_enemy()

func _spawn_enemy(at: Vector2) -> void:
	if _enemy != null and is_instance_valid(_enemy):
		_enemy.queue_free()
	_enemy = load("res://scenes/enemy.tscn").instantiate()
	_enemy.speed = 0.0 # stationary target: pure registration measurement
	_enemy.position = at
	_root2d.add_child(_enemy)

func _fire_at_enemy() -> void:
	var p: Projectile = load("res://scenes/projectile.tscn").instantiate()
	p.setup(_fireball, Vector2.RIGHT, _root2d)
	p.position = Vector2.ZERO
	_root2d.add_child(p)
	_projs.append(p)

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0: # swept registration, one distance at a time
			if t > 1.0:
				if is_instance_valid(_enemy) and _enemy.hp >= _enemy.max_hp:
					_sweep_misses += 1
				if not is_instance_valid(_enemy):
					pass # died = registered
				_sweep_idx += 1
				if _sweep_idx < SWEEP_DISTANCES.size():
					_spawn_enemy(Vector2(SWEEP_DISTANCES[_sweep_idx], 0))
					_fire_at_enemy()
					t = 0.0
				else:
					_check("swept: 10tps ~50px steps register at ALL 8 phase offsets (misses=%d)" % _sweep_misses, _sweep_misses == 0)
					Engine.physics_ticks_per_second = 60
					phase = 1
					t = 0.0
		1: # flash on non-lethal damage
			if t > 0.3:
				_spawn_enemy(Vector2(400, 400))
				_enemy.apply_damage(10)
				_check("flash: non-lethal hit brightens the enemy that frame", _enemy.modulate.r > 1.5)
				phase = 2
				t = 0.0
		2:
			if t > 0.3:
				_check("flash: modulate restores after the flash window",
					is_instance_valid(_enemy) and _enemy.modulate.is_equal_approx(Color.WHITE))
				var p: Projectile = load("res://scenes/projectile.tscn").instantiate()
				p.setup(_fireball, Vector2.RIGHT, _root2d)
				p.position = Vector2(-600, -600)
				_root2d.add_child(p)
				_projs.append(p)
				phase = 3
				t = 0.0
		3: # spin/pulse over ~0.3s of flight
			if t > 0.05:
				var p: Projectile = _projs.back()
				_check("feel: visual scale is radius-scaled base (9/4=2.25)",
					is_instance_valid(p) and absf(p.get_node("Visual").scale.x - 2.25) < 0.6)
				phase = 4
				t = 0.0
		4:
			if t > 0.25:
				var p: Projectile = _projs.back()
				if is_instance_valid(p):
					_check("feel: diamond spins in flight (rotation advanced)", absf(p.get_node("Visual").rotation) > 1.0)
				else:
					_check("feel: diamond spins in flight (rotation advanced)", false)
				if fails == 0:
					print("[109] ALL PASS")
				print("[109] DONE fails=", fails)
				quit()
	return false
