class_name EnemyBehaviorCover
extends RefCounted
## #406: cover-seeking chase for the common moustache man (Mustache
## Warrior, scenes/enemy.tscn). Daniel, 2026-11-09 (WhatsApp):
##   "moustache men now seek cover. If pathfinding towards a player,
##    they'll move to the nearest cover towards the player (trees,
##    breakable terrain). When moving between cover, they run fast. If the
##    player mouse is pointing their direction they stay behind cover. If
##    they players mouse is away from their direction for a period of time
##    (3s) moustache men will charge the player"
## Target clarification (Daniel, same thread): "just regular mobs" - the
## Mustache Warlord boss keeps its #177 behavior. And: "it isn't hardcoded
## to trees. It should be any cover."
##
## Architecture: this is NOT the enemy's _behavior slot value.
## EnemyBehaviorChaseContact owns one instance of this helper and
## delegates to it only when the enemy opts in (Enemy.cover_seek, set by
## scenes/enemy.tscn). The slot keeps holding an
## EnemyBehaviorChaseContact, so Enemy._resolve_target's
## `_behavior is EnemyBehaviorChaseContact` test - summon taunts (#209)
## and defense-core targeting (#337) - keeps working untouched, and
## guard/patrol/migrate (#346/#373), which delegate their ENGAGED chase to
## the same base, seek cover too while chasing a player. Fallbacks call
## the owner's unchanged _chase_step. (Composition + seam preservation
## follow technical recommendations from Colin's Instinct on e94c89e -
## recommendations only: no eligibility rule or value below is
## peer-approved.)
##
## COVER ELIGIBILITY (author-proposed definition, human-open): a cover
## candidate is any solid that can geometrically shield the enemy from
## the player - never selected by tree type (Daniel: "any cover") -
## discovered through two generic providers:
##   1. Terrain adapter: any BLOCKING, non-swimmable cell on the wired
##      TerrainMap, via the TerrainMap lookup seam only
##      (tile_type_at_cell/type_properties/cell_to_world - no raw registry
##      or TileMap internals). Overworld trees are OBSTACLE; destroyable
##      TREE/BLOCK cells are the "breakable terrain" Daniel named;
##      MOUNTAIN or any future blocking type qualifies the same way.
##      Water is not cover; pits (FALLING) are not cover.
##   2. Solid adapter: any Node2D in the "cover" group (DestroyableContainer
##      opts in on _ready). Any future solid object can opt in the same way.
## Blockage alone is not enough: a candidate must provide SHELTER -
## a hold point on ground this mover can enter, placed on the side away
## from the player so the candidate itself sits on the hold->player
## segment (geometric shielding), verified by the occlusion check.
## #407 (trees block projectiles) is a separate concern and is NOT folded
## in: this behavior is positioning only.
##
## Loop:
##   SEEK  - no cover held yet: walk (normal speed) to the nearest cover
##           toward the player and stop just behind it.
##   DASH  - moving between cover spots (advancing toward the player, or
##           repositioning when the player strafes around the held cover):
##           runs FAST ("when moving between cover, they run fast").
##   HOLD  - at the cover: stand still while the player's mouse points
##           their way (aim direction within AIM_CONE of player->enemy).
##           Shelter is re-checked even while aimed at: if the player
##           strafes so the cover no longer shields them, they DASH to valid
##           shelter, or ENGAGE when none exists.
##           #414 (Daniel, 2026-11-09: "moustache men periodically find
##           nearby cover if holding cover for over 5s"): holding the same
##           cover for HOLD_RELOCATE_TIME triggers a relocate DASH to a
##           DIFFERENT nearby cover, aimed at or not (the newer instruction
##           modifies the original "stay behind cover while aimed at").
##           With no other cover around it keeps holding and retries one
##           period later.
##           #443: while holding, they lob a low-damage rock at the player
##           every ROCK_INTERVAL (see the ROCK constants / _tick_rock).
##   CHARGE- the per-enemy away-timer runs whenever the mouse is NOT
##           pointing their way (in SEEK/DASH/HOLD) and resets the moment
##           it points back; at AWAY_CHARGE_TIME the moustache man charges:
##           fast direct chase, normal contact attack on arrival, then
##           ENGAGED. #414 (Daniel: "Once they begin charging dont stop"):
##           a charge COMMITS - the away-timer only ticks in SEEK/DASH/HOLD,
##           so re-aiming never cancels a charge already running; only
##           contact ends it. (Unchanged behavior, now pinned by test414.)
##   ENGAGED - plain chase/contact (the owner's _chase_step, unchanged).
##           If the player disengages beyond RE_ENGAGE_DIST and cover
##           exists, back to SEEK. #469: an ENGAGED that is only the
##           no-cover fallback re-scans on the repick cadence at ANY range
##           (post-charge and wedged-hold ENGAGED keep the distance rule),
##           and within CLOSE_COVER_DIST a starved toward-player tier falls
##           back to any sheltered cover in range (see _pick_cover).
## A destroyed cover is dropped two ways: instantly via the TerrainMap
## cell_destroyed/cell_interacted signals (the destroy_cell/interact_cell
## paths emit them), and - because raw set_cell/clear_cell emit nothing -
## via the repick-cadence validity poll that also catches freed solids.
## A mover wedged on an unreachable hold point (STALL_TIME at zero
## velocity) drops the cover and engages.
##
## Movement routes through a per-mover #391 TerrainPath helper and the
## parent's _slide (no raw-velocity bypass of terrain/water/crowd rules),
## for travel AND the charge. The away-timer and contact clock accumulate
## from delta inside physics_step only, so freeze (#305) and knockback
## (#331) pause them. The contact clock is the owner's _contact_timer:
## one cooldown across charge and engaged hits.
##
## Fallbacks (owner's exact _chase_step): no cover in range, FlowNav enemy
## (#367 maze keeps its steering), or a non-Player target (summon taunt,
## defense core - a summon/core has no mouse).
## All timings/angles/speeds are PLACEHOLDER tuning (human-open).
##
## One instance per owning behavior (which is per-enemy, #99); state is
## never shared across enemies.

