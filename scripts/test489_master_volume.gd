extends SceneTree
## #489 headless driver: Settings panel master volume.
##   unit  - the slider value drives the Master bus (linear -> dB, 0% mutes),
##           is saved to the settings file and re-applied by a fresh panel.
##   input - Esc opens/closes the panel; Esc is left alone while another
##           modal_ui panel is open; the open panel joins modal_ui.
##   main  - main.tscn mounts a SettingsPanel.
## CI has no audio device: these check bus state, not loudness.
## Run: godot --headless --path . --script scripts/test489_master_volume.gd

const TEST_PATH := "user://test489_settings.cfg"
var _fails := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	print("[489] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _esc() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.physical_keycode = KEY_ESCAPE
	e.pressed = true
	return e

func _panel() -> SettingsPanel:
	var p := SettingsPanel.new()
	p.settings_path = TEST_PATH
	root.add_child(p)
	return p

func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	var bus := AudioServer.get_bus_index(&"Master")

	# --- unit ---
	var p := _panel()
	await _frames(1)
	_check("unit: no file -> default 100%", is_equal_approx(p.master_volume, 1.0))
	_check("unit: default leaves Master at 0 dB, unmuted",
		is_equal_approx(AudioServer.get_bus_volume_db(bus), 0.0) and not AudioServer.is_bus_mute(bus))
	var slider := p.find_child("MasterVolume", true, false) as HSlider
	_check("unit: slider exists, 0..100", slider != null and slider.min_value == 0.0 and slider.max_value == 100.0)
	slider.value = 50.0
	_check("unit: slider 50 -> master_volume 0.5", is_equal_approx(p.master_volume, 0.5))
	_check("unit: Master bus ~ -6 dB", absf(AudioServer.get_bus_volume_db(bus) - linear_to_db(0.5)) < 0.01)
	_check("unit: label shows 50%", (p.find_child("MasterValue", true, false) as Label).text == "50%")
	_check("unit: saved to file", is_equal_approx(SettingsPanel.load_master_volume(TEST_PATH), 0.5))
	slider.value = 0.0
	_check("unit: 0% mutes the Master bus", AudioServer.is_bus_mute(bus))
	slider.value = 25.0
	_check("unit: raising again unmutes", not AudioServer.is_bus_mute(bus))
	p.queue_free()
	await _frames(1)
	# Simulate a restart: reset the bus, a fresh panel must restore 25%.
	AudioServer.set_bus_volume_db(bus, 0.0)
	var p2 := _panel()
	await _frames(1)
	_check("unit: fresh panel reloads 25%", is_equal_approx(p2.master_volume, 0.25))
	_check("unit: fresh panel re-applies it to the bus",
		absf(AudioServer.get_bus_volume_db(bus) - linear_to_db(0.25)) < 0.01)
	_check("unit: slider shows the saved value", is_equal_approx((p2.find_child("MasterVolume", true, false) as HSlider).value, 25.0))
	_check("unit: out-of-range is clamped", (func() -> bool:
		p2.set_master_volume(3.0); return is_equal_approx(p2.master_volume, 1.0)).call())

	# --- input ---
	_check("input: starts closed", not p2.is_open())
	p2._unhandled_key_input(_esc())
	_check("input: Esc opens", p2.is_open() and p2.is_in_group("modal_ui"))
	p2._unhandled_key_input(_esc())
	_check("input: Esc closes", not p2.is_open() and not p2.is_in_group("modal_ui"))
	var other := Node.new()
	root.add_child(other)
	other.add_to_group("modal_ui")
	p2._unhandled_key_input(_esc())
	_check("input: Esc ignored while another modal panel is open", not p2.is_open())
	other.queue_free()
	await _frames(1)
	(p2.find_child("OpenSettings", true, false) as Button).pressed.emit()
	_check("input: Settings button opens", p2.is_open())
	(p2.find_child("Close", true, false) as Button).pressed.emit()
	_check("input: Close button closes", not p2.is_open())
	p2.queue_free()
	await _frames(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	AudioServer.set_bus_volume_db(bus, 0.0)
	AudioServer.set_bus_mute(bus, false)

	# --- main ---
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	var sp := main.get_node_or_null("SettingsPanel") as SettingsPanel
	_check("main: SettingsPanel mounted, closed", sp != null and not sp.is_open())

	print("RESULT: ", "ALL PASS" if _fails == 0 else "%d FAIL" % _fails)
	quit(0 if _fails == 0 else 1)
