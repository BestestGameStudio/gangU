extends Node2D
class_name SpellCaster
## Casting core (#3): owns collected spells, per-spell cooldowns, and spawning
## projectiles toward the cursor. Consumes the shared `cast` input action.
## Supports many spells and later switching (#10) via add_spell/next_spell.
##
## #10 slots extension (Contract B, ADDITIVE): an UNLOCKED inventory plus six
## nullable equip SLOTS with direct per-slot casting (human-settled: 6 slots,
## one key per slot, direct per-slot cast, run-scoped reset, equip panel, one
## spell one slot; slot keys were digits 1-6, re-settled to LMB/RMB/Q/E/R/F by
## #319). The legacy cycle path (spells/add_spell/spell_added/
## next_spell/equipped_spell/cast) keeps Space as its generic cast key; LMB
## left the `cast` action in #319 because it is now slot 1 (a press would
## otherwise fire BOTH the cycle-equipped spell and slot 1). The cycle's
## removal and the generic cast role remain OPEN human choices. The caster never prefills a
## #262 (Daniel, 2026-11-08, "yes first empty slots, and without replacement"):
## unlock_spell auto-binds each newly granted spell to the FIRST EMPTY slot;
## main.gd's starting_spells seeding at boot (#238) rides the same path and
## stays a no-op safeguard. Duplicate unlock grants get no new guard here
## (grant policy OPEN) - equip uniqueness is enforced by assign_slot only.

signal spell_cast(spell: Spell)
signal cooldown_started(spell: Spell, duration: float)
signal spell_equipped(spell: Spell)
## #10: emitted on EVERY add (starting spells and pickups) so HUD rows follow.
signal spell_added(spell: Spell)
## #10 slots: emitted on EVERY unlock-inventory grant (starting, pickup, alias).
signal spell_unlocked(spell: Spell)
## #10 slots: slot gained a spell / slot lost one (clear). Indices are 0-5.
signal slot_assigned(index: int, spell: Spell)
signal slot_cleared(index: int)
## Post-B follow-up: replace_spell swapped a granted spell for a new one.
signal spell_replaced(old_spell: Spell, new_spell: Spell)
## #216: a terrain-block spell placed its tile at `cell`.
signal terrain_block_placed(spell: Spell, cell: Vector2i)

@export var projectile_scene: PackedScene

## #110: muzzle accent - code-drawn, tinted per spell (visual only).
const CombatEffects = preload("res://scripts/combat_effects.gd")
@export var starting_spells: Array[Spell] = []

var spells: Array[Spell] = []
var current_index: int = 0
var _cooldowns: Dictionary = {} ## Spell -> remaining seconds
var _cooldown_totals: Dictionary = {} ## #268: Spell -> last started cooldown length

## #10 slots: unlock inventory (grants land here only, never auto-equip) and
## the six nullable equip slots. Read via get_unlocked()/get_slots() (copies).
var unlocked: Array[Spell] = []
var _slots: Array[Spell] = [null, null, null, null, null, null]

## #370 Stone Hammer run state (Crush crit bonus, Rhythm combo). One per
## caster so it survives upgrades; the run reload resets it with the scene.
var hammer_state := StoneHammerState.new()
## #370 Crush Signature: Spell -> live HammerVortex while its key is held,
## and Spell -> the input action that opened it (only that key releases it).
var _vortexes: Dictionary = {}
var _vortex_actions: Dictionary = {}

const SLOT_COUNT := 6

var equipped_spell: Spell:
	get:
		if spells.is_empty():
			return null
		return spells[current_index]

func _ready() -> void:
	for s in starting_spells:
		add_spell(s)
	_register_slot_actions()

## #319 (Daniel, 2026-11-08): slot cast keys are LMB, RMB, Q, E, R, F for
## slots 1-6 (was digits 1-6). Slots 1-2 bind mouse buttons, 3-6 physical
## letter keys. SLOT_KEY_LABELS is the single source for UI display.
const SLOT_KEY_LABELS: Array[String] = ["LMB", "RMB", "Q", "E", "R", "F"]
const SLOT_KEYCODES: Array[int] = [0, 0, KEY_Q, KEY_E, KEY_R, KEY_F]

