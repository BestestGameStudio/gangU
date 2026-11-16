extends SceneTree
## #719: project UI font, crisp import, and dynamically created controls.
func _initialize() -> void:
 run.call_deferred()
func run() -> void:
 var failures := 0
 var font: FontFile = load("res://assets/fonts/m5x7/m5x7.ttf")
 var theme: Theme = load("res://game/ui/default_theme.tres")
 var label := Label.new()
 root.add_child(label)
 var conditions := [
  font.get_font_name() == "m5x7",
  theme.default_font == font and theme.default_font_size == 16,
  label.get_theme_font("font") == font,
  ThemeDB.fallback_font == font,
  font.antialiasing == TextServer.FONT_ANTIALIASING_NONE,
  font.hinting == TextServer.HINTING_NONE,
  font.subpixel_positioning == TextServer.SUBPIXEL_POSITIONING_DISABLED,
  is_equal_approx(font.oversampling, 1.0),
  not font.generate_mipmaps and not font.multichannel_signed_distance_field,
 ]
 for i in conditions.size():
  print("[719] check ",i,": ",conditions[i])
  if not conditions[i]:failures += 1
 label.free()
 print("[719] ",conditions.size()," checks, ",failures," failures")
 quit(1 if failures else 0)
