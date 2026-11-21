class_name PauseMenu
extends CanvasLayer
## Esc menu: resume, daylight preset, seed / new city, quit.

signal lighting_changed(preset: String)
signal seed_changed(seed_text: String)

const SEED_PREFIXES := ["ROMA", "OSTIA", "POMPEII", "TIVOLI", "LUGDUNUM", "ARLES", "NARBO", "TARRACO"]

var _panel: Control
var _light: OptionButton
var _seed: LineEdit


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS

	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.theme = UiTheme.make()
	_panel.visible = false
	add_child(_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.15, 0.1, 0.08, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	center.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	card.add_child(vb)

	vb.add_child(UiTheme.kicker("WAVE FUNCTION COLLAPSE · ENDLESS CITY"))
	var title := Label.new()
	title.text = "Forma Urbis"
	title.add_theme_font_size_override("font_size", 34)
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "Run through an infinite Roman city that collapses into being around you."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	sub.add_theme_font_size_override("font_size", 13)
	vb.add_child(sub)

	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(close)
	vb.add_child(resume)

	vb.add_child(_label("DAYLIGHT"))
	_light = OptionButton.new()
	for key: String in Lighting.ORDER:
		_light.add_item(Lighting.PRESETS[key]["label"])
	_light.item_selected.connect(func(i: int) -> void: lighting_changed.emit(Lighting.ORDER[i]))
	vb.add_child(_light)

	vb.add_child(_label("CITY SEED"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	_seed = LineEdit.new()
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed.max_length = 24
	_seed.text_submitted.connect(func(t: String) -> void: _apply_seed(t))
	row.add_child(_seed)
	var build := Button.new()
	build.text = "Found City"
	build.pressed.connect(func() -> void: _apply_seed(_seed.text))
	row.add_child(build)
	var rnd := Button.new()
	rnd.text = "New Random Seed"
	rnd.pressed.connect(_random_seed)
	vb.add_child(rnd)

	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func() -> void: get_tree().quit())
	vb.add_child(quit)


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	return l


func sync(preset: String, seed_text: String) -> void:
	_light.select(maxi(0, Lighting.ORDER.find(preset)))
	_seed.text = seed_text


func is_open() -> bool:
	return _panel.visible


func open() -> void:
	_panel.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_panel.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		if is_open():
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func _apply_seed(t: String) -> void:
	t = t.strip_edges().substr(0, 24)
	if t.is_empty():
		t = "ROMA-753"
	_seed.text = t
	seed_changed.emit(t)
	close()


func _random_seed() -> void:
	var t := "%s-%d" % [SEED_PREFIXES[randi() % SEED_PREFIXES.size()], randi_range(100, 999)]
	_apply_seed(t)
