class_name RelicIcon
extends Control
## #449: fixed-size icon for a relic in the UI (shop first; the tab menu
## follows when #431 lands). Daniel's call (2026-11-09): ONE shared
## placeholder for every relic, drawn in code, no art files - the same
## amber diamond for all of them, told apart by the hover tooltip, which
## carries the relic's name and description ("icon only, name and desc on
## hover"). Real art can replace the placeholder later.

const PLACEHOLDER_FILL := Color(0.85, 0.62, 0.20) # amber, same for every relic
const PLACEHOLDER_EDGE := Color(0.45, 0.30, 0.08)

var _relic: Relic

func _init(side: float = UiStyle.ICON_SIZE) -> void:
	name = "RelicIcon"
	custom_minimum_size = Vector2(side, side)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Hover must reach this control so the tooltip can show.
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = "Relic"

func show_relic(relic: Relic) -> void:
	_relic = relic
	if relic == null:
		tooltip_text = "Relic"
		return
	tooltip_text = relic.display_name
	if relic.description != "":
		tooltip_text += "\n" + relic.description

func _draw() -> void:
	var c := size * 0.5
	var r := size.x * 0.34
	var diamond := PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0),
	])
	draw_colored_polygon(diamond, PLACEHOLDER_FILL)
	draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), PLACEHOLDER_EDGE, 2.0, true)
