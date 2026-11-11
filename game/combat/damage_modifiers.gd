class_name DamageModifiers
extends RefCounted
## Per-actor collection of DamageModifier sources, read by DamageCalc.

var _items: Array[DamageModifier] = []

func add(m: DamageModifier) -> void:
	_items.append(m)

func remove(m: DamageModifier) -> void:
	_items.erase(m)

func items() -> Array[DamageModifier]:
	return _items
