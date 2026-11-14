extends SceneTree
## #131: fixture-only relics; no production content or balance.
var failures := 0
var checks := 0

class Target extends Node2D:
	var damage_modifiers := DamageModifiers.new()
	var received := 0
	func apply_damage(n: int) -> void:
		received += n

class RefusingOwned extends OwnedRelics:
	func add(_r: Relic) -> bool:
		return false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("[131] ", label, " -> ", "PASS" if ok else "FAIL")

func relic(key: StringName, amp: float = 0.25) -> Relic:
	var r := Relic.new()
	r.id = key
	r.display_name = "Fixture relic"
	r.hooked_tags = [SpellTags.PROJECTILE]
	r.amount = amp
	return r

func entry(r: Relic) -> ShopEntry:
	var e := ShopEntry.new()
	e.good = r
	e.price = 3 # fixture only
	return e

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for child in root.get_children():
		child.free()
	var packed := load("res://game/core/main.tscn") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var owned := main.get_node("OwnedRelics") as OwnedRelics
	var shop := main.get_node("Shop") as Shop
	var player := main.get_node("Player") as Player
	player.set_physics_process(false)
	var r := relic(&"fixture_a")
	var events: Array = []
	owned.changed.connect(func(): events.append(true))
	check(owned != null and Run.relics() == owned, "production mount/Run.relics()")
	check(r.is_valid_definition(), "valid stable id/tag definition")
	var invalid := relic(&"")
	check(not owned.add(invalid), "empty identity refused")
	invalid.id = &"invalid_tag"
	invalid.hooked_tags = [&"not_a_tag"]
	check(not owned.add(invalid), "unknown controlled tag refused")
	check(owned.add(r), "direct acquisition succeeds")
	check(owned.has_id(r.id) and owned.count() == 1, "central owned set")
	check(not owned.add(r.duplicate(true)), "copied logical identity refused")
	var reloaded := relic(r.id)
	check(not owned.add(reloaded), "separate resource same id refused")
	check(events.size() == 1, "changed only on successful add")
	ResourceSaver.save(r, "user://test131_fixture.tres")
	var loaded := ResourceLoader.load("user://test131_fixture.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as Relic
	check(loaded != r and not owned.add(loaded), "serialized reload same id refused")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test131_fixture.tres"))
	var copy := owned.all()
	copy.clear()
	check(owned.count() == 1, "all returns array copy")
	var other := relic(&"fixture_b", 0.0)
	other.scalar_effects = {&"fixture_scalar": 2.0}
	check(owned.add(other), "equally named distinct id remains distinct")
	var spell := Spell.new()
	spell.mode = Spell.CastMode.PROJECTILE
	spell.tags = [SpellTags.PROJECTILE]
	spell.damage = 20
	var mods := owned.modifiers_for(spell)
	check(mods.size() == 1 and is_equal_approx(mods[0].amount, 0.25), "tag matched optional damage payload")
	check(mods[0] != owned.modifiers_for(spell)[0], "fresh modifier instances")
	mods[0].amount = 99
	check(is_equal_approx(owned.modifiers_for(spell)[0].amount, 0.25), "modifier mutation cannot corrupt definition")
	check(is_equal_approx(owned.query(&"fixture_scalar", spell.tags), 2.0), "generic non-damage scalar query")
	check(owned.query(&"unknown", spell.tags) == 0.0, "unknown scalar is neutral")
	check(owned.query(&"fixture_scalar", [SpellTags.MELEE]) == 0.0, "generic tag mismatch neutral")
	var crit := relic(&"fixture_crit", 0.0)
	crit.stage = DamageModifier.Stage.CRIT
	crit.chance = 1.0
	crit.multiplier = 2.0
	var c := crit.to_modifier()
	check(c.stage == DamageModifier.Stage.CRIT and c.chance == 1.0 and c.multiplier == 2.0, "adapter supports non-AMP stages")
	var untagged := Spell.new()
	untagged.mode = Spell.CastMode.PROJECTILE
	check(owned.modifiers_for(untagged).is_empty(), "untagged spell unchanged")
	check(owned.modifiers_for(null).is_empty(), "null query empty")

	# Real projectile setup BEFORE tree entry, same as SpellCaster._fire.
	var target := Target.new()
	main.add_child(target)
	var projectile_scene := load("res://game/spells/projectile.tscn") as PackedScene
	var p := projectile_scene.instantiate() as Projectile
	p.setup(spell, Vector2.RIGHT, player)
	main.add_child(p)
	p._on_body_entered(target)
	check(target.received == 25, "actual projectile hit + DamageCalc includes relic AMP")
	check(player.damage_modifiers.items().is_empty(), "source modifier collection not mutated")
	var p2 := projectile_scene.instantiate() as Projectile
	p2.setup(spell, Vector2.RIGHT, player)
	main.add_child(p2)
	p2._on_body_entered(target)
	check(target.received == 50, "repeated casts do not accumulate relic AMP")
	var enemy := Enemy.new()
	# Enemy source need not enter tree to prove it cannot use player relics.
	var ep := projectile_scene.instantiate() as Projectile
	ep.setup(spell, Vector2.RIGHT, enemy)
	main.add_child(ep)
	ep._on_body_entered(target)
	check(target.received == 70, "enemy projectile does not receive player relic")
	enemy.free()
	Run.unregister(owned)
	var plain := projectile_scene.instantiate() as Projectile
	plain.setup(spell, Vector2.RIGHT, player)
	main.add_child(plain)
	plain._on_body_entered(target)
	check(target.received == 90, "absent provider retains original damage")
	Run.register(owned)

	# Shop mounted BEFORE OwnedRelics: lazy provider must still work.
	var catalog := ShopCatalog.new()
	var duplicate_entry := entry(reloaded)
	var fresh := relic(&"shop_fixture")
	var fresh_entry := entry(fresh)
	catalog.entries = [duplicate_entry, fresh_entry]
	shop.setup(catalog)
	var wallet := main.get_node("CurrencyWallet") as CurrencyWallet
	wallet.add(20)
	check(not shop.can_grant(reloaded), "shop excludes directly acquired logical id")
	check(not shop.offerable_entries().has(duplicate_entry), "owned offer excluded")
	check(shop.can_grant(fresh), "lazy provider resolves later Main mount")
	check(shop.buy(fresh_entry) and wallet.balance() == 17 and owned.has_id(fresh.id), "shop charges and grants centrally")
	check(not owned.add(relic(fresh.id)), "shop acquisition cannot duplicate from another source")
	check(not shop.buy(fresh_entry) and wallet.balance() == 17, "duplicate buy refuses without charge")
	shop.owned_relics_path = NodePath("../OwnedRelics")
	check(not shop.can_grant(fresh), "explicit provider path enforces same gate")
	var refusing := RefusingOwned.new()
	refusing.name = "RefusingOwned"
	main.add_child(refusing)
	shop.owned_relics_path = NodePath("../RefusingOwned")
	var refund_entry := entry(relic(&"refund_fixture"))
	shop._stock = [refund_entry]
	check(shop.can_grant(refund_entry.good), "pre-charge check permits fixture")
	check(not shop.buy(refund_entry) and wallet.balance() == 17, "post-charge failed grant refunds exactly")
	check(shop._stock.has(refund_entry), "failed grant preserves stock")
	shop.owned_relics_path = NodePath("../missing")
	check(not shop.can_grant(refund_entry.good), "missing explicit provider refuses safely")
	shop.owned_relics_path = NodePath("../OwnedRelics")

	# ACTUAL death -> RunManager -> satchel.try_revive interception.
	var satchel := main.get_node("ReviveSatchel") as ReviveSatchel
	var rm := main.get_node("RunManager") as RunManager
	satchel.collect()
	await process_frame
	await process_frame
	check(rm._watched == player, "production RunManager connected to Player.died")
	player.apply_damage(player.hp)
	check(player.hp > 0 and satchel.carried == 0, "actual death consumed revive and healed")
	check(not rm._restarting and owned.has_id(r.id), "item revive preserves OWNED RELICS in same run")
	# No revive remains: actual RunManager timer reloads current Main scene.
	rm.restart_delay = 0.01
	var pre_death_count := owned.count()
	player.apply_damage(player.hp)
	check(rm._restarting, "unrevived death starts new-run path")
	await create_timer(0.2).timeout
	var next_owned := current_scene.get_node("OwnedRelics") as OwnedRelics
	check(next_owned.count() == pre_death_count and next_owned.has_id(r.id) and next_owned.has_id(fresh.id), "new-run reload KEEPS owned relics across death (#655)")
	print("[131] DONE checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
