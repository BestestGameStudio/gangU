class_name HitContext
extends RefCounted
## Geometry for one incoming hit, in world space. Receivers may opt into
## modifiers_for_hit(context) BEFORE DamageCalc rolls/truncates. This does
## not change hit selection, acceptance, source gates or HP mutation.
enum Shape { UNLOCATED, PROJECTILE, AREA, CONTACT }
var shape: Shape = Shape.UNLOCATED
## Caller identity is separate from shape and OnHit delivery (both hammer
## areas report MELEE; shield reports CONTACT but is geometrically an area).
var kind: StringName = &"unlocated"
var origin := Vector2.ZERO
var end := Vector2.ZERO
var radius := 0.0

static func projectile(from: Vector2, to: Vector2, hit_radius: float) -> HitContext:
	var c := HitContext.new()
	c.shape = Shape.PROJECTILE
	c.kind = &"projectile"
	c.origin = from
	c.end = to
	c.radius = maxf(hit_radius, 0.0)
	return c

static func area(center: Vector2, hit_radius: float, caller: StringName = &"area") -> HitContext:
	var c := HitContext.new()
	c.shape = Shape.AREA
	c.kind = caller
	c.origin = center
	c.end = center
	c.radius = maxf(hit_radius, 0.0)
	return c

static func contact(at: Vector2) -> HitContext:
	var c := HitContext.new()
	c.shape = Shape.CONTACT
	c.kind = &"contact"
	c.origin = at
	c.end = at
	return c

## A swept projectile circle or stationary area/contact against a weak spot.
## UNLOCATED never guesses a position (e.g. a source-less damage tick).
func overlaps_circle(center: Vector2, other_radius: float) -> bool:
	if shape == Shape.UNLOCATED:
		return false
	var nearest := Geometry2D.get_closest_point_to_segment(center, origin, end) if shape == Shape.PROJECTILE else origin
	return nearest.distance_squared_to(center) <= pow(radius + maxf(other_radius, 0.0), 2.0)

## Return the original collection by identity for every non-opt-in receiver.
## An opt-in receiver must return the complete incoming modifier collection;
## null means no receiver modifiers, just as in DamageCalc.compute today.
static func receiver_modifiers(target: Object, context: HitContext = null) -> DamageModifiers:
	if context != null and target.has_method(&"modifiers_for_hit"):
		return target.call(&"modifiers_for_hit", context) as DamageModifiers
	return target.get(&"damage_modifiers") as DamageModifiers