const COVER_SEARCH_RADIUS: float = 384.0 ## how far a moustache man looks for cover (PLACEHOLDER)
const COVER_CONE_COS: float = 0.5 ## cover must sit within 60deg of the player direction (PLACEHOLDER)
const AIM_CONE_COS: float = 0.8660254 ## mouse "pointing their direction" = player aim within 30deg of player->enemy (PLACEHOLDER)
const AWAY_CHARGE_TIME: float = 3.0 ## Daniel: charge after the mouse is away this long (per enemy, resets on re-aim)
const HOLD_RELOCATE_TIME: float = 5.0 ## Daniel (2026-11-09): holding one cover this long -> relocate to a different nearby cover
const FAST_MULT: float = 2.2 ## "run fast": dash-between-cover and charge speed multiplier (PLACEHOLDER)
const STANDOFF: float = 20.0 ## hold distance behind the cover edge (PLACEHOLDER)
const SOLID_RADIUS: float = 24.0 ## assumed blocking radius of a cover-group solid (PLACEHOLDER)
const ADVANCE_MARGIN: float = 24.0 ## a new cover must get them at least this much closer to the player to be an advance (PLACEHOLDER)
const FLANK_COS: float = 0.3 ## held cover no longer toward the player past this (PLACEHOLDER)
const RE_ENGAGE_DIST: float = 280.0 ## post-charge ENGAGED: disengaged past this, seek cover again (PLACEHOLDER)
## #469 (Daniel, 2026-11-09: "mustache men sometimes stop seeking cover" -
## "Walking at you" - "When im close"): within this range of the player,
## when no cover lies toward the player (the strict tier - nearer than the
## player and inside COVER_CONE_COS - is geometrically starved up close),
## any cover in range whose hold point is sheltered from the player
## qualifies: beside, behind the mob, or just past the player. (PLACEHOLDER)
const CLOSE_COVER_DIST: float = 256.0
const REPICK_INTERVAL: float = 0.25 ## cover rescan/invalidation cadence (mirrors TerrainPath.REPLAN_INTERVAL)
const WAYPOINT_EPS: float = 10.0
const SHELTER_HALF_WIDTH: float = 8.0 ## sightline must stay blocked this far either side (body width, not a corner graze) (PLACEHOLDER)
const STALL_TIME: float = 1.0 ## wedged this long on an unreachable hold point: drop the cover and engage (PLACEHOLDER)
## #443 (Daniel, 2026-11-09: "When hiding behind cover mustache men throw
## rocks. Rocks go over terrain like barricades and trees"; answers: low
## damage, only while hiding behind cover, fly toward the player, over low
## cover only - maze walls and stone blocks still block them).
## The rock is a LOBBED Projectile (resources/spells/mustache_rock.tres) aimed
## at the player's position at release; it lands just past that point, so
## moving dodges it. Thrown only in HOLD, only within ROCK_RANGE, and only
## when no high cover (TerrainMap.lob_blocked) sits on the line - a man
## behind a wall does not waste rocks into it.
const ROCK_SPELL: Spell = preload("res://resources/spells/mustache_rock.tres")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")
const ROCK_INTERVAL: float = 1.8 ## seconds between throws while holding (PLACEHOLDER)
const ROCK_FIRST_DELAY: float = 0.6 ## settle time after reaching cover before the first throw (PLACEHOLDER)
const ROCK_RANGE: float = 400.0 ## max throw distance to the player (PLACEHOLDER)
const ROCK_OVERSHOOT: float = 36.0 ## the rock flies this far past the aim point before landing (PLACEHOLDER)

