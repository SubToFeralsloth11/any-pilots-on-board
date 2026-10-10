extends CenterContainer
## Full-screen centred settings panel shared by the title menu and the pause menu. Edits the Settings autoload
## (which applies and saves each change) and emits `closed` when the player presses Back.
## Call open() to show it with fresh values.

signal closed

const NAVY := Color(0.07, 0.11, 0.26, 0.96)
const GOLD := Color(1, 0.84, 0.2)
const ON_COLOR := Color(0.3, 0.8, 0.4)
const OFF_COLOR := Color(0.32, 0.36, 0.5)
const LABEL_W := 230.0

var _sliders := {}     ## setting key -> [HSlider, value Label, formatter Callable]
var _toggles := {}     ## setting key -> Button
var _quality: Array[Button] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(NAVY, 26, 26.0, GOLD))
	add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 560
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := _label("SETTINGS", 42)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_constant_override("outline_size", 14)
	box.add_child(title)
	_slider_row(box, "Mouse sensitivity", "mouse_sensitivity", 0.2, 3.0, 0.05, func(v: float) -> String: return "%.2fx" % v)
	_toggle_row(box, "Invert mouse Y", "invert_y")
	_slider_row(box, "Field of view", "fov", 60.0, 110.0, 1.0, func(v: float) -> String: return "%d°" % roundi(v))
	_slider_row(box, "Master volume", "master_volume", 0.0, 1.0, 0.01, func(v: float) -> String: return "%d%%" % roundi(v * 100))
	_quality_row(box)
	_toggle_row(box, "Fullscreen", "fullscreen")
	_toggle_row(box, "Show FPS counter", "show_fps")
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(240, 52)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	box.add_child(back)


## Shows the panel with the current saved values.
func open() -> void:
	for key: String in _sliders:
		var v := float(Settings.get(key))
		(_sliders[key][0] as HSlider).set_value_no_signal(v)
		(_sliders[key][1] as Label).text = (_sliders[key][2] as Callable).call(v)
	for key: String in _toggles:
		_set_toggle(_toggles[key], bool(Settings.get(key)))
	for i in _quality.size():
		_quality[i].set_pressed_no_signal(i == Settings.quality)
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func _row(parent: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := _label(text, 20)
	l.custom_minimum_size.x = LABEL_W
	row.add_child(l)
	parent.add_child(row)
	return row


func _slider_row(parent: Control, text: String, key: String, lo: float, hi: float, step: float, fmt: Callable) -> void:
	var row := _row(parent, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size.y = 32
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.add_theme_stylebox_override("slider", _track(Color(0.18, 0.22, 0.38)))
	s.add_theme_stylebox_override("grabber_area", _track(GOLD))
	s.add_theme_stylebox_override("grabber_area_highlight", _track(Color(1, 0.9, 0.45)))
	row.add_child(s)
	var val := _label("", 20)
	val.custom_minimum_size.x = 70
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	s.value_changed.connect(func(v: float) -> void: val.text = fmt.call(v))
	# Save once when a drag ends; clicks on the track and arrow keys save immediately.
	s.drag_started.connect(func() -> void: s.set_meta("dragging", true))
	s.drag_ended.connect(func(_changed: bool) -> void:
		s.set_meta("dragging", false)
		Settings.set_value(key, s.value))
	s.value_changed.connect(func(v: float) -> void:
		if not s.get_meta("dragging", false):
			Settings.set_value(key, v))
	_sliders[key] = [s, val, fmt]


func _toggle_row(parent: Control, text: String, key: String) -> void:
	var row := _row(parent, text)
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(110, 42)
	b.toggled.connect(func(on: bool) -> void:
		_set_toggle(b, on)
		Settings.set_value(key, on))
	row.add_child(b)
	_toggles[key] = b


func _set_toggle(b: Button, on: bool) -> void:
	b.set_pressed_no_signal(on)
	b.text = "ON" if on else "OFF"
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, _box(ON_COLOR if on else OFF_COLOR, 14, 10.0))


func _quality_row(parent: Control) -> void:
	var row := _row(parent, "Graphics quality")
	var group := ButtonGroup.new()
	for i in Settings.QUALITY_NAMES.size():
		var b := Button.new()
		b.text = Settings.QUALITY_NAMES[i]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(98, 42)
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_stylebox_override("normal", _box(OFF_COLOR, 14, 10.0))
		b.add_theme_stylebox_override("pressed", _box(GOLD.darkened(0.15), 14, 10.0))
		b.add_theme_stylebox_override("hover_pressed", _box(GOLD.darkened(0.05), 14, 10.0))
		b.pressed.connect(func() -> void: Settings.set_value("quality", i))
		row.add_child(b)
		_quality.append(b)


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.1))
	l.add_theme_constant_override("outline_size", 6)
	return l


func _track(color: Color) -> StyleBoxFlat:
	var s := _box(color, 8, 0.0)
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func _box(color: Color, radius: int, pad: float, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(4)
		s.shadow_color = Color(0, 0, 0, 0.35)
		s.shadow_size = 10
		s.shadow_offset = Vector2(0, 6)
	return s
