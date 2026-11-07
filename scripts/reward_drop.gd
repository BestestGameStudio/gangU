class_name RewardDrop
extends Area2D
## Reward drop (track A, #59): a reward lying where an enemy died. Walk-over
## auto-pick-up (approved by Daniel, 2026-11-07): the entry leaves the reward
## pool and, for spells, UNLOCKS on the player's caster for later equip - no
## auto-equip. The item route stays UNWIRED until the #54 content decision.
## Wiring follows the ReviveItem precedent: the pool is found via the
## "reward_pool" group; the drop itself is area-owned and freed on area swap.

signal collected(drop: RewardDrop, entry: RewardEntry)

var entry: RewardEntry

func setup(p_entry: RewardEntry) -> void:
	entry = p_entry

func _ready() -> void:
	add_to_group("reward_drops")
	if entry == null or entry.spell == null:
		push_warning("RewardDrop: no spell entry assigned.")
		return
	$NameLabel.text = entry.spell.spell_name
	$Visual.color = entry.spell.projectile_color
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if not (body is Player):
		return
	var pool := get_tree().get_first_node_in_group("reward_pool") as RewardPool
	if pool != null and not pool.is_eligible(entry):
		# Already granted this run: consume without re-granting. Inert + log;
		# FIXTURE PROVISIONAL behavior - production duplicate floor-copy policy
		# is an open human choice (#59).
		print("[rewards] ineligible floor copy consumed (fixture provisional)")
		queue_free()
		return
	if pool != null:
		pool.remove_on_grant(entry)
	if entry.kind == RewardEntry.Kind.SPELL:
		var caster := body.get_node_or_null("SpellCaster")
		if caster != null and caster.has_method("unlock_spell"):
			caster.unlock_spell(entry.spell)
		else:
			# Defensive fallback only: unlock_spell is live on main. If the
			# caster is absent or predates it, the grant stays pool-recorded.
			push_warning("RewardDrop: caster.unlock_spell unavailable; pool grant recorded only.")
	else:
		# Item rewards unwired until #54 content approval.
		print("[rewards] item drop collected; item route unwired (#54 pending)")
	collected.emit(self, entry)
	print("spell unlocked: ", entry.spell.spell_name)
	set_deferred("monitoring", false)
	visible = false
	# #72: a GRANTED drop has completed its lifecycle - free it like the stale
	# path does, so it does not linger as a dead "reward_drops" group member
	# until area swap. Pool removal / unlock / collected signal all precede
	# this; grant/stale/restart semantics and loot policies unchanged.
	queue_free()
