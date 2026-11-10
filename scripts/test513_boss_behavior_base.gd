extends SceneTree
## #513 PART1 harness: shared BossBehavior base extracted from the three
## boss behaviors (#173 Head, #174 Beast, #177 Warlord). Behavior is meant
## to be unchanged; these legs pin the extraction's contract:
##   (1) the three boss brains are BossBehavior instances (RefCounted base);
##   (2) subclass enum access still resolves (State/Attack through the
##       subclass names, as the existing boss tests use them);
##   (3) timing constants survived the move (per-boss values unchanged);
##   (4) the initial attack timer comes from each boss's FIRST_ATTACK_DELAY;
##   (5) the anti-repeat picker never allows three in a row and caps its
##       history at 4;
##   (6) wind-up durations are per-boss, incl. the Beast's enraged
##       chain-pause override;
##   (7) stun-phase opt-in: Head/Beast yes, Warlord no.
## All legs are direct instance checks - no physics frames needed.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[513] ", name, " -> PASS")
	else:
		failures += 1
		print("[513] ", name, " -> FAIL")

func _init() -> void:
	# (1) inheritance
	var head := EnemyBehaviorHead.new()
	var beast := EnemyBehaviorBeast.new()
	var warlord := EnemyBehaviorWarlord.new()
	_check(head is BossBehavior and head is RefCounted, "head is a BossBehavior")
	_check(beast is BossBehavior, "beast is a BossBehavior")
	_check(warlord is BossBehavior, "warlord is a BossBehavior")

	# (2) enums resolve through the subclass names (values are the union's)
	_check(EnemyBehaviorHead.State.STUN == BossBehavior.State.STUN, "head State.STUN resolves")
	_check(EnemyBehaviorBeast.State.SCREAM == BossBehavior.State.SCREAM, "beast State.SCREAM resolves")
	_check(EnemyBehaviorWarlord.Attack.SPIN == BossBehavior.Attack.SPIN, "warlord Attack.SPIN resolves")
	_check(EnemyBehaviorHead.Attack.VOLLEY != EnemyBehaviorHead.Attack.PULSE, "attack values distinct")

	# (3) timing constants unchanged
	_check(EnemyBehaviorHead.FIRST_ATTACK_DELAY == 1.0 and EnemyBehaviorHead.ATTACK_INTERVAL == 1.8
		and EnemyBehaviorHead.ENRAGED_INTERVAL == 1.0 and EnemyBehaviorHead.RECOVER_TIME == 0.5
		and EnemyBehaviorHead.STUN_TIME == 1.6, "head timing constants unchanged")
	_check(EnemyBehaviorWarlord.FIRST_ATTACK_DELAY == 1.2 and EnemyBehaviorWarlord.ATTACK_INTERVAL == 1.9
		and EnemyBehaviorWarlord.ENRAGED_INTERVAL == 1.1 and EnemyBehaviorWarlord.RECOVER_TIME == 0.45,
		"warlord timing constants unchanged")
	_check(EnemyBehaviorBeast.FIRST_ATTACK_DELAY == 1.0 and EnemyBehaviorBeast.ATTACK_INTERVAL == 1.7
		and EnemyBehaviorBeast.ENRAGED_INTERVAL == 1.0 and EnemyBehaviorBeast.RECOVER_TIME == 0.5
		and EnemyBehaviorBeast.STUN_TIME == 1.6, "beast timing constants unchanged")
	_check(BossBehavior.AIM_LOCK_AT == 0.6, "shared aim-lock fraction is 0.6")

	# (4) initial attack timer = each boss's FIRST_ATTACK_DELAY
	_check(head._attack_timer == 1.0, "head initial attack timer 1.0")
	_check(warlord._attack_timer == 1.2, "warlord initial attack timer 1.2")
	_check(beast._attack_timer == 1.0, "beast initial attack timer 1.0")

	# (5) anti-repeat picker
	var picker := BossBehavior.new()
	_check(picker._history_pick(1, 2) == 1, "picker first pick kept")
	_check(picker._history_pick(1, 2) == 1, "picker second pick kept")
	_check(picker._history_pick(1, 2) == 2, "picker third same pick falls back")
	for i in 8:
		picker._history_pick(0, 1)
	_check(picker._history.size() <= 4, "picker history capped at 4")

	# (6) wind-up durations
	_check(head._windup_time(EnemyBehaviorHead.Attack.VOLLEY) == 0.7
		and head._windup_time(EnemyBehaviorHead.Attack.PULSE) == 0.75, "head wind-up times")
	_check(warlord._windup_time(EnemyBehaviorWarlord.Attack.LUNGE) == 0.6
		and warlord._windup_time(EnemyBehaviorWarlord.Attack.SPIN) == 0.5
		and warlord._windup_time(EnemyBehaviorWarlord.Attack.VOLLEY) == 0.65, "warlord wind-up times")
	_check(beast._windup_time(EnemyBehaviorBeast.Attack.LUNGE) == 0.65
		and beast._windup_time(EnemyBehaviorBeast.Attack.SCREAM) == 0.75, "beast wind-up times")
	beast.attack = BossBehavior.Attack.LUNGE
	beast._lunges = 0
	_check(beast._windup_duration() == 0.65, "beast first lunge wind-up")
	beast._lunges = 1
	_check(beast._windup_duration() == EnemyBehaviorBeast.LUNGE_CHAIN_PAUSE, "beast chain pause wind-up")
	beast._windup_reset(BossBehavior.Attack.LUNGE)
	_check(beast._lunges == 0, "beast wind-up reset clears lunge chain")

	# (7) stun-phase opt-in
	_check(head._has_stun_phase() and beast._has_stun_phase(), "head and beast stun once")
	_check(not warlord._has_stun_phase(), "warlord has no stun phase")

	print("[513] DONE failures=", failures)
	quit(1 if failures > 0 else 0)
