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

const TOKEN_COLOR := Color(0.75, 0.45, 1.0)
const RELIC_COLOR := Color(0.3, 0.95, 0.85)

func setup(p_entry: RewardEntry) -> void:
	entry = p_entry

func _ready() -> void:
	add_to_group("reward_drops")
	if entry == null:
		push_warning("RewardDrop: no entry assigned.")
		return
	if entry.kind == RewardEntry.Kind.CURRENCY:
		# #128 placeholder presentation: gold diamond labeled with the amount.
		$NameLabel.text = "%dc" % entry.currency_amount
		$Visual.color = Color(1.0, 0.85, 0.2)
	elif entry.kind == RewardEntry.Kind.UPGRADE_TOKEN:
		# #315 placeholder presentation (art is human-open): violet diamond.
		$NameLabel.text = "Upgrade Token"
		$Visual.color = TOKEN_COLOR
	elif entry.kind == RewardEntry.Kind.RELIC:
		# #426 placeholder presentation (art is human-open): teal diamond
		# labeled with the relic name.
		if entry.relic == null:
			push_warning("RewardDrop: no relic entry assigned.")
			return
		$NameLabel.text = entry.relic.display_name
		$Visual.color = RELIC_COLOR
	elif entry.spell == null:
		push_warning("RewardDrop: no spell entry assigned.")
		return
	else:
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
	if entry.kind == RewardEntry.Kind.SPELL and entry.spell != null:
		# #383: the player already holds this logical spell (any source, or
		# an upgraded form): consume without grant, pool change or signal.
		var holder := body.get_node_or_null("SpellCaster")
		if holder != null and holder.has_method("has_logical_spell") and holder.has_logical_spell(entry.spell):
			print("[rewards] duplicate spell floor copy consumed (#383)")
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
		print("spell unlocked: ", entry.spell.spell_name)
	elif entry.kind == RewardEntry.Kind.CURRENCY:
		# #128: currency routes to the run wallet mounted on Main. Currency
		# stays pool-eligible after grant (Daniel, 2026-11-07), so the pool
		# call above is a no-op for CURRENCY and drops can repeat.
		var wallet := get_tree().get_first_node_in_group("currency_wallet") as CurrencyWallet
		if wallet != null:
			wallet.add(entry.currency_amount)
		else:
			# Defensive fallback only: the wallet mount is live on main.
			push_warning("RewardDrop: currency wallet unavailable; pool grant recorded only.")
		print("[rewards] currency collected: +", entry.currency_amount)
	elif entry.kind == RewardEntry.Kind.UPGRADE_TOKEN:
		# #315: the token goes to the run's SpellProgress (mounted on Main);
		# it is spent from the Tab panel's Upgrades section.
		var progress := get_tree().get_first_node_in_group("spell_progress") as SpellProgress
		if progress != null:
			progress.add_upgrade_token(1)
		else:
			push_warning("RewardDrop: SpellProgress unavailable; upgrade token lost.")
		print("[rewards] upgrade token collected")
	elif entry.kind == RewardEntry.Kind.RELIC:
		# #426: OwnedRelics.add refuses an already-owned id (a second boss
		# drop picked up after the first), so the copy is consumed with no
		# grant and no signal - Daniel's "no duplicates from any source".
		var relics := get_tree().get_first_node_in_group("owned_relics") as OwnedRelics
		if relics == null or not relics.add(entry.relic):
			print("[rewards] relic not granted (already owned or no OwnedRelics) - copy consumed (#426)")
			queue_free()
			return
		print("[rewards] relic collected: ", entry.relic.display_name)
	else:
		# Item rewards unwired until #54 content approval.
		print("[rewards] item drop collected; item route unwired (#54 pending)")
	collected.emit(self, entry)
	set_deferred("monitoring", false)
	visible = false
	# #72: a GRANTED drop has completed its lifecycle - free it like the stale
	# path does, so it does not linger as a dead "reward_drops" group member
	# until area swap. Pool removal / unlock / collected signal all precede
	# this; grant/stale/restart semantics and loot policies unchanged.
	queue_free()
