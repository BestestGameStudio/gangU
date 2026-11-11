extends Node2D
## #6 EVIDENCE driver (test-only). Proves:
## (a) casting works while alive (baseline);
## (b) DEAD player can NOT cast during the death pause - the alive guard:
##     zero projectile spawns, zero cooldown_started, zero spell_cast;
## (c) death restarts the run and collected spells reset to the starting set;
## (d) casting works again after the restart (regression);
## (e) the cycle repeats. GANGU_AUTOTEST=1 prints headless evidence lines.

static var run_count := 0
static var guard_active := false
static var dead_projectiles := 0
static var dead_casts := 0
static var dead_cooldowns := 0

@onready var debug: Label = $DebugLabel
var _status := ""
var _phase := 0 ## 0 baseline cast, 2 hammer cast during death pause, 3 post-restart cast, 4 done
var _t := 0.0
var _p: Player
var _caster: SpellCaster
var _alive_casts := 0
var _alive_cooldowns := 0
var _spawned := 0

func _ready() -> void:
	run_count += 1
	_p = Player.find(get_tree())
	_caster = _p.get_node_or_null("SpellCaster")
	var rm: RunManager = $RunManager
	rm.player = _p ## production-style explicit wiring
	Input.warp_mouse(Vector2(576, 600)) ## aim at empty floor, away from enemies
	child_entered_tree.connect(func(c): if c is Projectile:
		_spawned += 1
		if guard_active:
			dead_projectiles += 1)
	_caster.spell_cast.connect(func(_s):
		_alive_casts += 1
		if guard_active:
			dead_casts += 1)
	_caster.cooldown_started.connect(func(_s, _d):
		_alive_cooldowns += 1
		if guard_active:
			dead_cooldowns += 1)
	print("[run] start run=", run_count, " hp=", _p.hp, " enemies=", get_tree().get_nodes_in_group("enemies").size(), " spells=", _caster.spells.size())
	if run_count == 1:
		var picked := Spell.new()
		picked.mode = Spell.CastMode.PROJECTILE
		picked.spell_name = "PickedUpTestSpell"
		_caster.add_spell(picked)
		print("[run] collected extra spell, spells=", _caster.spells.size())
	if run_count >= 2:
		print("[guard] run ", run_count - 1, " death pause: dead projectiles=", dead_projectiles, " dead casts=", dead_casts, " dead cooldowns=", dead_cooldowns, " -> ", "PASS (all zero)" if dead_projectiles == 0 and dead_casts == 0 and dead_cooldowns == 0 else "FAIL")
		dead_projectiles = 0; dead_casts = 0; dead_cooldowns = 0
		guard_active = false
		_phase = 3
	_p.died.connect(func(): print("[run] died, restart pending, casting disabled"); _status = "died, restarting")
	rm.run_restarting.connect(func(): print("[run] run_restarting emitted"))
	if OS.get_environment("GANGU_AUTOTEST") == "1":
		get_tree().create_timer(12.0).timeout.connect(func(): print("[run] evidence window over, quitting"); get_tree().quit())

func _process(delta: float) -> void:
	_t += delta
	match _phase:
		0: ## baseline: alive cast must work
			if _t > 0.3:
				Input.action_press(&"cast")
			if _t > 0.45:
				Input.action_release(&"cast")
				print("[guard] alive baseline cast: casts=", _alive_casts, " cooldowns=", _alive_cooldowns, " projectiles=", _spawned, " -> ", "OK" if _alive_casts >= 1 and _spawned >= 1 else "FAIL")
				_p.apply_damage(100)
				guard_active = true
				_phase = 2; _t = 0.0
		2: ## death pause: hammer the cast input; nothing may come out
			if int(_t * 20.0) % 2 == 0:
				Input.action_press(&"cast")
			else:
				Input.action_release(&"cast")
		3: ## post-restart regression: cast must work again
			if _t > 0.3:
				Input.action_press(&"cast")
			if _t > 0.45:
				Input.action_release(&"cast")
				print("[guard] post-restart cast: casts=", _alive_casts, " cooldowns=", _alive_cooldowns, " projectiles=", _spawned, " -> ", "OK (regression clear)" if _alive_casts >= 1 and _spawned >= 1 else "FAIL")
				if run_count < 3:
					_p.apply_damage(100)
					guard_active = true
					_phase = 2; _t = 0.0
				else:
					print("[run] repeatable restart verified over ", run_count, " runs")
					_phase = 4
	debug.text = "run " + str(run_count) + " | hp " + str(_p.hp) + " | spells " + str(_caster.spells.size()) + " | " + _status
