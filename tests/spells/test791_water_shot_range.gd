extends SceneTree
var failures := 0
func _initialize() -> void:
 var camera := load("res://game/core/main.tscn").instantiate().get_node("FollowCamera") as Camera2D
 # Current game's default 1152px viewport at zoom1. Fixed stat, not auto-resizing.
 for name in ["water_shot", "water_shot_hover", "water_shot_reservoir", "water_shot_tide"]:
  var spell := load("res://data/spells/" + name + ".tres") as Spell
  var ok := spell.range == 1280.0 and spell.range > 1152.0 / camera.zoom.x and spell.projectile_speed == 750.0
  print("[791] ", name, " range1280 exceeds default screen; speed unchanged: ", ok)
  if not ok: failures += 1
 var main := camera.get_parent()
 main.free()
 quit(1 if failures else 0)
