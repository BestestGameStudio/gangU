class_name StatModifier
extends RefCounted
## (#268) One change to one player stat, from one gameplay source (spell,
## item, relic, dungeon effect...). Owned by a PlayerStats collection.
##
## OP:
##   FLAT    - added to the base. For the fraction stats (damage_amp, armor,
##             cooldown_reduction) this is "percentage points": +0.1 = +10%.
##   PERCENT - multiplies (base + flats): +0.2 = +20%, -0.3 = -30%. Meant for
##             the base-scaled stats (max_hp, move_speed).
##
## DURATION:
##   > 0  - TIMED: expires after that many seconds of PlayerStats.tick time.
##   <= 0 - RUN-SCOPED ("permanent"): stays until removed or until the run
##          ends. The run ends with a scene reload (#6), which frees the
##          Player and its PlayerStats, so nothing carries across runs.

enum Op { FLAT, PERCENT }

var stat: StringName
var op: Op = Op.FLAT
var value: float = 0.0
var duration: float = 0.0
## Seconds left for TIMED modifiers; set by PlayerStats.add.
var time_left: float = 0.0
## Optional logical source id, used by PlayerStats.remove_source/add_unique.
var source: StringName = &""

func is_timed() -> bool:
	return duration > 0.0

static func flat(p_stat: StringName, p_value: float, p_duration: float = 0.0, p_source: StringName = &"") -> StatModifier:
	return _make(p_stat, Op.FLAT, p_value, p_duration, p_source)

static func percent(p_stat: StringName, p_value: float, p_duration: float = 0.0, p_source: StringName = &"") -> StatModifier:
	return _make(p_stat, Op.PERCENT, p_value, p_duration, p_source)

static func _make(p_stat: StringName, p_op: Op, p_value: float, p_duration: float, p_source: StringName) -> StatModifier:
	var m := StatModifier.new()
	m.stat = p_stat
	m.op = p_op
	m.value = p_value
	m.duration = p_duration
	m.source = p_source
	return m