## #10 slots: runtime action+binding registration. Idempotent across scene
## reloads (InputMap is global): existing actions are left untouched, so
## nothing stacks. project.godot stays untouched; #319 keys are human-settled.
func _register_slot_actions() -> void:
	for i in SLOT_COUNT:
		var action := StringName("spell_slot_%d" % (i + 1))
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		if i < 2:
			var mev := InputEventMouseButton.new()
			mev.button_index = MOUSE_BUTTON_LEFT if i == 0 else MOUSE_BUTTON_RIGHT
			InputMap.action_add_event(action, mev)
		else:
			var ev := InputEventKey.new()
			ev.physical_keycode = SLOT_KEYCODES[i]
			InputMap.action_add_event(action, ev)

## #319: HUD/equip-panel display name for a slot's cast key (single source).
static func slot_key_label(index: int) -> String:
	return SLOT_KEY_LABELS[index] if index >= 0 and index < SLOT_COUNT else "?"

func add_spell(spell: Spell) -> bool:
	if not unlock_spell(spell):
		return false
	spells.append(spell)
	spell_added.emit(spell)
	if spells.size() == 1:
		current_index = 0
		spell_equipped.emit(spell)
	return true

## #383: true when the player already holds this logical spell this run: the
## exact resource, or any upgraded form descended from it (so a base copy
## cannot be re-acquired after Base -> upgrade). Only the spell's OWN descendants
## count; unrelated spells and other upgrade branches are unaffected.
func has_logical_spell(spell: Spell) -> bool:
	if spell == null:
		return false
	if unlocked.has(spell) or spells.has(spell):
		return true
	var progress := get_tree().get_first_node_in_group("spell_progress") as SpellProgress if is_inside_tree() else null
	if progress == null:
		return false
	var parent_of: Dictionary = {}
	for u: SpellUpgrade in progress.upgrades:
		if u != null and u.result_spell != null and u.source_spell != null:
			parent_of[u.result_spell] = u.source_spell
	for held in unlocked:
		var cur: Spell = held
		for _i in 16: # bounded walk; guards bad cyclic data
			if not parent_of.has(cur):
				break
			cur = parent_of[cur]
			if cur == spell:
				return true
	return false

## #10 slots: grant to the unlock inventory. Duplicate-grant policy is an OPEN
## human choice - #383 now refuses a second copy of a held logical spell.
## #262: every newly granted spell also auto-binds to the FIRST EMPTY slot in
## 1-6 order. Existing bindings are never replaced: when all six slots are
## occupied the grant stays unlock-only for manual equip in the Tab panel.
## One funnel covers every grant path - walk-over pickups (add_spell), enemy
## reward-drop spells, and shop purchases.
## #383: refuses (returns false) when the logical spell is already held, with
## no inventory/slot change and no signal.
func unlock_spell(spell: Spell) -> bool:
	if spell == null or has_logical_spell(spell):
		return false
	unlocked.append(spell)
	spell_unlocked.emit(spell)
	bind_first_free(spell)
	return true

## #262: bind `spell` to the first empty slot in 1-6 order. Returns the slot
## index the spell ends in (its existing binding when already slotted), or
## -1 when every slot is occupied: the grant then stays unlock-only and no
## existing player assignment is touched.
func bind_first_free(spell: Spell) -> int:
	if spell == null:
		return -1
	var existing := _slots.find(spell)
	if existing != -1:
		return existing
	for i in SLOT_COUNT:
		if _slots[i] == null:
			return i if assign_slot(i, spell) else -1
	return -1

