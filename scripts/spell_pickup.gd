class_name SpellPickup
extends Area2D
## #10: spell pickup item. Walk-over grants the spell to the player's
## SpellCaster in the SAME run; the shared Player survives area swaps, so
## collected spells persist hub<->dungeon for free and reset on the
## RunManager's full-scene reload.

signal picked_up(pickup: SpellPickup, spell: Spell)

## The spell resource this pickup grants. The caster stores the resource
## reference; SpellCaster owns per-spell cooldowns keyed by Spell.
@export var spell: Spell
@export var spell_path: String = ""

func _ready() -> void:
	add_to_group("spell_pickups")
	if spell == null and spell_path != "":
		spell = load(spell_path)
	if spell == null:
		push_warning("SpellPickup: no spell assigned.")
		return
	$NameLabel.text = spell.spell_name
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if not (body is Player):
		return
	var caster := body.get_node_or_null("SpellCaster") as SpellCaster
	if caster == null or spell == null:
		return
	if caster.spells.has(spell):
		# PROVISIONAL HARNESS DEFAULT (reversible, not settled production
		# behavior): duplicate pickups are ignored. Final duplicate/content
		# behavior is an open human choice.
		return
	caster.add_spell(spell)
	print("spell picked up: ", spell.spell_name)
	picked_up.emit(self, spell)
	# PROVISIONAL HARNESS DEFAULT (reversible, not settled production
	# behavior): consume on grant so the harness room state reads clearly.
	# Final consume/respawn behavior is an open human choice.
	set_deferred("monitoring", false)
	visible = false