enum State { SEEK, DASH, HOLD, CHARGE, ENGAGED }

var _state: int = State.SEEK
## DEBUG/RECORDING aid: when true (showcase drivers set it), cover scans log
## candidate rejection tallies. Logging only - no decision is altered.
var debug_trace := false
var _dbg_last := ""
var _has_cover: bool = false
var _cover_cell: Vector2i = Vector2i.ZERO ## terrain cover, when _cover_node is null
var _cover_node: Node2D = null ## solid-body cover, when set
var _cover_pos: Vector2 = Vector2.ZERO
var _hold_pos: Vector2 = Vector2.ZERO
var _away_timer: float = 0.0
var _repick_timer: float = 0.0
var _stall_timer: float = 0.0
## #414: time spent HOLDing the current cover (reset on each new hold).
var _hold_elapsed: float = 0.0
## #469: true when ENGAGED came from a charge hit or a wedged hold point
## (sticky: re-seek only past RE_ENGAGE_DIST, the pre-#469 rule). False
## for the no-cover fallback, which re-scans on the repick cadence at any
## range so a close player no longer locks the mob into the plain chase.
var _engaged_sticky: bool = false
## #443: countdown to the next rock while holding (reset on each new hold).
var _rock_timer: float = ROCK_FIRST_DELAY
## #443: rocks thrown by this enemy (test/debug counter only).
var rocks_thrown: int = 0
## The TerrainMap whose cell_destroyed/cell_interacted signals we listen
## to for instant cover invalidation (raw set/clear_cell emit nothing, so
## the repick poll below remains the catch-all).
var _signal_map: TerrainMap = null
## Separate routing state from the owner's chase path - a half-walked
## chase path never mixes with a cover route (the #346 _walk_path idiom).
var _terrain_path := TerrainPath.new()