## #10 slots: one spell one slot (human-settled), enforced by REFUSAL (joint
## lead/writer pin): no silent moves, copies, or evictions. Returns true when
## the slot ends with this spell assigned (including the no-op re-assign).
func assign_slot(index: int, spell: Spell) -> bool:
	if index < 0 or index >= SLOT_COUNT:
		push_warning("assign_slot: index out of range")
		return false
	if spell == null:
		push_warning("assign_slot: null spell")
		return false
	if not unlocked.has(spell):
		push_warning("assign_slot: spell not in unlocked inventory")
		return false
	if _slots[index] == spell:
		return true # already assigned here: no-op, no signal
	if _slots.find(spell) != -1:
		push_warning("assign_slot: spell already occupies another slot (clear it first)")
		return false
	if _slots[index] != null:
		push_warning("assign_slot: target slot occupied by a different spell (clear it first)")
		return false
	_slots[index] = spell
	slot_assigned.emit(index, spell)
	return true

## Returns true (+ slot_cleared) when the slot held a spell, false on empty.
func clear_slot(index: int) -> bool:
	if index < 0 or index >= SLOT_COUNT:
		push_warning("clear_slot: index out of range")
		return false
	if _slots[index] == null:
		return false
	_slots[index] = null
	slot_cleared.emit(index)
	return true

## Post-B follow-up (bounded caster follow-up, additive): atomically swap a
## granted spell for a new, not-yet-granted one. unlocked[] is replaced at
## old_spell's OWN index; the legacy spells[] list is replaced at its OWN old
## index ONLY IF old is present there (an unlock-only grant stays out of the
## legacy list; current_index is never touched). If old was slotted, that slot
## index is preserved and re-emits slot_assigned (no slot_cleared). The new
## spell inherits old's remaining cooldown (max(remaining, 0), unconditional
## overwrite) and old's cooldown key is deleted. Refusals below are argument
## validation for THIS API only - they do not change the OPEN duplicate-grant
## policy (unlock_spell/add_spell stay unguarded).
func replace_spell(old_spell: Spell, new_spell: Spell) -> bool:
	if old_spell == null or new_spell == null:
		push_warning("replace_spell: null spell")
		return false
	var uidx := unlocked.find(old_spell)
	if uidx == -1:
		push_warning("replace_spell: old spell not in unlocked inventory")
		return false
	if unlocked.has(new_spell):
		push_warning("replace_spell: new spell already unlocked")
		return false
	# Atomic inventory + slot swap (no partial states: all refusals above).
	unlocked[uidx] = new_spell
	var lidx := spells.find(old_spell)
	if lidx != -1:
		spells[lidx] = new_spell # legacy keeps its own index; current_index unchanged
	var sidx := _slots.find(old_spell)
	if sidx != -1:
		_slots[sidx] = new_spell # preserve slot index; no slot_cleared
	# Cooldown transfer: new inherits old's remaining time, old entry removed.
	_cooldowns[new_spell] = maxf(_cooldowns.get(old_spell, 0.0), 0.0)
	_cooldowns.erase(old_spell)
	if _cooldown_totals.has(old_spell):
		_cooldown_totals[new_spell] = _cooldown_totals[old_spell]
		_cooldown_totals.erase(old_spell)
	if sidx != -1:
		slot_assigned.emit(sidx, new_spell)
	spell_replaced.emit(old_spell, new_spell)
	return true

func can_cast_slot(index: int) -> bool:
	if index < 0 or index >= SLOT_COUNT:
		return false
	var s: Spell = _slots[index]
	return s != null and cooldown_remaining(s) <= 0.0

## Direct per-slot cast (human-settled: keys 1-6 cast that slot's spell
## directly, no selection step). No-op + warning on empty/blocked slot.
func cast_slot(index: int) -> void:
	if not can_cast_slot(index):
		push_warning("cast_slot: slot empty or on cooldown")
		return
	_cast_spell(_slots[index])

## Read-only accessors for the HUD slot bar and the equip panel. Both return
## COPIES - callers can never mutate caster state through them.
func get_slots() -> Array[Spell]:
	return _slots.duplicate()

func get_unlocked() -> Array[Spell]:
	return unlocked.duplicate()

func next_spell() -> void:
	if spells.size() > 1:
		current_index = (current_index + 1) % spells.size()
		spell_equipped.emit(equipped_spell)

