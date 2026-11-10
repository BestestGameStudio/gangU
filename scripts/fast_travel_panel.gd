class_name FastTravelPanel
extends ModalPanel
## #349: view only. Main supplies live eligibility and handles requests.
## The panel has no clear record or origin policy of its own.
signal destination_requested(dungeon_id: StringName)
signal hub_requested

var _open_button: Button
var _backdrop: PanelContainer
var _rows: VBoxContainer

func _ready() -> void:
	layer = 4
	_open_button = Button.new()
	_open_button.name = "OpenTravel"
	_open_button.text = "FAST TRAVEL"
	_open_button.position = Vector2(12, 238)
	UiStyle.style_button(_open_button, UiStyle.B_ACCENT, 8)
	_open_button.pressed.connect(_toggle)
	add_child(_open_button)
	_backdrop = PanelContainer.new()
	_backdrop.name = "TravelChoices"
	_backdrop.position = Vector2(356, 172)
	_backdrop.custom_minimum_size = Vector2(440, 280)
	_backdrop.add_theme_stylebox_override("panel", UiStyle.panel())
	add_child(_backdrop)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_backdrop.add_child(box)
	var title := Label.new()
	title.text = "FAST TRAVEL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	box.add_child(_rows)
	var close_button := Button.new()
	close_button.text = "Close"
	UiStyle.style_button(close_button, UiStyle.B_DIM, 8)
	close_button.pressed.connect(close)
	box.add_child(close_button)
	close()
	set_choices([], false)

## Called by Main on area/clear changes. Requests are advisory: Main must
## revalidate at click time. Closing also drops modal cast suppression.
func set_choices(ids: Array[StringName], can_return: bool) -> void:
	for row in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	for id in FastTravelRoutes.destinations(ids):
		var button := Button.new()
		button.name = "Travel_" + str(id)
		button.text = FastTravelRoutes.label_for(id)
		UiStyle.style_button(button, UiStyle.B_ACCENT, 8)
		button.pressed.connect(_request_destination.bind(id))
		_rows.add_child(button)
	if can_return:
		var button := Button.new()
		button.name = "ReturnHub"
		button.text = "Return to Hub"
		UiStyle.style_button(button, UiStyle.B_ACCENT, 8)
		button.pressed.connect(_request_hub)
		_rows.add_child(button)
	_open_button.visible = _rows.get_child_count() > 0
	if not _open_button.visible:
		close()

func close() -> void:
	_set_shown(false)

func _toggle() -> void:
	_set_shown(not _backdrop.visible)

## The open button stays on screen; only the choices backdrop is the panel.
func _apply_shown(shown: bool) -> void:
	_backdrop.visible = shown

func _request_destination(id: StringName) -> void:
	close()
	destination_requested.emit(id)

func _request_hub() -> void:
	close()
	hub_requested.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if _backdrop.visible and event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