## Entry point, called from the owning EnemyBehaviorChaseContact only when
## enemy.cover_seek is set. `player` is duck-typed (Player, Summon or
## DefenseCore); the cover loop runs only for a live Player target.
func physics_step(owner: EnemyBehaviorChaseContact, enemy: Enemy, player, delta: float) -> void:
	if enemy.nav != null or not (player is Player):
		owner._chase_step(enemy, player, delta)
		return
	if player == null or not is_instance_valid(player) or player.hp <= 0:
		owner._chase_step(enemy, player, delta)
		return
	_repick_timer = maxf(0.0, _repick_timer - delta)
	_hook_terrain_signals(enemy)
	var pointing := _is_pointed_at(enemy, player)
	if _state == State.SEEK or _state == State.DASH or _state == State.HOLD:
		_away_timer = 0.0 if pointing else _away_timer + delta
		if _away_timer >= AWAY_CHARGE_TIME:
			_state = State.CHARGE
	match _state:
		State.SEEK:
			_seek(owner, enemy, player, delta, false)
		State.DASH:
			_seek(owner, enemy, player, delta, true)
		State.HOLD:
			_hold(enemy, player, pointing, delta)
		State.CHARGE:
			_charge(owner, enemy, player, delta)
		State.ENGAGED:
			owner._chase_step(enemy, player, delta)
			var far: bool = enemy.global_position.distance_to(player.global_position) > RE_ENGAGE_DIST
			if (far or not _engaged_sticky) and _repick_timer <= 0.0:
				# Re-seek only when cover actually exists, so cover-less
				# areas never flip-flop between SEEK and ENGAGED. #469: the
				# no-cover fallback re-scans at any range (it used to wait
				# for RE_ENGAGE_DIST, locking a close mob into the chase).
				if _pick_cover(enemy, player, false):
					_engaged_sticky = false
					_state = State.SEEK
					_away_timer = 0.0

# --- #420 seams (barricade deployer) ---------------------------------------

## True while a cover is held or being travelled to.
func has_cover() -> bool:
	return _has_cover

## True in the states where no cover is in use: looking for one (SEEK
## without a pick) or plain chase (ENGAGED). CHARGE is a commitment (#414)
## and is never interrupted.
func is_uncovered() -> bool:
	return not _has_cover and (_state == State.SEEK or _state == State.ENGAGED)

## True when at least one viable cover spot toward the player exists
## (the same candidate filter SEEK picks from).
func viable_cover_exists(enemy: Enemy, player: Player) -> bool:
	return not _cover_candidates(enemy, player).is_empty()

## Re-enter SEEK with an immediate rescan (e.g. right after a barricade was
## deployed, so it is picked up on this mover's next step).
func seek_now() -> void:
	_state = State.SEEK
	_repick_timer = 0.0
	_away_timer = 0.0

# --- SEEK / DASH ------------------------------------------------------------

func _seek(owner: EnemyBehaviorChaseContact, enemy: Enemy, player: Player, delta: float, fast: bool) -> void:
	if _has_cover and not _cover_still_valid(enemy):
		_drop_cover()
	if not _has_cover:
		if _repick_timer > 0.0 or not _pick_cover(enemy, player, false):
			# No cover in range: plain chase/contact until the next scan.
			_state = State.ENGAGED
			_engaged_sticky = false
			owner._chase_step(enemy, player, delta)
			return
	var speed: float = enemy.speed * (FAST_MULT if fast else 1.0)
	if _move(enemy, _hold_pos, speed, delta):
		_state = State.HOLD
		enemy.velocity = Vector2.ZERO
		_stall_timer = 0.0
		_hold_elapsed = 0.0 # #414: a fresh hold restarts the relocate clock
		_rock_timer = ROCK_FIRST_DELAY # #443: settle before the first rock
	elif enemy.velocity == Vector2.ZERO:
		# Wedged (unreachable hold point): give up on this cover.
		_stall_timer += delta
		if _stall_timer >= STALL_TIME:
			_stall_timer = 0.0
			_drop_cover()
			_state = State.ENGAGED
			# Sticky: re-scanning at once would re-pick the same unreachable
			# hold point and wedge again.
			_engaged_sticky = true
	else:
		_stall_timer = 0.0

# --- HOLD -------------------------------------------------------------------

