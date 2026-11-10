class_name SettingsPanel
extends CanvasLayer
## (#489) Settings panel with a master volume slider. Esc (or the small
## "Settings" button in the bottom-right corner) opens / closes it.
##
## - Master volume drives the Master audio bus (bus 0), which every
##   AudioStreamPlayer in the game plays on (music, ambience, SFX). The
##   per-track trims (BossMusic.MUSIC_VOLUME_DB etc.) are untouched; this
##   scales everything on top of them. 0% mutes the bus.
## - The value is saved to user://settings.cfg and re-applied on every
##   _ready, so it survives the per-run scene reload and game restarts.
## - Does NOT pause (MapPanel / EquipPanel idiom). While open it joins
##   "modal_ui" so clicks on the slider never cast spells.
## - Esc only opens the panel when no other modal UI (map, equip, fast
##   travel) is open, so Esc still closes those first.

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "audio"
const KEY_MASTER := "master_volume"
const DEFAULT_MASTER := 1.0

## Overridable so the test harness never touches the real settings file.
var settings_path := SETTINGS_PATH
var master_volume := DEFAULT_MASTER

var _open_button: Button
var _backdrop: PanelContainer
var _slider: HSlider
var _value_label: Label

func _ready() -> void:
	layer = 10
	master_volume = load_master_volume(settings_path)
	apply_master_volume(master_volume)
	_build_ui()
	close()

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

func is_open() -> bool:
	return _backdrop != null and _backdrop.visible

func open() -> void:
	_backdrop.visible = true
	add_to_group("modal_ui")

func close() -> void:
	_backdrop.visible = false
	remove_from_group("modal_ui")

func toggle() -> void:
	if is_open():
		close()
	else:
		open()

## True when some other panel (map, equip, fast travel) is open.
func _other_modal_open() -> bool:
	for n in get_tree().get_nodes_in_group("modal_ui"):
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
	var corner := Control.new()
	corner.name = "Corner"
	# Bottom-right: the top-right corner holds the HUD's area name.
	corner.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(corner)
	_open_button = Button.new()
	_open_button.name = "OpenSettings"
	_open_button.text = "Settings"
	_open_button.tooltip_text = "Settings (Esc)"
	_open_button.focus_mode = Control.FOCUS_NONE
	_open_button.add_theme_font_size_override("font_size", 12)
	UiStyle.style_button(_open_button, UiStyle.B_DIM, 4.0)
	_open_button.pressed.connect(toggle)
	corner.add_child(_open_button)
	# Pin the button 10 px inside the bottom-right screen corner.
	_open_button.position = -_open_button.get_combined_minimum_size() - Vector2(10.0, 10.0)

	_backdrop = PanelContainer.new()
	_backdrop.name = "SettingsBackdrop"
	_backdrop.add_theme_stylebox_override("panel", UiStyle.panel())
	_backdrop.set_anchors_preset(Control.PRESET_CENTER)
	_backdrop.custom_minimum_size = Vector2(380, 0)
	_backdrop.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_backdrop.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_backdrop)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_backdrop.add_child(box)
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
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
	hint.add_theme_font_size_override("font_size", 12)
	box.add_child(hint)
