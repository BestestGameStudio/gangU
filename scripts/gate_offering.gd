class_name GateOffering
extends Resource
## #350: a dungeon offering is NORMAL or RED by chance. There is no rank
## system and no progression gating (Colin, 2026-11-08); ranks stay out of
## scope until Colin decides otherwise.
##
## A hub gate that carries an offering rolls its gate_type from this resource
## ONCE per run; Main caches the roll per gate, so the type stays fixed until
## death (the death restart reloads Main and clears the record). The type
## carries the existing semantics: NORMAL allows retreat, RED locks the player
## in until the objective is complete (D12, applied in main.gd from the type
## of the gate actually entered).
##
## The production distribution is 50/50 (Colin, 2026-11-08). An unset
## red_chance still keeps the gate's authored type for tests and tooling.

const UNSET := -1.0

## Probability in [0, 1] that the offering rolls RED; otherwise NORMAL.
## Left at UNSET (any negative value) the roll is disabled.
@export var red_chance: float = UNSET

func is_set() -> bool:
	return red_chance >= 0.0

## Returns the type to present: the authored type while the chance is unset,
## otherwise RED with probability red_chance (clamped to [0, 1]) and NORMAL
## otherwise. Pass a seeded rng for deterministic tests.
func roll(authored: Gate.GateType, rng: RandomNumberGenerator = null) -> Gate.GateType:
	if not is_set():
		return authored
	var r := rng.randf() if rng != null else randf()
	return Gate.GateType.RED if r < clampf(red_chance, 0.0, 1.0) else Gate.GateType.NORMAL
