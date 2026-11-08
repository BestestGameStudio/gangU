class_name UiStyle
extends RefCounted
## Shared look for every screen-space panel (equip panel, shop
## panel): one palette and the StyleBoxFlat builders that use it. Code-drawn
## only, so it renders the same under the compatibility renderer on the web.

const PANEL_BG := Color(0.05, 0.05, 0.07, 0.92)
const PANEL_BORDER := Color(0.55, 0.6, 0.72, 0.85)
const SHADOW := Color(0.0, 0.0, 0.0, 0.45)

const ROW_BG := Color(0.08, 0.08, 0.1, 0.9)
const ROW_BG_HOVER := Color(0.12, 0.13, 0.17, 0.95)
const ROW_BG_HIGHLIGHT := Color(0.14, 0.16, 0.22, 0.95)
const ROW_BG_DISABLED := Color(0.06, 0.06, 0.08, 0.6)

const B_DIM := Color(0.45, 0.48, 0.55, 0.6)
const B_ASSIGNED := Color(0.75, 0.8, 0.9, 0.8)
const B_SELECTED := Color(0.85, 0.9, 1.0, 0.9)
const B_ACCENT := Color(0.95, 0.75, 0.25, 0.9)
const TEXT_DIM := Color(0.7, 0.72, 0.78, 1.0)

const PANEL_BORDER_WIDTH := 2
const PANEL_RADIUS := 8
const PANEL_PAD := 10.0
const SHADOW_SIZE := 6
const SHADOW_OFFSET := Vector2(0.0, 2.0)
const ROW_BORDER_WIDTH := 1
const ROW_BORDER_WIDTH_HIGHLIGHT := 2
const ROW_RADIUS := 4
const BAR_RADIUS := 3
const ICON_SIZE := 22.0
const ICON_PLACEHOLDER_BG := Color(1.0, 1.0, 1.0, 0.04)
const COOLDOWN_WIPE := Color(0.18, 0.2, 0.26, 1.0)

## Outer plate of a panel: thick border, rounded corners, soft drop shadow.
static func panel(bg: Color = PANEL_BG) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(PANEL_BORDER_WIDTH)
	sb.set_corner_radius_all(PANEL_RADIUS)
	sb.shadow_color = SHADOW
	sb.shadow_size = SHADOW_SIZE
	sb.shadow_offset = SHADOW_OFFSET
	sb.set_content_margin_all(PANEL_PAD)
	return sb

## A row or slot box inside a panel. The border color carries the row's
## state; highlighted rows get a thicker border and a lighter fill. Content
## margins are fixed, so switching state never moves the row's content.
static func row(border: Color, pad: float = 4.0, left_pad: float = -1.0, highlighted: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = ROW_BG_HIGHLIGHT if highlighted else ROW_BG
	sb.border_color = border
	sb.set_border_width_all(ROW_BORDER_WIDTH_HIGHLIGHT if highlighted else ROW_BORDER_WIDTH)
	sb.set_corner_radius_all(ROW_RADIUS)
	sb.set_content_margin_all(pad)
	if left_pad >= 0.0:
		sb.content_margin_left = left_pad
	return sb

## Styles every button state from one border color: hover lightens the
## fill, pressed reads as highlighted, focus is a bright outline for keyboard
## users, disabled fades.
static func style_button(b: Button, border: Color, pad: float = 4.0, left_pad: float = -1.0, highlighted: bool = false) -> void:
	var normal := row(border, pad, left_pad, highlighted)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = ROW_BG_HOVER if not highlighted else ROW_BG_HIGHLIGHT
	var pressed := row(border, pad, left_pad, true)
	var disabled := row(Color(border, border.a * 0.5), pad, left_pad)
	disabled.bg_color = ROW_BG_DISABLED
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	var focus := row(B_SELECTED, pad, left_pad)
	focus.draw_center = false
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("disabled", disabled)

## Empty icon slot: a faint outlined box that reads as "no art yet".
static func icon_placeholder() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = ICON_PLACEHOLDER_BG
	sb.border_color = B_DIM
	sb.set_border_width_all(ROW_BORDER_WIDTH)
	sb.set_corner_radius_all(BAR_RADIUS)
	return sb

