class_name SettingsPanel
extends ModalPanel
## (#489) Settings panel with a master volume slider. Esc opens / closes
## it (#622 removed the on-screen corner button; Esc is the only opener).
##
## - Master volume drives the Master audio bus (bus 0), which every
##   AudioStreamPlayer in the game plays on (music, ambience, SFX). The
##   per-track trims (MusicDirector.BOSS_VOLUME_DB etc.) are untouched; this
##   scales everything on top of them. 0% mutes the bus.
## - The value is saved to user://settings.cfg and re-applied on every
##   _ready, so it survives the per-run scene reload and game restarts.
## - Does NOT pause (MapPanel / EquipPanel idiom). A ModalPanel, so clicks
##   on the slider never cast spells.
## - Esc only opens the panel when no other modal UI (map, equip, fast
##   travel) is open, so Esc still closes those first.

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "audio"
const KEY_MASTER := "master_volume"
const DEFAULT_MASTER := 1.0
const DISPLAY_SECTION := "display"
const KEY_SHOW_FPS := "show_fps"

## Overridable so the test harness never touches the real settings file.
var settings_path := SETTINGS_PATH
var master_volume := DEFAULT_MASTER
## #826: small FPS readout in the top-right corner, off by default.
var show_fps := false

var _fps_layer: CanvasLayer
var _fps_label: Label
var _fps_check: CheckBox
var _fps_accum := 0.0

var _backdrop: PanelContainer
var _slider: HSlider
var _value_label: Label
var _binding_buttons: Dictionary = {}
var _capture_action := ""
var _binding_status: Label

func _ready() -> void:
	layer = 10
	master_volume = load_master_volume(settings_path)
	apply_master_volume(master_volume)
	KeyBindings.load_saved(settings_path)
	show_fps = load_show_fps(settings_path)
	_build_ui()
	_build_fps_label()
	apply_show_fps()
	close()

static func load_show_fps(path: String = SETTINGS_PATH) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return false
	return bool(cfg.get_value(DISPLAY_SECTION, KEY_SHOW_FPS, false))

static func save_show_fps(on: bool, path: String = SETTINGS_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path) # keep any other keys; a missing file is fine
	cfg.set_value(DISPLAY_SECTION, KEY_SHOW_FPS, on)
	cfg.save(path)

func set_show_fps(on: bool) -> void:
	show_fps = on
	save_show_fps(on, settings_path)
	if _fps_check != null and _fps_check.button_pressed != on:
		_fps_check.set_pressed_no_signal(on)
	apply_show_fps()

func apply_show_fps() -> void:
	if _fps_layer != null:
		_fps_layer.visible = show_fps
	set_process(show_fps)
	_fps_accum = 1.0 # refresh the number on the next frame

func _process(delta: float) -> void:
	_fps_accum += delta
	if _fps_accum >= 0.5 and _fps_label != null:
		_fps_accum = 0.0
		_fps_label.text = "FPS %d" % int(Engine.get_frames_per_second())

func _build_fps_label() -> void:
	_fps_layer = CanvasLayer.new()
	_fps_layer.name = "FpsLayer"
	_fps_layer.layer = 99
	add_child(_fps_layer)
	_fps_label = Label.new()
	_fps_label.name = "FpsLabel"
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fps_label.position = Vector2(-12, 44) ## below the area name
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.add_theme_font_size_override("font_size", 18)
	_fps_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_fps_label.add_theme_constant_override("shadow_offset_x", 2)
	_fps_label.add_theme_constant_override("shadow_offset_y", 2)
	_fps_layer.add_child(_fps_label)

## Linear 0..1 -> Master bus. 0 mutes rather than going to -inf dB.
static func apply_master_volume(v: float) -> void:
	var bus := AudioServer.get_bus_index(&"Master")
	if bus < 0:
		bus = 0
	v = clampf(v, 0.0, 1.0)
	AudioServer.set_bus_mute(bus, v <= 0.0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(v, 0.0001)))

static func load_master_volume(path: String = SETTINGS_PATH) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return DEFAULT_MASTER
	# Coerce like the pre-typing float() loader: legacy/hand-edited configs
	# can hold string, int or bool values (see bestiary.gd for why narrowed).
	var raw: Variant = cfg.get_value(SECTION, KEY_MASTER, DEFAULT_MASTER)
	var saved: float
	if raw is float:
		saved = raw
	elif raw is int:
		var i: int = raw
		saved = float(i)
	elif raw is bool:
		var b: bool = raw
		saved = float(b)
	elif raw is String:
		var s: String = raw
		saved = s.to_float()
	elif raw is StringName:
		var sn: StringName = raw
		saved = String(sn).to_float()
	else:
		# float() rejected non-scalar values with a hard script error;
		# keep rejecting instead of silently forcing a wrong volume.
		saved = raw + 0.0
	return clampf(saved, 0.0, 1.0)

static func save_master_volume(v: float, path: String = SETTINGS_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path) # keep any other keys; a missing file is fine
	cfg.set_value(SECTION, KEY_MASTER, clampf(v, 0.0, 1.0))
	cfg.save(path)

func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	apply_master_volume(master_volume)
	save_master_volume(master_volume, settings_path)
	if _slider != null and not is_equal_approx(_slider.value, master_volume * 100.0):
		_slider.set_value_no_signal(master_volume * 100.0)
	_refresh_label()

func _apply_shown(shown: bool) -> void:
	_backdrop.visible = shown

func is_open() -> bool:
	return _backdrop != null and _backdrop.visible

