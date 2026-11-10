extends SceneTree
## #513: presentation data retains geometry, animation and reset/chain hooks.
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("[513 presentation] ", label, " -> ", "PASS" if ok else "FAIL")
func _initialize() -> void:
	var h := EnemyBehaviorHead.new()
	var b := EnemyBehaviorBeast.new()
	var w := EnemyBehaviorWarlord.new()
	_check(h.presentations.size() == 2 and b.presentations.size() == 2 and w.presentations.size() == 3, "all attacks represented")
	var hv = h.presentations[BossBehavior.Attack.VOLLEY]
	_check(hv.animation == &"projectile" and hv.next_state == BossBehavior.State.VOLLEY and hv.length == 230.0 and hv.clear_on_start, "head volley presentation")
	var hp = h.presentations[BossBehavior.Attack.PULSE]
	_check(hp.animation == &"aoe" and hp.phase_ring and not hp.clear_on_start, "head pulse retains windup ring")
	var bl = b.presentations[BossBehavior.Attack.LUNGE]
	_check(bl.animation == &"bite" and bl.length == 210.0 and is_equal_approx(bl.width,36.0) and bl.clear_on_start, "beast lunge geometry")
	var bs = b.presentations[BossBehavior.Attack.SCREAM]
	_check(bs.animation == &"aoe" and bs.phase_ring and not bs.clear_on_start, "beast scream retains phase ring")
	var wl = w.presentations[BossBehavior.Attack.LUNGE]
	_check(wl.animation == &"lunge" and wl.length == 190.0 and is_equal_approx(wl.width,34.8), "warlord lunge geometry")
	var ws = w.presentations[BossBehavior.Attack.SPIN]
	_check(ws.animation == &"spin" and ws.radius == 72.0 and ws.start_ring and ws.start_duration == 0.95, "warlord spin starts original active ring")
	var wv = w.presentations[BossBehavior.Attack.VOLLEY]
	_check(wv.animation == &"ranged" and wv.length == 220.0 and wv.clear_on_start, "warlord volley geometry")
	h._pulses = 2
	h._waves_fired = 2
	h._attack_begin_reset()
	_check(h._pulses == 0 and h._waves_fired == 0, "head counters reset")
	b._lunges = 1
	b.attack = BossBehavior.Attack.LUNGE
	b._attack_begin_reset()
	b._attack_begin_count()
	_check(b._lunges == 2 and b._hits == 0, "beast chain count survives reset")
	b._screams = 1
	b.attack = BossBehavior.Attack.SCREAM
	b._attack_begin_count()
	_check(b._screams == 0, "beast scream counter reset")
	w._hits = 1
	w._tick_t = 0.5
	w._waves_fired = 2
	w._attack_begin_reset()
	_check(w._hits == 0 and w._tick_t == 0.0 and w._waves_fired == 0, "warlord counters reset")
	quit(1 if failures else 0)
