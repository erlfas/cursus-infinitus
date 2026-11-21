class_name Hud
extends CanvasLayer
## Small in-game HUD: distance run, the module under the runner, seed.
## F3 toggles a debug readout of the streaming WFC solver.

const PASSUS_M := 1.48   # one Roman passus (double step)

var citizen: Citizen
var streamer: ChunkStreamer

var _distance: Label
var _miles: Label
var _place: Label
var _family: Label
var _seed: Label
var _debug: Label
var _debug_panel: PanelContainer


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.make()
	add_child(root)

	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	panel.add_child(vb)
	vb.add_child(UiTheme.kicker("FORMA URBIS · CURSUS INFINITUS"))
	_distance = Label.new()
	_distance.add_theme_font_size_override("font_size", 26)
	vb.add_child(_distance)
	_miles = Label.new()
	_miles.add_theme_color_override("font_color", UiTheme.TERTIARY)
	_miles.add_theme_font_size_override("font_size", 13)
	vb.add_child(_miles)
	var sep := HSeparator.new()
	vb.add_child(sep)
	_place = Label.new()
	_place.add_theme_font_size_override("font_size", 17)
	vb.add_child(_place)
	_family = Label.new()
	_family.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	_family.add_theme_font_size_override("font_size", 12)
	vb.add_child(_family)
	_seed = Label.new()
	_seed.add_theme_color_override("font_color", UiTheme.BRASS)
	_seed.add_theme_font_size_override("font_size", 12)
	vb.add_child(_seed)

	var hint := PanelContainer.new()
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 18
	hint.offset_bottom = -18
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(hint)
	var hl := Label.new()
	hl.text = "WASD run · Shift sprint · Space jump · Mouse look · Wheel zoom · Esc menu · F3 debug"
	hl.add_theme_font_size_override("font_size", 12)
	hl.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	hint.add_child(hl)

	_debug_panel = PanelContainer.new()
	_debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_panel.anchor_left = 1.0
	_debug_panel.anchor_right = 1.0
	_debug_panel.offset_right = -18
	_debug_panel.offset_top = 18
	_debug_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_debug_panel.visible = false
	root.add_child(_debug_panel)
	_debug = Label.new()
	_debug.add_theme_font_size_override("font_size", 12)
	_debug_panel.add_child(_debug)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_F3:
		_debug_panel.visible = not _debug_panel.visible


static func to_roman(n: int) -> String:
	if n <= 0:
		return "—"
	var vals := [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
	var syms := ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
	var out := ""
	for i in vals.size():
		while n >= vals[i]:
			out += syms[i]
			n -= vals[i]
	return out


func _process(_dt: float) -> void:
	if citizen == null or streamer == null or streamer.world == null:
		return
	var m := citizen.distance_m
	var passus := int(m / PASSUS_M)
	_distance.text = "%s passus" % _group(passus)
	_miles.text = "%.2f km  ·  Mille passuum: %s" % [m / 1000.0, to_roman(passus / 1000)]

	var cell := WfcWorld.cell_at(citizen.global_position)
	var v := streamer.world.variant_at(cell)
	if v >= 0:
		_place.text = WfcData.v_name[v]
		var fam := WfcData.v_family[v]
		_family.text = "%s  ·  cell (%d, %d)" % [WfcData.FAMILY_LABELS[fam], cell.x, cell.y]
	else:
		_place.text = "Superpositio…"
		_family.text = "uncollapsed  ·  cell (%d, %d)" % [cell.x, cell.y]
	_seed.text = "#" + streamer.world.seed_text.to_upper()

	if _debug_panel.visible:
		var w := streamer.world
		_debug.text = "FPS %d\nchunks solved %d · loaded %d\npending solves %d · last solve %.1f ms\nretry attempts %d · relaxed edges %d" % [
			Engine.get_frames_per_second(), w.chunks.size(), streamer.views.size(),
			streamer.pending_solves, streamer.last_solve_ms, w.total_attempts - w.chunks.size(), w.total_fallback_edges]


static func _group(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = " " + out
	return out