func _hold(enemy: Enemy, player: Player, pointing: bool, delta: float) -> void:
	enemy.velocity = Vector2.ZERO
	EnemyBehaviorChaseContact._slide(enemy)
	_hold_elapsed += delta
	_tick_rock(enemy, player, delta)
	if _repick_timer > 0.0:
		return
	if not _cover_still_valid(enemy):
		_drop_cover()
		if _pick_cover(enemy, player, false):
			_state = State.DASH
		else:
			_state = State.ENGAGED
			_engaged_sticky = false
		return
	# Shelter is re-checked BEFORE the aim gate: a player who strafes
	# around the cover while still aiming at the mob must not leave it
	# standing exposed ("stay behind cover", not "stand still").
	if _flanked(enemy, player):
		# Reposition (possibly to the far side of the same object). No
		# cover left anywhere = the normal chase/contact fallback.
		if _pick_cover(enemy, player, false):
			_state = State.DASH
		else:
			_drop_cover()
			_state = State.ENGAGED
			_engaged_sticky = false
		return
	# #414 (Daniel, 2026-11-09: "moustache men periodically find nearby
	# cover if holding cover for over 5s"): held this cover too long -
	# relocate to a DIFFERENT nearby cover, aimed at or not. No other
	# cover around: keep holding, retry after another full period.
	if _hold_elapsed >= HOLD_RELOCATE_TIME:
		_hold_elapsed = 0.0
		if _pick_cover(enemy, player, false, true):
			_state = State.DASH
		return
	if pointing:
		return
	if _pick_cover(enemy, player, true):
		# Mouse is away: advance to a cover closer to the player.
		_state = State.DASH
	else:
		_repick_timer = REPICK_INTERVAL

# --- ROCK (#443) ------------------------------------------------------------

## HOLD-only rock clock: ticks from delta inside physics_step, so freeze
## (#305) and knockback (#331) pause it like the other timers.
func _tick_rock(enemy: Enemy, player: Player, delta: float) -> void:
	_rock_timer -= delta
	if _rock_timer > 0.0:
		return
	var dist: float = enemy.global_position.distance_to(player.global_position)
	if dist > ROCK_RANGE or dist < 1.0:
		_rock_timer = REPICK_INTERVAL # out of range: re-check soon
		return
	if enemy.terrain != null and enemy.terrain.lob_blocked(enemy.global_position, player.global_position):
		_rock_timer = REPICK_INTERVAL # a wall/stone block in the way: no throw
		return
	_rock_timer = ROCK_INTERVAL
	throw_rock(enemy, player.global_position)

## Spawns one rock from `enemy` toward `target` (the player's position at
## release). Range is per throw - a duplicate of the shared spell - so the
## rock lands ROCK_OVERSHOOT past the aim point instead of flying on.
func throw_rock(enemy: Enemy, target: Vector2) -> Projectile:
	var area: Node = enemy.get_parent()
	if area == null:
		return null
	var to: Vector2 = target - enemy.global_position
	var spell: Spell = ROCK_SPELL.duplicate()
	spell.range = minf(to.length() + ROCK_OVERSHOOT, ROCK_RANGE + ROCK_OVERSHOOT)
	var p: Projectile = PROJECTILE_SCENE.instantiate()
	p.setup(spell, to, enemy)
	p.position = enemy.global_position
	p.visual_override = RockVisual.new()
	# D14: never add to the tree synchronously from a physics step.
	area.call_deferred("add_child", p)
	enemy.play_action(&"ranged")
	rocks_thrown += 1
	return p

# --- CHARGE -----------------------------------------------------------------

func _charge(owner: EnemyBehaviorChaseContact, enemy: Enemy, player: Player, delta: float) -> void:
	_move(enemy, player.global_position, enemy.speed * FAST_MULT, delta)
	owner._contact_timer = maxf(0.0, owner._contact_timer - delta)
	var to_player: Vector2 = player.global_position - enemy.global_position
	if to_player.length() <= enemy.contact_range and owner._contact_timer <= 0.0:
		player.apply_damage(DamageCalc.compute(enemy.contact_damage, enemy.damage_modifiers, player.damage_modifiers, enemy.damage_rng).amount)
		owner._contact_timer = enemy.contact_cooldown
		enemy.play_action(&"attack")
		_state = State.ENGAGED
		_engaged_sticky = true # #469: post-charge ENGAGED keeps the RE_ENGAGE_DIST rule