func cooldown_remaining(spell: Spell) -> float:
	return _cooldowns.get(spell, 0.0)

## #268: full length of the spell's last started cooldown (after cooldown
## reduction), for HUD fill ratios. spell.cooldown before the first cast.
func cooldown_duration(spell: Spell) -> float:
	if spell == null:
		return 0.0
	return _cooldown_totals.get(spell, spell.cooldown)

func _effective_cooldown(base: float) -> float:
	var owner_node := get_parent()
	if owner_node is Player:
		return (owner_node as Player).effective_cooldown(base)
	return base

func can_cast() -> bool:
	return equipped_spell != null and cooldown_remaining(equipped_spell) <= 0.0

func _process(delta: float) -> void:
	for s: Spell in _cooldowns.keys():
		_cooldowns[s] = maxf(_cooldowns[s] - delta, 0.0)
	_tick_hammer(delta)
	if not _vortexes.is_empty():
		_prune_charges()
	if _input_casts_suppressed():
		return
	# #370: a held Vortex Hammer key charges instead of casting; the release
	# swings. Handled before the pressed checks so the release is seen.
	var cast_held := Input.is_action_pressed(&"cast")
	if _charge_input(equipped_spell, &"cast", cast_held):
		pass
	# #246: a HELD cast button auto-refires the moment the cooldown completes
	# (pressed, not just_pressed). can_cast() gates the cooldown frames, so a
	# held Space/LMB fires once per press, then refires on completion with no
	# re-click; releasing the button stops it.
	elif cast_held and not _redirect_gate(equipped_spell, Input.is_action_just_pressed(&"cast")) and can_cast():
		cast()
	# #10: switching is caster-owned (player.gd untouched). The action has no
	# key bound until the human key choice lands; harness drives next_spell().
	if InputMap.has_action(&"switch_spell") and Input.is_action_just_pressed(&"switch_spell"):
		next_spell()
	# #10 slots: direct per-slot cast on keys 1-6 (registered in _ready).
	# #246: same held-button auto-refire here. can_cast_slot gates empty and
	# cooling slots up front, so a held key refires on cooldown completion
	# and never spams cast_slot's refusal warnings while it runs.
	for i in SLOT_COUNT:
		var action := StringName("spell_slot_%d" % (i + 1))
		if _charge_input(_slots[i], action, Input.is_action_pressed(action)):
			continue
		if not Input.is_action_pressed(action):
			continue
		# #331: a steer Water Ball with shots in flight re-aims them on a
		# fresh press instead of casting (held keys never recast it).
		if _redirect_gate(_slots[i], Input.is_action_just_pressed(action)):
			continue
		if can_cast_slot(i):
			cast_slot(i)

func cast() -> void:
	_cast_spell(equipped_spell)

## #331: world point casts aim at. aim_override (a Vector2) replaces the
## mouse for scripted drivers and harnesses; null = the real cursor.
var aim_override: Variant = null

func aim_point() -> Vector2:
	if aim_override is Vector2:
		return aim_override
	return get_global_mouse_position()

## #331 Water Ball steer branch: this caster's shots of `spell` still flying.
func live_shots(spell: Spell) -> Array[Projectile]:
	var out: Array[Projectile] = []
	if spell == null:
		return out
	for n in get_tree().get_nodes_in_group(&"projectiles"):
		var p := n as Projectile
		if p != null and p.spell == spell and p.source == get_parent() and not p.is_queued_for_deletion():
			out.append(p)
	return out

## #331: re-aim every redirectable live shot of `spell` at the aim point.
## Returns how many turned. Not a cast: no cooldown, no signals.
## (Daniel 2026-11-09) a shot at its spell.redirect_limit no longer turns.
func redirect_shots(spell: Spell) -> int:
	var target := aim_point()
	var turned := 0
	for p in live_shots(spell):
		if p.redirect(target):
			turned += 1
	return turned

