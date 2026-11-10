extends SceneTree
## #465 rendered demo (production mount: Main -> overworld -> DungeonA, real
## mobs carrying the production table): regular mobs now drop CURRENCY
## ONLY. Two mobs die (SYNTHETIC KILLS via apply_damage - the drop wiring
## is what is being shown, not combat), gold "5c" drops appear, and
## walk-over pickup adds them to the run wallet (counter top-left). Run
## under xvfb with --write-movie; quits itself.

var _p: Player
var _main: Node
var _label: Label
var _wallet: CurrencyWallet
var _phase := ""

func _enter(gate_name: String) -> void:
	var gate: Gate = _main.current_area.get_node(gate_name)
	gate._on_body_entered(_p)
	for i in 3:
		await _frame()

func _initialize() -> void:
	Bestiary.save_path = "user://rec465_bestiary.cfg"
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	_p = _main.get_node("Player")
	var hud0 := CanvasLayer.new()
	_main.add_child(hud0)
	_label = Label.new()
	_label.position = Vector2(24, 120)
	_label.add_theme_font_size_override("font_size", 26)
	hud0.add_child(_label)
	for i in 60:
		if _main.current_area != null:
			break
		await _frame()
	_wallet = Run.wallet()

	_phase = "into DungeonA (real mobs, real production loot table)"
	await _enter("GateOverworld")
	await _enter("GateNormal")
	var area: Node2D = _main.current_area
	for i in 20:
		await _frame()

	# Stand the player next to the first mob, then kill it (synthetic).
	var mobs: Array[Enemy] = []
	for n in area.get_children():
		if n is Enemy:
			mobs.append(n)
	mobs.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
	var m1: Enemy = mobs[0]
	var m2: Enemy = mobs[1]
	# Capture kill spots now: death queue_frees the enemy.
	var spot1: Vector2 = m1.global_position
	var spot2: Vector2 = m2.global_position
	_p.global_position = spot1 + Vector2(-160, 0)
	_phase = "a regular mob dies (synthetic kill)..."
	await _frames(40)
	m1.apply_damage(9999)
	_phase = "...and drops CURRENCY - no spells in regular-mob loot any more"
	await _frames(70)

	_phase = "walk over it: +5c into the run wallet"
	var drop1 := _find_drop()
	if drop1 != null:
		_p.global_position = drop1.global_position
	await _frames(50)

	_p.global_position = spot2 + Vector2(0, 120)
	_phase = "second mob (synthetic kill): currency again, every time"
	await _frames(30)
	m2.apply_damage(9999)
	await _frames(50)
	var drop2 := _find_drop()
	if drop2 != null:
		_p.global_position = drop2.global_position
	_phase = "picked up again - currency drops repeat (bosses/beasts unchanged)"
	await _frames(60)
	quit(0)

func _find_drop() -> RewardDrop:
	for d in get_nodes_in_group("reward_drops"):
		return d as RewardDrop
	return null

func _frames(n: int) -> void:
	for i in n:
		await _frame()

func _frame() -> void:
	await physics_frame
	_p.hp = _p.max_hp
	_label.text = "#465: regular mobs drop currency only (wallet: %dc)\n%s" % [_wallet.balance() if _wallet != null else 0, _phase]
	await process_frame
