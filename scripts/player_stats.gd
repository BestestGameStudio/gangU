class_name PlayerStats
extends RefCounted
## (#268) Foundation for player stats changed by many gameplay sources.
## Holds the StatModifier list; the Player owns the base values and reads
## final values through value(stat, base).
##
## STATS (base value in brackets):
##   max_hp             [Player.max_hp export] integer, rounded to nearest
##   damage_amp         [0.0] fraction, +0.25 = hits deal +25%
##   armor              [0.0] fraction of incoming damage removed
##   move_speed         [Player.speed export] pixels/second
##   cooldown_reduction [0.0] fraction, spell cooldown = base * (1 - cdr)
##
## FORMULA (same for every stat, in this order):
##   final = (base + sum(FLAT)) * max(1 + sum(PERCENT), 0), then clamp.
## Stacking: every modifier stacks additively within its op, regardless of
## source. Use add_unique() for "refresh, don't stack" effects.
##
## CAPS (applied last, on the final value):
##   max_hp             >= 1
##   damage_amp         [-0.9, 5.0]   (hits never drop below 10% of base)
##   armor              [-1.0, 0.8]   (at most 80% blocked; negative = shred,
##                                    up to double damage taken)
##   move_speed         [0.1x, 3x] of base (slows never fully root)
##   cooldown_reduction [-1.0, 0.6]   (cooldowns at least 40% of base;
##                                    negative = up to double cooldowns)
##
## EXPIRY / REMOVAL:
##   TIMED modifiers count down in tick(delta) (the Player calls it from
##   _physics_process, so pausing the tree pauses buffs) and are removed when
##   time_left reaches 0. RUN-SCOPED modifiers stay until remove()/
##   remove_source(), or until the run's scene reload frees this object.
##
## Damage amp and armor feed the existing DamageCalc path through
## Player's bridged DamageModifier entries, so the order there (AMP, CRIT,
## REDUCTION) stays the one damage formula.

## Emitted once per affected stat whenever its modifier set changes.
signal changed(stat: StringName)

const MAX_HP := &"max_hp"
const DAMAGE_AMP := &"damage_amp"
const ARMOR := &"armor"
const MOVE_SPEED := &"move_speed"
const COOLDOWN_REDUCTION := &"cooldown_reduction"
const ALL: Array[StringName] = [MAX_HP, DAMAGE_AMP, ARMOR, MOVE_SPEED, COOLDOWN_REDUCTION]

const MAX_HP_MIN := 1.0
const DAMAGE_AMP_MIN := -0.9
const DAMAGE_AMP_MAX := 5.0
const ARMOR_MIN := -1.0
const ARMOR_MAX := 0.8
const MOVE_SPEED_MIN_FACTOR := 0.1
const MOVE_SPEED_MAX_FACTOR := 3.0
const COOLDOWN_REDUCTION_MIN := -1.0
const COOLDOWN_REDUCTION_MAX := 0.6

var _mods: Array[StatModifier] = []

static func is_valid_stat(stat: StringName) -> bool:
	return ALL.has(stat)

## Adds (stacks) a modifier and returns it as the removal handle. Timed
## modifiers start their countdown here. Unknown stats are refused.
func add(m: StatModifier) -> StatModifier:
	if m == null or not is_valid_stat(m.stat):
		push_warning("PlayerStats.add: null modifier or unknown stat")
		return null
	if _mods.has(m):
		return m
	m.time_left = m.duration if m.is_timed() else 0.0
	_mods.append(m)
	changed.emit(m.stat)
	return m

## Refresh-instead-of-stack: drops every modifier with the same source AND
## stat first, then adds `m`. Needs a non-empty source. Emits once.
func add_unique(m: StatModifier) -> StatModifier:
	if m == null or m.source == &"":
		push_warning("PlayerStats.add_unique: needs a modifier with a source")
		return null
	for old in _mods.duplicate():
		if old.source == m.source and old.stat == m.stat:
			_mods.erase(old)
	if _mods.has(m):
		_mods.erase(m)
	return add(m)

func remove(m: StatModifier) -> bool:
	if m == null or not _mods.has(m):
		return false
	_mods.erase(m)
	changed.emit(m.stat)
	return true

## Removes every modifier from `source` (timed and run-scoped). Returns count.
func remove_source(source: StringName) -> int:
	return _take(func(m: StatModifier) -> bool: return m.source == source)

## Removes every TIMED modifier, keeping run-scoped ones. Returns count.
func clear_timed() -> int:
	return _take(func(m: StatModifier) -> bool: return m.is_timed())

func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	var expired := false
	for m in _mods:
		if m.is_timed():
			m.time_left -= delta
			if m.time_left <= 0.0:
				expired = true
	if expired:
		_take(func(m: StatModifier) -> bool: return m.is_timed() and m.time_left <= 0.0)

## Copy of the active modifiers, optionally filtered to one stat.
func modifiers(stat: StringName = &"") -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for m in _mods:
		if stat == &"" or m.stat == stat:
			out.append(m)
	return out

## Final value of `stat` for the given base (see FORMULA and CAPS above).
func value(stat: StringName, base: float) -> float:
	var flat := 0.0
	var pct := 0.0
	for m in _mods:
		if m.stat != stat:
			continue
		if m.op == StatModifier.Op.FLAT:
			flat += m.value
		else:
			pct += m.value
	var v := (base + flat) * maxf(1.0 + pct, 0.0)
	return clamp_value(stat, v, base)

static func clamp_value(stat: StringName, v: float, base: float) -> float:
	match stat:
		MAX_HP:
			return maxf(v, MAX_HP_MIN)
		DAMAGE_AMP:
			return clampf(v, DAMAGE_AMP_MIN, DAMAGE_AMP_MAX)
		ARMOR:
			return clampf(v, ARMOR_MIN, ARMOR_MAX)
		MOVE_SPEED:
			return clampf(v, base * MOVE_SPEED_MIN_FACTOR, base * MOVE_SPEED_MAX_FACTOR)
		COOLDOWN_REDUCTION:
			return clampf(v, COOLDOWN_REDUCTION_MIN, COOLDOWN_REDUCTION_MAX)
	return v

## Removes every modifier matching `pred`, then emits once per touched stat.
func _take(pred: Callable) -> int:
	var touched: Array[StringName] = []
	var kept: Array[StatModifier] = []
	for m in _mods:
		if pred.call(m):
			if not touched.has(m.stat):
				touched.append(m.stat)
		else:
			kept.append(m)
	var removed := _mods.size() - kept.size()
	_mods = kept
	for s in touched:
		changed.emit(s)
	return removed