## #331: true when the press belongs to a recast_redirect spell with
## redirectable shots in flight - a fresh press redirects them, a held one
## does nothing; either way the input must not cast. (Daniel 2026-11-09:
## Guided tier 1 shots turn only once) shots that used up their redirects
## don't hold the gate, so the next press casts a fresh shot normally.
func _redirect_gate(spell: Spell, just_pressed: bool) -> bool:
	if spell == null or not spell.recast_redirect:
		return false
	var redirectable := false
	for p in live_shots(spell):
		if p.can_redirect():
			redirectable = true
			break
	if not redirectable:
		return false
	if just_pressed:
		redirect_shots(spell)
	return true

## #331 Water Ball bubble branch: the owner's live shield, if any.
func active_shield() -> WaterShield:
	var owner_node := get_parent()
	if owner_node == null:
		return null
	for c in owner_node.get_children():
		var shield := c as WaterShield
		if shield != null and shield.is_active() and not shield.is_queued_for_deletion():
			return shield
	return null

## Spawns (or refreshes) the shield, or - Big Ball with a shield up - fires
## its Water Ball and shrinks the ball. Returns the cooldown this cast costs.
func _cast_shield(spell: Spell, dir: Vector2) -> float:
	var current := active_shield()
	if current != null and spell.shield_shot != null:
		_spawn_fanout(spell.shield_shot, dir)
		current.shrink()
		return spell.shield_shot.cooldown
	if current != null:
		current.remove_from_group(&"water_shields")
		current.queue_free() # refresh: a recast replaces it, no end burst
	var owner_node := get_parent() as Node2D
	if owner_node == null:
		return spell.cooldown
	var shield := WaterShield.spawn(owner_node, spell)
	if spell.shield_shot != null:
		# Big Ball: shoot right away; the real cooldown starts when it ends.
		shield.ended.connect(_on_big_ball_ended.bind(spell), CONNECT_ONE_SHOT)
		return spell.shield_shot.cooldown
	return spell.cooldown

func _on_big_ball_ended(_popped: bool, spell: Spell) -> void:
	_start_cooldown(spell, spell.cooldown)

func _start_cooldown(spell: Spell, base: float) -> void:
	var duration := _effective_cooldown(base)
	_cooldowns[spell] = duration
	_cooldown_totals[spell] = duration
	cooldown_started.emit(spell, duration)

## #331 splash branch: the landing point under the aim, clamped to range.
func _lob_target(spell: Spell) -> Vector2:
	var off := aim_point() - global_position
	if off.length() > spell.range:
		off = off.normalized() * spell.range
	return global_position + off

## #331: one lob per projectile_count; extra lobs ring the aim point within
## splash_scatter px (Mastery), the first always lands on it.
func _cast_splash(spell: Spell) -> void:
	var center := _lob_target(spell)
	var n := maxi(spell.projectile_count, 1)
	var phase := randf() * TAU
	for i in n:
		var target := center
		if i > 0 and spell.splash_scatter > 0.0:
			var a := phase + TAU * float(i - 1) / float(n - 1)
			target += Vector2(cos(a), sin(a)) * spell.splash_scatter * randf_range(0.7, 1.0)
		WaterSplash.spawn(get_tree().current_scene, spell, get_parent(), global_position, target, 70.0 + 15.0 * i)

## ---- #370 Stone Hammer ------------------------------------------------------

## Starts one swing. Returns the base cooldown this cast costs.
func _cast_hammer(spell: Spell) -> float:
	var base := hammer_state.cooldown_for(spell)
	hammer_state.on_cast()
	StoneHammer.spawn(get_tree().current_scene, spell, get_parent() as Node2D, self, hammer_target(spell))
	return base

## Where the hammer lands: the aim point, clamped to the spell's range.
func hammer_target(spell: Spell) -> Vector2:
	return _lob_target(spell)

