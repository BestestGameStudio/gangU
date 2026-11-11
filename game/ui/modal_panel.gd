class_name ModalPanel
extends CanvasLayer
## Base for the code-built UI panels. SpellCaster skips casting while any
## node is in the "modal_ui" group, so a panel is in that group exactly
## while it is shown: subclasses show and hide only through _set_shown.

const GROUP := &"modal_ui"

func _set_shown(shown: bool) -> void:
	_apply_shown(shown)
	if shown:
		add_to_group(GROUP)
	else:
		remove_from_group(GROUP)

## What "shown" means on screen: the whole layer unless overridden.
func _apply_shown(shown: bool) -> void:
	visible = shown