func open() -> void:
	_set_shown(true)

func close() -> void:
	_capture_action = ""
	_refresh_bindings()
	_set_shown(false)

## True when some other panel (map, equip, fast travel) is open.
func _other_modal_open() -> bool:
	for n in get_tree().get_nodes_in_group(GROUP):
		if n != self:
			return true
	return false

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and (event as InputEventKey).pressed and not event.is_echo()):
		return
	if (event as InputEventKey).keycode != KEY_ESCAPE:
		return
	if is_open():
		close()
		get_viewport().set_input_as_handled()
	elif not _other_modal_open():
		open()
		get_viewport().set_input_as_handled()

func _refresh_label() -> void:
	if _value_label != null:
		_value_label.text = "%d%%" % roundi(master_volume * 100.0)

func _build_ui() -> void:
	_backdrop = PanelContainer.new()
	_backdrop.name = "SettingsBackdrop"
	_backdrop.add_theme_stylebox_override("panel", UiStyle.panel())
	_backdrop.set_anchors_preset(Control.PRESET_CENTER)
	_backdrop.custom_minimum_size = Vector2(540, 0)
	_backdrop.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_backdrop.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_backdrop)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_backdrop.add_child(box)
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var name_label := Label.new()
	name_label.text = "Master volume"
	row.add_child(name_label)
	_slider = HSlider.new()
	_slider.name = "MasterVolume"
	_slider.min_value = 0.0
	_slider.max_value = 100.0
	_slider.step = 1.0
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.set_value_no_signal(master_volume * 100.0)
	_slider.value_changed.connect(func(v: float) -> void: set_master_volume(v / 100.0))
	row.add_child(_slider)
	_value_label = Label.new()
	_value_label.name = "MasterValue"
	_value_label.custom_minimum_size = Vector2(44, 0)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_value_label)
	_refresh_label()

	_fps_check = CheckBox.new()
	_fps_check.name = "ShowFps"
	_fps_check.text = "Show FPS counter"
	_fps_check.focus_mode = Control.FOCUS_NONE
	_fps_check.set_pressed_no_signal(show_fps)
	_fps_check.toggled.connect(set_show_fps)
	box.add_child(_fps_check)

	_build_bindings(box)

	var close_button := Button.new()
	close_button.name = "Close"
	close_button.text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	UiStyle.style_button(close_button, UiStyle.B_DIM, 8)
	close_button.pressed.connect(close)
	box.add_child(close_button)
	var hint := Label.new()
	hint.text = "Esc: open / close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UiStyle.TEXT_DIM * Color(1, 1, 1, 0.6))
	hint.add_theme_font_size_override("font_size", 16)
	box.add_child(hint)

func _build_bindings(box: VBoxContainer) -> void:
	var heading := Label.new()
	heading.text = "Controls - click a binding to change"
	heading.add_theme_font_size_override("font_size", 22)
	box.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 280
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for action: String in KeyBindings.ACTIONS:
		var row := HBoxContainer.new()
		rows.add_child(row)
		var label := Label.new()
		label.text = KeyBindings.ACTIONS[action]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 18)
		row.add_child(label)
		var button := Button.new()
		button.name = "Bind_" + action
		button.custom_minimum_size.x = 120
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: begin_rebind(action))
		row.add_child(button)
		_binding_buttons[action] = button
	_binding_status = Label.new()
	_binding_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_binding_status.custom_minimum_size = Vector2(500, 36)
	_binding_status.add_theme_font_size_override("font_size", 16)
	_binding_status.text = "Esc cancels capture. Conflicting controls are not replaced."
	box.add_child(_binding_status)
	var reset := Button.new()
	reset.name = "ResetBindings"
	reset.text = "Reset controls to defaults"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(reset_bindings)
	box.add_child(reset)
	_refresh_bindings()

func _refresh_bindings() -> void:
	for action: String in _binding_buttons:
		_binding_buttons[action].text = "Press input..." if action == _capture_action else KeyBindings.action_label(action)

func begin_rebind(action: String) -> void:
	_capture_action = action
	_binding_status.text = "Press a key or mouse button for %s. Esc cancels." % KeyBindings.ACTIONS[action]
	_refresh_bindings()

func reset_bindings() -> void:
	_capture_action = ""
	var error := KeyBindings.reset(settings_path)
	_binding_status.text = "Default controls restored." if error == OK else "Controls reset, but could not save preferences."
	_refresh_bindings()

func _input(event: InputEvent) -> void:
	if not is_open() or _capture_action.is_empty(): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_capture_action = ""
		_binding_status.text = "Binding change cancelled."
		_refresh_bindings()
		get_viewport().set_input_as_handled()
		return
	if not ((event is InputEventKey or event is InputEventMouseButton) and event.is_pressed() and not event.is_echo()): return
	get_viewport().set_input_as_handled()
	var candidate := KeyBindings.normalized(event)
	if candidate == null:
		_binding_status.text = "Use a keyboard key or mouse button, not the wheel. Esc cancels."
		return
	var used_by := KeyBindings.conflict(_capture_action, candidate)
	if not used_by.is_empty():
		_binding_status.text = "%s is already used by %s. Choose another input or Esc." % [KeyBindings.label(candidate), used_by]
		return
	KeyBindings.assign(_capture_action, candidate)
	var error := KeyBindings.save(settings_path)
	_binding_status.text = "Binding saved." if error == OK else "Binding changed, but could not save preferences."
	_capture_action = ""
	_refresh_bindings()