## Rhythm combo clock: the combo resets once the held hammer is off cooldown
## and unused for its idle limit.
func _tick_hammer(delta: float) -> void:
	if hammer_state.combo_hits <= 0:
		return
	var hammer: Spell = null
	for s in _slots:
		if s != null and s.hammer_combo_cdr > 0.0:
			hammer = s
			break
	if hammer == null:
		for s in unlocked:
			if s != null and s.hammer_combo_cdr > 0.0:
				hammer = s
				break
	var limit := hammer.hammer_combo_idle_reset if hammer != null else 30.0
	var cooling := hammer != null and cooldown_remaining(hammer) > 0.0
	hammer_state.tick(delta, cooling, limit)

## Crush Signature: open the vortex for `spell` (key pressed). Refused while
## on cooldown, already charging, or for spells without a vortex.
func begin_charge(spell: Spell, action: StringName = &"") -> bool:
	if spell == null or spell.hammer_vortex_radius <= 0.0 or is_charging(spell):
		return false
	if cooldown_remaining(spell) > 0.0:
		return false
	var owner_node := get_parent()
	if not _owner_alive():
		return false
	var radius := spell.hammer_vortex_radius * hammer_state.size_scale(spell, owner_node)
	_vortexes[spell] = HammerVortex.spawn(get_tree().current_scene, spell, hammer_target.bind(spell), radius)
	_vortex_actions[spell] = action
	return true

func _owner_alive() -> bool:
	var owner_node := get_parent()
	if owner_node == null:
		return true
	var hp: Variant = owner_node.get(&"hp")
	return hp == null or int(hp) > 0

## Drops vortexes whose spell left every cast key (unequipped, upgraded) or
## whose caster died, so none is left pulling with no key to release it.
func _prune_charges() -> void:
	for s: Spell in _vortexes.keys():
		if not is_charging(s) or not _owner_alive() or not (_slots.has(s) or equipped_spell == s):
			cancel_charge(s)

func is_charging(spell: Spell) -> bool:
	var v: Variant = _vortexes.get(spell)
	return v != null and is_instance_valid(v)

func active_vortex(spell: Spell) -> HammerVortex:
	return _vortexes.get(spell) if is_charging(spell) else null

## Crush Signature: key released - close the vortex and swing. Returns
## false when nothing was charging.
func release_charge(spell: Spell) -> bool:
	if not is_charging(spell):
		_vortexes.erase(spell)
		_vortex_actions.erase(spell)
		return false
	cancel_charge(spell)
	_cast_spell(spell)
	return true

## Closes the vortex without swinging.
func cancel_charge(spell: Spell) -> void:
	var v: Variant = _vortexes.get(spell)
	if v != null and is_instance_valid(v):
		(v as Node).queue_free()
	_vortexes.erase(spell)
	_vortex_actions.erase(spell)

## Input routing for vortex spells. Returns true when the input belongs to a
## vortex spell (so the normal cast paths skip it): press opens the vortex,
## release swings. Another key holding the same spell's vortex is ignored.
func _charge_input(spell: Spell, action: StringName, pressed: bool) -> bool:
	if spell == null or spell.hammer_vortex_radius <= 0.0:
		return false
	if is_charging(spell):
		if _vortex_actions.get(spell, &"") != action:
			return true
		if not pressed:
			release_charge(spell)
		return true
	if pressed:
		begin_charge(spell, action)
	return true

## #10 slots input routing (joint pin with the equip/upgrade panel F): while a
## node in the "modal_ui" group exists (F joins it ONLY while visible), the
## panel owns mouse/keys, so INPUT-DRIVEN casts (legacy Space/LMB + slot keys)
## are skipped. Cooldowns still tick above - nothing pauses. Direct API calls
## (cast()/cast_slot(), harness, panel orchestration) are never gated. With no
## modal_ui node present (production today) behavior is unchanged.
func _input_casts_suppressed() -> bool:
	return get_tree().get_first_node_in_group("modal_ui") != null