# --- cover discovery --------------------------------------------------------

## Picks the nearest cover toward the player. With `advance_only`, only a
## cover that gets the enemy ADVANCE_MARGIN closer to the player than the
## currently held one qualifies. With `exclude_held` (#414 relocate), the
## currently held cover is skipped so the pick lands somewhere new.
## Returns whether a cover is held now.
func _pick_cover(enemy: Enemy, player: Player, advance_only: bool, exclude_held: bool = false) -> bool:
	var best: Dictionary = _best_candidate(enemy, player, _cover_candidates(enemy, player, false), advance_only, exclude_held)
	# #469: up close the strict toward-player tier is starved (cover must be
	# nearer than the player), so fall back to any sheltered cover in range.
	var relaxed: bool = best.is_empty() and enemy.global_position.distance_to(player.global_position) <= CLOSE_COVER_DIST
	if relaxed:
		best = _best_candidate(enemy, player, _cover_candidates(enemy, player, true), advance_only, exclude_held)
	_repick_timer = REPICK_INTERVAL
	if debug_trace:
		var dbg: Dictionary = {"want": true}
		_cover_candidates(enemy, player, relaxed, dbg)
		if relaxed:
			dbg["relaxed"] = true
		dbg.erase("want")
		var sig := str(dbg) + str(best.get("pos", Vector2.INF))
		if sig != _dbg_last:
			_dbg_last = sig
			print("[coverdbg] %s candidates=%d picked=%s rejects=%s" % [enemy.name, dbg.get("found", 0), ("none" if best.is_empty() else str(best["pos"])), str(dbg)])
	if best.is_empty():
		return false
	_has_cover = true
	_cover_cell = best.get("cell", Vector2i.ZERO)
	_cover_node = best.get("node", null)
	_cover_pos = best["pos"]
	_hold_pos = best["hold"]
	return true

## Nearest candidate (to the enemy) passing the advance/exclude filters.
func _best_candidate(enemy: Enemy, player: Player, candidates: Array[Dictionary], advance_only: bool, exclude_held: bool) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := INF
	for c in candidates:
		if exclude_held and _has_cover and (c["pos"] as Vector2) == _cover_pos:
			continue
		if advance_only and _has_cover:
			if (c["pos"] as Vector2).distance_to(player.global_position) >= _cover_pos.distance_to(player.global_position) - ADVANCE_MARGIN:
				continue
		var d: float = enemy.global_position.distance_to(c["pos"])
		if d < best_dist:
			best_dist = d
			best = c
	return best

## The held cover no longer shields the enemy from the player: the cover
## left the toward-player cone (FLANK_COS), or - for terrain cover - the
## enemy->player sightline no longer crosses any blocking material.
func _flanked(enemy: Enemy, player: Player) -> bool:
	var to_player: Vector2 = player.global_position - enemy.global_position
	var to_cover: Vector2 = _cover_pos - enemy.global_position
	if to_cover.length_squared() < 1.0 or to_cover.normalized().dot(to_player.normalized()) < FLANK_COS:
		return true
	if _cover_node == null and enemy.terrain != null:
		return not _sheltered(enemy.terrain, enemy.global_position, player.global_position)
	return false

## Body-width shelter: the sightline AND two parallel sightlines offset by
## +-SHELTER_HALF_WIDTH all cross blocking material, so a ray that merely
## grazes a cover corner does not count as "behind cover". Hold points
## built behind a cell centre (_cover_candidates) satisfy this by
## construction, so the candidate filter and the HOLD re-check agree.
func _sheltered(map: TerrainMap, pos: Vector2, watcher: Vector2) -> bool:
	var d := watcher - pos
	if d.length_squared() < 1.0:
		return false
	var off := d.normalized().orthogonal() * SHELTER_HALF_WIDTH
	return _occluded(map, pos, watcher) and _occluded(map, pos + off, watcher + off) and _occluded(map, pos - off, watcher - off)

func _drop_cover() -> void:
	_has_cover = false
	_cover_node = null

