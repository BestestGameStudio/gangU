extends SceneTree
var failures := 0
func _check(ok: bool, label: String) -> void:
	print("[349 panel] ", label, " -> ", "PASS" if ok else "FAIL")
	if not ok:
		failures += 1
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var panel := FastTravelPanel.new()
	root.add_child(panel)
	await process_frame
	_check(not panel._open_button.visible, "fresh run has no useless open button")
	var ids: Array[StringName] = [&"dungeon_a", &"dungeon_c"]
	panel.set_choices(ids, false)
	_check(panel._rows.get_child_count() == 2 and panel._open_button.visible, "hub has only supplied cleared choices")
	panel._toggle()
	_check(panel._backdrop.visible and panel.is_in_group("modal_ui"), "open panel blocks spell clicks")
	var selected: Array[StringName] = []
	panel.destination_requested.connect(func(id: StringName): selected.append(id))
	(panel._rows.get_child(0) as Button).pressed.emit()
	_check(selected == [&"dungeon_a"], "button requests expected destination")
	_check(not panel._backdrop.visible and not panel.is_in_group("modal_ui"), "selection closes and removes modal guard")
	panel.set_choices([], true)
	_check(panel._rows.get_child_count() == 1 and panel._rows.get_child(0).name == "ReturnHub", "return origin offers hub only")
	var returns: Array[bool] = []
	panel.hub_requested.connect(func(): returns.append(true))
	(panel._rows.get_child(0) as Button).pressed.emit()
	_check(returns.size() == 1, "hub request delivered")
	panel.set_choices([], false)
	_check(not panel._open_button.visible and not panel.is_in_group("modal_ui"), "reset removes choices and modal state")
	print("[349 panel] failures=", failures)
	quit(1 if failures else 0)