## Shared spawn path for the generic cast and direct slot casts: projectiles
## toward the cursor, cooldown keyed by the Spell resource.
## Fan-out seam (#33/#36, post-#65 window): one spawn per direction from the
## pure SpellFanout helper. Defaults (projectile_count 1 / spread 0) return
## [dir], so every existing spell behaves exactly as before. ONE cooldown
## entry and ONE cooldown_started/spell_cast signal per CAST, not per
## projectile; per-projectile setup/range/despawn is Projectile's own.
func _cast_spell(spell: Spell) -> void:
	if spell == null:
		return
	# #305: the Signature bubble anchors at the CAST POINT, captured before
	# any launch can move the player (Daniel: the bubble stays "where you
	# cast"). For a launch spell this is the pre-launch position.
	var cast_pos := global_position
	var dir := global_position.direction_to(aim_point())
	if dir.length_squared() == 0.0:
		dir = Vector2.RIGHT.rotated((get_parent() as Node2D).rotation)
	# #216: terrain-block spells place their tile BEFORE anything else; a
	# refused placement returns here, so it costs no cooldown and emits nothing.
	if spell.terrain_block != &"":
		if _place_terrain_block(spell) == null:
			return
	# #305: launch spells move the player BEFORE attacking (Mastery spec).
	# A refused launch (dead or already launching) returns here like a
	# refused terrain block (#216): not a cast, so no cooldown, no signals,
	# no attack. An accepted launch commits the cast - cooldown and both
	# signals fire below - and the attack waits for launch_ended so punches
	# spawn at the settled position.
	if spell.launch_speed > 0.0:
		var player := get_parent() as Player
		if player == null or not player.launch(dir, spell.launch_speed, spell.launch_duration):
			return
		_arm_launch(spell, player)
	# #212: summon-only spells carry projectile_count 0 - skip the projectile
	# fan-out entirely (window ACK: guard this loop ONLY). Cooldown and both
	# signals below stay unconditional; positive counts are byte-identical.
	# #305: a launch spell defers this whole block to launch_ended.
	# #305: freeze bubble. The ONE cooldown/signal pair below is untouched.
	# A refused launch/terrain placement returned above, so a bubble here
	# always belongs to a committed cast. #323: the Spirit Punch Signature
	# ("The World") carries projectile_count 0 and no launch, so its cast is
	# the bubble alone.
	if spell.freeze_radius > 0.0:
		FreezeBubble.spawn(get_tree().current_scene, cast_pos, spell.freeze_radius, spell.freeze_duration)
	# #331 Water Ball tree: bubble, heavy rain and splash casts replace the
	# flat fan-out; each still costs ONE cooldown/signal pair below (the Big
	# Ball's shot cast costs its Water Ball's cooldown instead).
	var cooldown_base := spell.cooldown
	# #370 Stone Hammer: an overhead swing at the aim point (clamped to
	# range). Its cooldown is the Rhythm combo's reduced one when it applies.
	match spell.cast_mode():
		Spell.CastMode.HAMMER:
			cooldown_base = _cast_hammer(spell)
		Spell.CastMode.SHIELD:
			cooldown_base = _cast_shield(spell, dir)
		Spell.CastMode.RAIN:
			WaterRain.spawn(get_tree().current_scene, spell, get_parent(), _lob_target(spell))
		Spell.CastMode.SPLASH:
			_cast_splash(spell)
		Spell.CastMode.PROJECTILE:
			if spell.launch_speed <= 0.0:
				_spawn_fanout(spell, dir)
				# #305: a burst re-fires the fan-out burst_count times, one immediately
				# (above) and the rest at burst_interval spacing, re-aimed at the cursor
				# like a repeated manual cast (#246). Player-owned caster, so the burst
				# keeps pace while a freeze bubble holds everything else; one cooldown
				# and one signal pair per cast stay untouched below.
				if spell.burst_count > 1:
					_run_burst(spell, spell.burst_count - 1)
	# #268: the owning Player's cooldown reduction shortens the cooldown this
	# cast starts. With no Player parent (or zero CDR) it is spell.cooldown.
	_start_cooldown(spell, cooldown_base)
	spell_cast.emit(spell)
	# #110: brief muzzle accent at the cast point, facing the aim direction.
	# Visual only; parented to the scene root, lifetime owned by the effect.
	CombatEffects.muzzle(get_tree().current_scene, global_position, dir.angle(), spell.projectile_color)