func _hook_terrain_signals(enemy: Enemy) -> void:
	if enemy.terrain == _signal_map:
		return
	if _signal_map != null and is_instance_valid(_signal_map):
		if _signal_map.cell_destroyed.is_connected(_on_terrain_cell_changed):
			_signal_map.cell_destroyed.disconnect(_on_terrain_cell_changed)
		if _signal_map.cell_interacted.is_connected(_on_terrain_cell_changed):
			_signal_map.cell_interacted.disconnect(_on_terrain_cell_changed)
	_signal_map = enemy.terrain
	if _signal_map != null:
		_signal_map.cell_destroyed.connect(_on_terrain_cell_changed)
		_signal_map.cell_interacted.connect(_on_terrain_cell_changed)

## TerrainMap destroy/interact paths emit these; a held terrain cover
## whose cell just changed is dropped immediately (the poll stays for
## raw set_cell/clear_cell edits, which emit nothing).
func _on_terrain_cell_changed(cell: Vector2i, _old_type = null, _new_type = null, _rule_id = null) -> void:
	if _has_cover and _cover_node == null and cell == _cover_cell:
		_drop_cover()

func _cover_still_valid(enemy: Enemy) -> bool:
	if _cover_node != null:
		return is_instance_valid(_cover_node)
	if enemy.terrain == null:
		return false
	var props := enemy.terrain.type_properties(enemy.terrain.tile_type_at_cell(_cover_cell))
	return props.get("movement", TerrainTypes.Movement.WALKABLE) == TerrainTypes.Movement.BLOCKING and not props.get("swimmable", false)

## Every cover candidate near the enemy that lies toward the player and
## provides real shelter: {pos, hold, cell?|node?}. `hold` sits just behind
## the cover on the side away from the player, on ground this mover can
## enter, and is occluded from the player by blocking material.
## `relaxed` (#469, close range only - see CLOSE_COVER_DIST) drops the
## toward-player tier rules (nearer than the player, inside the cone); the
## shelter rules (walkable hold, body-width occlusion) still apply.
func _cover_candidates(enemy: Enemy, player: Player, relaxed: bool = false, dbg: Dictionary = {}) -> Array[Dictionary]:
	var want: bool = dbg.get("want", false)
	var rej := {"blocking_scan": 0, "not_blocking_or_swim": 0, "too_close_or_beyond": 0, "outside_cone": 0, "hold_unwalkable": 0, "not_occluded": 0, "solid_reject": 0}
	var out: Array[Dictionary] = []
	var to_player: Vector2 = player.global_position - enemy.global_position
	var dist_p: float = to_player.length()
	if dist_p < 1.0:
		return out
	var dir_p: Vector2 = to_player / dist_p
	var map: TerrainMap = enemy.terrain
	if map == null and want:
		rej["no_terrain"] = 1
	if map != null:
		var cs: float = float(map.cell_size)
		var lo := map.world_to_cell(enemy.global_position - Vector2(COVER_SEARCH_RADIUS, COVER_SEARCH_RADIUS))
		var hi := map.world_to_cell(enemy.global_position + Vector2(COVER_SEARCH_RADIUS, COVER_SEARCH_RADIUS))
		for cx in range(lo.x, hi.x + 1):
			for cy in range(lo.y, hi.y + 1):
				var cell := Vector2i(cx, cy)
				var props := map.type_properties(map.tile_type_at_cell(cell))
				rej["blocking_scan"] += 1
				if props.get("movement", TerrainTypes.Movement.WALKABLE) != TerrainTypes.Movement.BLOCKING or props.get("swimmable", false):
					rej["not_blocking_or_swim"] += 1
					continue
				var cpos := map.cell_to_world(cell)
				var d: Vector2 = cpos - enemy.global_position
				var dist := d.length()
				if dist < cs * 0.75 or (dist >= dist_p and not relaxed):
					rej["too_close_or_beyond"] += 1
					continue
				if not relaxed and d.normalized().dot(dir_p) < COVER_CONE_COS:
					rej["outside_cone"] += 1
					continue
				var hold: Vector2 = cpos + (cpos - player.global_position).normalized() * (cs * 0.5 + STANDOFF)
				if not _hold_walkable(map, hold, enemy.can_swim):
					rej["hold_unwalkable"] += 1
					continue
				if not _sheltered(map, hold, player.global_position):
					rej["not_occluded"] += 1
					continue
				out.append({"pos": cpos, "hold": hold, "cell": cell})
	if want:
		rej["found"] = out.size()
		for k in rej: dbg[k] = rej[k]
	# Solids: any Node2D that opted into the "cover" group (containers,
	# future objects) - Daniel: "any cover", not hardcoded to trees. The
	# hold point sits behind the body, so the body itself occludes it.
	for n in enemy.get_tree().get_nodes_in_group(&"cover"):
		var solid := n as Node2D
		if solid == null or not is_instance_valid(solid):
			continue
		var spos: Vector2 = solid.global_position
		var sd: Vector2 = spos - enemy.global_position
		var sdist := sd.length()
		if sdist > COVER_SEARCH_RADIUS or sdist < SOLID_RADIUS * 0.5 or (sdist >= dist_p and not relaxed):
			continue
		if not relaxed and sd.normalized().dot(dir_p) < COVER_CONE_COS:
			continue
		# Relaxed: a solid hugging the player can't put a body between them.
		if relaxed and spos.distance_to(player.global_position) < SOLID_RADIUS + STANDOFF:
			continue
		var shold: Vector2 = spos + (spos - player.global_position).normalized() * (SOLID_RADIUS + STANDOFF)
		if map != null and not _hold_walkable(map, shold, enemy.can_swim):
			continue
		out.append({"pos": spos, "hold": shold, "node": solid})
	return out

