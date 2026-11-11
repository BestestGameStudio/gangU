class_name HammerVortex
extends Node2D
## #370 Stone Hammer Crush Signature: while the spell key is held, a vortex
## sits on the point the hammer will strike (it follows the aim, clamped to
## the spell's range) and pulls every living enemy within
## spell.hammer_vortex_radius toward its centre. Releasing the key swings the
## hammer (SpellCaster.release_charge). Pulling uses Enemy.knockback, so a
## pulled enemy's behaviour waits while it is dragged and walls stop it.

const PULL_GAIN := 6.0 ## px/s of pull per px of distance, so it eases in at the centre
const COLOR := Color(0.55, 0.45, 0.35)

var spell: Spell
## Returns the world point the hammer will strike (the caster's aim).
var target_provider: Callable
var radius := 0.0
var elapsed := 0.0
## Enemies pulled on the latest physics step.
var pulled := 0

static func spawn(parent: Node, p_spell: Spell, p_provider: Callable, p_radius: float) -> HammerVortex:
	var v := HammerVortex.new()
	v.name = "HammerVortex"
	v.spell = p_spell
	v.target_provider = p_provider
	v.radius = p_radius
	parent.add_child(v)
	if p_provider.is_valid():
		v.global_position = p_provider.call()
	return v

func _ready() -> void:
	add_to_group(&"hammer_vortexes")
	z_index = 1

func _physics_process(delta: float) -> void:
	elapsed += delta
	if target_provider.is_valid():
		global_position = target_provider.call()
	pulled = 0
	for e: Enemy in get_tree().get_nodes_in_group(&"enemies"):
		if not is_instance_valid(e) or e.is_queued_for_deletion() or e.hp <= 0:
			continue
		var off: Vector2 = global_position - e.global_position
		var d := off.length()
		if d > radius or d < 2.0:
			continue
		e.knockback(off / d * minf(spell.hammer_vortex_pull, d * PULL_GAIN))
		pulled += 1
	queue_redraw()

func _draw() -> void:
	var grow := clampf(elapsed / 0.25, 0.0, 1.0)
	var r := radius * grow
	draw_circle(Vector2.ZERO, r, Color(COLOR.r, COLOR.g, COLOR.b, 0.12))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 56, Color(0.85, 0.75, 0.6, 0.55), 2.0)
	# Spiral arms turning inward.
	var spin := elapsed * 5.0
	for arm in 4:
		var pts := PackedVector2Array()
		for i in 16:
			var f := float(i) / 15.0
			var a := spin + TAU * arm / 4.0 + f * 2.4
			pts.append(Vector2(cos(a), sin(a)) * r * (1.0 - f * 0.9))
		draw_polyline(pts, Color(0.9, 0.8, 0.6, 0.7), 2.0)
	draw_circle(Vector2.ZERO, 6.0, Color(0.25, 0.2, 0.15, 0.8))
