class_name UiTheme
extends RefCounted
## Terracotta palette from the original page, as a Godot Theme.

const BG := Color("#f9f3eb")
const SURFACE := Color("#f3e9dc")
const INK := Color("#261b15")
const INK_SOFT := Color("#57483f")
const OUTLINE := Color("#dfd0be")
const PRIMARY := Color("#b84a24")
const PRIMARY_HOVER := Color("#9d3c1b")
const TERTIARY := Color("#1d6356")
const BRASS := Color("#b5893e")


static func box(bg: Color, border: Color, radius := 10, border_w := 1, pad := 12.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	var hud_bg := Color(BG.r, BG.g, BG.b, 0.9)
	t.set_stylebox("panel", "PanelContainer", box(hud_bg, OUTLINE, 12, 1, 14.0))
	t.set_color("font_color", "Label", INK)

	t.set_stylebox("normal", "Button", box(PRIMARY, PRIMARY, 22, 1, 16.0))
	t.set_stylebox("hover", "Button", box(PRIMARY_HOVER, PRIMARY_HOVER, 22, 1, 16.0))
	t.set_stylebox("pressed", "Button", box(PRIMARY_HOVER, INK, 22, 1, 16.0))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), INK, 22, 2, 16.0))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", Color.WHITE)

	t.set_stylebox("normal", "LineEdit", box(Color("#fcf8f2"), Color("#9e8a78"), 6, 1, 10.0))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0), PRIMARY, 6, 2, 10.0))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("caret_color", "LineEdit", PRIMARY)

	t.set_stylebox("normal", "OptionButton", box(Color("#fcf8f2"), Color("#9e8a78"), 6, 1, 10.0))
	t.set_stylebox("hover", "OptionButton", box(Color("#ede0d0"), Color("#9e8a78"), 6, 1, 10.0))
	t.set_stylebox("pressed", "OptionButton", box(Color("#ede0d0"), PRIMARY, 6, 1, 10.0))
	t.set_stylebox("focus", "OptionButton", box(Color(0, 0, 0, 0), PRIMARY, 6, 2, 10.0))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "OptionButton", INK)
	t.set_stylebox("panel", "PopupMenu", box(BG, OUTLINE, 6, 1, 6.0))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("hover", "PopupMenu", box(PRIMARY, PRIMARY, 4, 0, 6.0))
	return t


static func kicker(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", PRIMARY)
	l.add_theme_font_size_override("font_size", 12)
	return l