func _hold_walkable(map: TerrainMap, pos: Vector2, can_swim: bool) -> bool:
	var props := map.properties_at(pos)
	return props.get("walkable", true) or (props.get("swimmable", false) and can_swim)

## Geometric occlusion: the segment pos->watcher crosses at least one
## blocking, non-swimmable cell (half-cell sampling, the TerrainPath line
## idiom). A hold point placed behind its own cover cell satisfies this by
## construction; the check rejects wall-adjacent cells whose "behind" still
## sees the player around a corner.
func _occluded(map: TerrainMap, pos: Vector2, watcher: Vector2) -> bool:
	var dist := pos.distance_to(watcher)
	var steps := int(ceil(dist / (map.cell_size * 0.5))) + 1
	for i in steps + 1:
		var cell := map.world_to_cell(pos.lerp(watcher, float(i) / steps))
		var props := map.type_properties(map.tile_type_at_cell(cell))
		if props.get("movement", TerrainTypes.Movement.WALKABLE) == TerrainTypes.Movement.BLOCKING and not props.get("swimmable", false):
			return true
	return false

# --- helpers ----------------------------------------------------------------

## Mouse-pointing test: the player's aim (node rotation is the #137 aim
## contract, driven by the cursor) falls within AIM_CONE of the
## player->enemy direction.
func _is_pointed_at(enemy: Enemy, player: Player) -> bool:
	var to_enemy: Vector2 = enemy.global_position - player.global_position
	if to_enemy.length() < 1.0:
		return true
	var aim := Vector2.from_angle(player.global_rotation)
	return aim.dot(to_enemy.normalized()) >= AIM_CONE_COS

## Steered move toward `dest` (per-helper TerrainPath routing, the parent's
## _slide); returns true when the hold point is reached.
func _move(enemy: Enemy, dest: Vector2, speed: float, delta: float) -> bool:
	var to: Vector2 = dest - enemy.global_position
	if to.length() <= WAYPOINT_EPS:
		return true
	var desired: Vector2 = to.normalized() * speed
	enemy.velocity = _terrain_path.steer(enemy.terrain, enemy.global_position, enemy.velocity, desired, dest, speed, delta, enemy.can_swim)
	EnemyBehaviorChaseContact._slide(enemy)
	return false