## One fan-out of projectiles toward dir: one spawn per direction from the
## pure SpellFanout helper (defaults return [dir]).
func _spawn_fanout(spell: Spell, dir: Vector2) -> void:
	for d in SpellFanout.directions(dir, spell.projectile_count, spell.spread_degrees):
		var p: Projectile = projectile_scene.instantiate()
		p.setup(spell, d, get_parent())
		p.cursor_provider = aim_point # #331: steer Water Balls chase the aim point
		get_tree().current_scene.add_child(p)
		p.global_position = global_position


## #305: remaining burst repetitions, each re-aimed at the live cursor like
## a repeated manual cast. Runs on this player-owned caster's own clock, so
## it is outside the freeze contract's entity set (only the player moves).
func _run_burst(spell: Spell, remaining: int) -> void:
	for i in remaining:
		await get_tree().create_timer(spell.burst_interval).timeout
		if not is_instance_valid(self):
			return
		var dir := global_position.direction_to(aim_point())
		if dir.length_squared() == 0.0:
			dir = Vector2.RIGHT.rotated((get_parent() as Node2D).rotation)
		_spawn_fanout(spell, dir)


## #305: an accepted spell launch. The cast is already committed (cooldown
## and signals fired); the attack itself waits for launch_ended so
## projectiles spawn at the settled position. The two one-shot connections
## are paired: whichever fires first disconnects the other, so a
## death-cancelled launch can never fire a stale volley on a later launch.
var _pending_launch_spell: Spell = null
var _pending_launch_player: Player = null
var _pending_launch_ended_cb: Callable
var _pending_launch_cancelled_cb: Callable

func _arm_launch(spell: Spell, player: Player) -> void:
	_pending_launch_spell = spell
	_pending_launch_player = player
	_pending_launch_ended_cb = _on_launch_ended.bind(spell, player)
	_pending_launch_cancelled_cb = _on_launch_cancelled.bind(player)
	player.launch_ended.connect(_pending_launch_ended_cb, CONNECT_ONE_SHOT)
	player.launch_cancelled.connect(_pending_launch_cancelled_cb, CONNECT_ONE_SHOT)

func _on_launch_ended(spell: Spell, player: Player) -> void:
	if player.is_connected(&"launch_cancelled", _pending_launch_cancelled_cb):
		player.launch_cancelled.disconnect(_pending_launch_cancelled_cb)
	_pending_launch_spell = null
	_pending_launch_player = null
	# Re-aimed at the live cursor like a repeated manual cast (#246), but
	# from the settled post-launch position.
	var dir := global_position.direction_to(aim_point())
	if dir.length_squared() == 0.0:
		dir = Vector2.RIGHT.rotated((get_parent() as Node2D).rotation)
	if spell.projectile_count > 0:
		_spawn_fanout(spell, dir)
		if spell.burst_count > 1:
			_run_burst(spell, spell.burst_count - 1)

func _on_launch_cancelled(player: Player) -> void:
	if player.is_connected(&"launch_ended", _pending_launch_ended_cb):
		player.launch_ended.disconnect(_pending_launch_ended_cb)
	_pending_launch_spell = null
	_pending_launch_player = null
	# No attack and no refund: the cast committed when the launch was
	# accepted, matching the refused-cast semantics above.


## #216: the caster's owner carries the area's TerrainMap (main.gd _swap
## sets Player.terrain). Areas without one (hub, DungeonA-C) refuse the cast.
func _place_terrain_block(spell: Spell) -> Variant:
	var owner_node := get_parent() as Node2D
	var map: TerrainMap = null
	if owner_node != null:
		map = owner_node.get(&"terrain") as TerrainMap
	if map == null:
		return null
	var blockers := TerrainBlock.blockers_in(get_tree(), owner_node)
	var cell: Variant = TerrainBlock.place(map, global_position, aim_point(), spell.range, spell.terrain_block, blockers)
	if cell != null:
		terrain_block_placed.emit(spell, cell)
	return cell
