class_name AlertBus
extends Node
## #639 (Daniel, WhatsApp 2026-11-12: "lets do signals might be adding audio
## + ui later"): alert bus for enemy pack behavior. One node parked on the
## SceneTree root (the DayNightClock idiom): a red mustache behavior that
## spots the player calls broadcast(); red behaviors subscribe on their
## enemy's behalf and react if within range. Other listeners (audio, UI)
## can subscribe to the same signal without touching the behavior.
##
## Emitted with the spot in world coordinates, a per-run sequence number
## (receivers act once per alert) and the spotting enemy.
signal red_alert(spot: Vector2, seq: int, source: Enemy)

var _seq: int = 0

## One bus per tree, created on first use (DayNightClock.ensure idiom).
static func ensure(tree: SceneTree) -> AlertBus:
	var bus := tree.root.get_node_or_null("AlertBus") as AlertBus
	if bus == null:
		bus = AlertBus.new()
		bus.name = "AlertBus"
		tree.root.add_child(bus)
	return bus

## Broadcast a player spotting at `spot`; returns the alert's sequence.
func broadcast(source: Enemy, spot: Vector2) -> int:
	_seq += 1
	red_alert.emit(spot, _seq, source)
	return _seq
