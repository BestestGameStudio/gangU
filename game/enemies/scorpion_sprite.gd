extends EnemySprite
## Attacks and miss-stun hold their telegraph/forward pose even when hit.
## Enemy still flashes and emits health_changed; ordinary sprites unchanged.
func _on_health_changed(current: int, max_hp_value: int) -> void:
	var e := get_parent() as EnemyScorpion
	if e != null and e._behavior is EnemyBehaviorScorpion:
		var state := (e._behavior as EnemyBehaviorScorpion).state
		if e.is_stunned():
			_last_hp = current
			return
		if state not in [EnemyBehaviorScorpion.State.CHASE,EnemyBehaviorScorpion.State.BURIED]:
			_last_hp = current
			return
	super._on_health_changed(current,max_hp_value)

## Source-rig stinger-barb mask only, never the tail segment chain.
const TAIL_SHADER := preload("res://game/enemies/scorpion_tail_tint.gdshader")
const TAIL_MASK := preload("res://assets/sprites/scorpion_tail_mask.png")
const TAIL_DIRECTIONS := ["s","se","e","ne","n","nw","w","sw"]
func _ready() -> void:
	super._ready()
	var ink := ShaderMaterial.new()
	ink.shader = TAIL_SHADER
	ink.set_shader_parameter("tail_mask",TAIL_MASK)
	material = ink

func _process(delta: float) -> void:
	super._process(delta)
	var strength := 0.0
	var direction := 0
	var e := get_parent() as EnemyScorpion
	if e != null and e._behavior is EnemyBehaviorScorpion:
		var b := e._behavior as EnemyBehaviorScorpion
		if b.state == b.State.STING_WINDUP and not e.is_stunned() and String(animation).begins_with("attack_") and frame < 2:
			direction = TAIL_DIRECTIONS.find(String(animation).trim_prefix("attack_"))
			strength = 0.55+0.45*(0.5+0.5*sin(TAU*5.0*b._time))
	(material as ShaderMaterial).set_shader_parameter("mask_cell",Vector2(maxi(direction,0),mini(frame,1)))
	(material as ShaderMaterial).set_shader_parameter("warning_strength",strength)
