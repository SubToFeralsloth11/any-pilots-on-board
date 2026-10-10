extends CanvasLayer
## HUD: crosshair and aim prompt, subtitles, toasts, objective, flight strip, the pilot panel,
## a controls cheat-sheet, the pause menu, the results screen, crash flash and the ambience.

const PilotPanel := preload("res://scripts/ui/pilot_panel.gd")
const Ambience := preload("res://scripts/ui/ambience.gd")

const CHEAT_TIME := 10.0
const TOAST_TIME := 3.5
const MAX_TOASTS := 5
const MS_TO_KT := 1.94384
const M_TO_FT := 3.28084
const SPEAKER_COLORS := ["#ffd23f", "#7fd6ff", "#ff8fa3", "#9dff8a", "#ffb35c", "#d2a8ff"]
const STAT_LABELS := [
	["windows_broken", "Windows broken"], ["items_lost", "Things lost overboard"],
	["things_broken", "Things broken"], ["passengers_lost", "Passengers lost"],
	["players_fell", "Players who fell out"], ["fires_put_out", "Fires put out"],
]
const CHEATS := "[b]HOW TO (NOT) FLY[/b]\n" \
	+ "WASD move · Space jump · Shift sprint\n" \
	+ "Ctrl/C crouch & brace · Y shout\n" \
	+ "E interact / pick up / drop\n" \
	+ "LMB throw or punch · RMB use item\n" \
	+ "Esc pause\n" \
	+ "[color=#ffd23f]Pilot seat:[/color] W nose down · S nose up\n" \
	+ "A/D bank · Shift/Ctrl throttle · F flaps · G gear"

var world: World

var _root: Control
var _crosshair: Control
var _prompt: Label
var _subtitle_box: PanelContainer
var _subtitle: RichTextLabel
var _sub_queue: Array[Array] = []
var _sub_time := 0.0
var _objective_box: PanelContainer
var _objective: Label
var _toasts: VBoxContainer
var _strip: RichTextLabel
var _pilot: Control
var _cheats: PanelContainer
var _pause: Control
var _results: Control
var _results_text: RichTextLabel
var _results_title: Label
var _flash: ColorRect
var _ambience: Node
var _time := 0.0


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)
	_build_crosshair()
	_build_subtitles()
	_build_top_left()
	_build_strip()
	_pilot = PilotPanel.new()
	_pilot.set("world", world)
	_pilot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_pilot, Vector2(0.5, 1), Rect2(-500, -232, 1000, 222))
	_pilot.visible = false
	_root.add_child(_pilot)
	_build_cheats()
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 0.6, 0.2, 0)
	_root.add_child(_flash)
	_build_pause()
	_build_results()
	_ambience = Ambience.new()
	_ambience.set("world", world)
	add_child(_ambience)
	world.subtitle.connect(_on_subtitle)
	world.toast.connect(_on_toast)
	world.round_ended.connect(_on_round_ended)


## True while the pause menu or results screen should swallow gameplay input.
func blocking_input() -> bool:
	return _pause.visible or _results.visible


# --- Building ------------------------------------------------------------------------------

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	var outline := Color(0.02, 0.03, 0.1, 0.9)
	t.set_constant("outline_size", "Label", 7)
	t.set_color("font_outline_color", "Label", outline)
	t.set_constant("outline_size", "RichTextLabel", 7)
	t.set_color("font_outline_color", "RichTextLabel", outline)
	t.set_font_size("normal_font_size", "RichTextLabel", 18)
	t.set_font_size("bold_font_size", "RichTextLabel", 20)
	t.set_stylebox("panel", "PanelContainer", _box(Color(0.05, 0.08, 0.18, 0.7), 10))
	for state in ["normal", "hover", "pressed", "focus"]:
		var col := Color(0.2, 0.45, 0.95)
		if state == "hover":
			col = Color(0.3, 0.58, 1.0)
		elif state == "pressed":
			col = Color(0.95, 0.6, 0.15)
		var sb := _box(col, 12)
		if state == "focus":
			sb.draw_center = false
			sb.border_color = Color(1, 0.85, 0.2)
			sb.set_border_width_all(3)
		t.set_stylebox(state, "Button", sb)
	t.set_font_size("font_size", "Button", 22)
	return t


func _box(color: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


## Anchors `c` at a point of the screen (0..1) and offsets it by `rect` from there.
func _place(c: Control, anchor: Vector2, rect: Rect2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = rect.position.x
	c.offset_top = rect.position.y
	c.offset_right = rect.end.x
	c.offset_bottom = rect.end.y


func _rich(width: float) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.custom_minimum_size.x = width
	return r


func _build_crosshair() -> void:
	_crosshair = Control.new()
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_crosshair, Vector2(0.5, 0.5), Rect2(-12, -12, 24, 24))
	_crosshair.draw.connect(func() -> void:
		var c := Vector2(12, 12)
		var hot := _prompt.text != ""
		_crosshair.draw_circle(c, 3.5, Color(0, 0, 0, 0.6))
		_crosshair.draw_circle(c, 2.0, Color(1, 0.85, 0.2) if hot else Color.WHITE)
		if hot:
			_crosshair.draw_arc(c, 10, 0, TAU, 24, Color(1, 0.85, 0.2, 0.9), 2.0))
	_root.add_child(_crosshair)
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 20)
	_place(_prompt, Vector2(0.5, 0.5), Rect2(-300, 22, 600, 30))
	_root.add_child(_prompt)


func _build_subtitles() -> void:
	_subtitle_box = PanelContainer.new()
	_subtitle_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_subtitle_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle = _rich(760)
	_subtitle.add_theme_font_size_override("normal_font_size", 22)
	_subtitle.add_theme_font_size_override("bold_font_size", 22)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_box.add_child(_subtitle)
	_subtitle_box.visible = false
	_root.add_child(_subtitle_box)
	_place_subtitles(false)


func _place_subtitles(above_panel: bool) -> void:
	var bottom := -285.0 if above_panel else -40.0
	_place(_subtitle_box, Vector2(0.5, 1), Rect2(-394, bottom, 788, 0))


func _build_top_left() -> void:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 8)
	_place(col, Vector2.ZERO, Rect2(16, 16, 420, 0))
	_root.add_child(col)
	_objective_box = PanelContainer.new()
	_objective_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	var head := Label.new()
	head.text = "OBJECTIVE"
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", Color(1, 0.8, 0.25))
	v.add_child(head)
	_objective = Label.new()
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.custom_minimum_size.x = 380
	v.add_child(_objective)
	_objective_box.add_child(v)
	_objective_box.visible = false
	col.add_child(_objective_box)
	_toasts = VBoxContainer.new()
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_toasts)


func _build_strip() -> void:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_place(box, Vector2(1, 0), Rect2(-16, 16, 0, 0))
	_strip = _rich(330)
	_strip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_strip.add_theme_font_size_override("normal_font_size", 17)
	box.add_child(_strip)
	_root.add_child(box)


func _build_cheats() -> void:
	_cheats = PanelContainer.new()
	_cheats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_cheats, Vector2(0, 0.5), Rect2(16, -60, 0, 0))
	var r := _rich(380)
	r.add_theme_font_size_override("normal_font_size", 16)
	r.text = CHEATS
	_cheats.add_child(r)
	_root.add_child(_cheats)


func _overlay() -> Control:
	var o := ColorRect.new()
	o.color = Color(0.02, 0.04, 0.12, 0.6)
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.visible = false
	_root.add_child(o)
	return o


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 52)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _title(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 14)
	return l


func _build_pause() -> void:
	_pause = _overlay()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_place(box, Vector2(0.5, 0.5), Rect2(-170, -150, 340, 300))
	_pause.add_child(box)
	box.add_child(_title("PAUSED", 48, Color.WHITE))
	var sub := Label.new()
	sub.text = "(the plane is not. Good luck.)"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	_button(box, "Resume", _resume)
	_button(box, "Leave flight", _leave)


func _build_results() -> void:
	_results = _overlay()
	var panel := PanelContainer.new()
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_place(panel, Vector2(0.5, 0.5), Rect2(-280, -250, 560, 500))
	_results.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_results_title = _title("", 64, Color.WHITE)
	box.add_child(_results_title)
	_results_text = _rich(520)
	_results_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_results_text)
	var leave := _button(box, "Leave flight", _leave)
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


# --- Per frame -------------------------------------------------------------------------------

func _process(dt: float) -> void:
	_time += dt
	var p := world.local_player
	var piloting := p != null and p.piloting
	var prompt := p.aim_prompt if p else ""
	if blocking_input():
		prompt = ""
	if _prompt.text != prompt:
		_prompt.text = prompt
		_crosshair.queue_redraw()
	_crosshair.visible = not blocking_input()
	if _pilot.visible != piloting:
		_pilot.visible = piloting
		_place_subtitles(piloting)
	_update_subtitles(dt)
	_update_objective()
	_strip.text = _strip_text()
	if _cheats.visible:
		_cheats.modulate.a = clampf(CHEAT_TIME + 1.0 - _time, 0.0, 1.0)
		_cheats.visible = _time < CHEAT_TIME + 1.0


func _update_objective() -> void:
	var obj: Variant = world.story.get("objective") if world.story else null
	var text := str(obj) if obj != null else ""
	_objective_box.visible = text != ""
	if _objective.text != text:
		_objective.text = text


func _strip_text() -> String:
	var f := world.flight
	var lines: Array[String] = []
	if f.phase == FlightModel.Phase.FLYING:
		lines.append("ALT [b]%d ft[/b]   [b]%d kt[/b]" % [roundi(f.altitude() * M_TO_FT), roundi(f.speed * MS_TO_KT)])
	elif f.phase == FlightModel.Phase.CRASHED:
		lines.append("[color=#ff6b5b]ON THE GROUND (IN PIECES)[/color]")
	else:
		lines.append("ON THE GROUND   [b]%d kt[/b]" % roundi(f.speed * MS_TO_KT))
	var g := f.felt_gravity()
	var g_text := "GRAVITY %.1fg" % g
	if g < 0.25:
		g_text += "  ZERO-G!"
	elif g < 0.65:
		g_text += "  FLOATY"
	elif g > 1.5:
		g_text += "  HEAVY"
	if absf(g - 1.0) > 0.35:
		var c := Color.from_hsv(fmod(_time * 0.8, 1.0), 0.65, 1.0)
		lines.append("[color=#%s][b]%s[/b][/color]" % [c.to_html(false), g_text])
	else:
		lines.append(g_text)
	var blink := fmod(_time, 0.8) < 0.5
	for i in 2:
		if world.plane.engine_fire[i]:
			var name_text := "LEFT" if i == 0 else "RIGHT"
			var col := "#ff3b2f" if blink else "#ffb000"
			lines.append("[color=%s][b]!! %s ENGINE ON FIRE !![/b][/color]" % [col, name_text])
	if f.phase == FlightModel.Phase.FLYING and not f.has_pilot:
		lines.append("[color=%s]NOBODY IS FLYING THE PLANE[/color]" % ("#ffd23f" if blink else "#ffffff"))
	var damage := _damage_text()
	if damage != "":
		lines.append(damage)
	return "\n".join(lines)


## Compact airframe health: only parts below full health, coloured, worst flashing.
func _damage_text() -> String:
	var bits: Array[String] = []
	for part in PilotPanel.PARTS:
		var hp: float = PilotPanel.part_health(world, part[0])
		if hp < 0.98:
			var col: Color = PilotPanel.health_color(hp, _time)
			bits.append("[color=#%s]%s %d%%[/color]" % [col.to_html(false), part[1], roundi(hp * 100)])
	if bits.is_empty():
		return ""
	return "[font_size=15]" + "  ".join(bits) + "[/font_size]"


# --- Subtitles and toasts -------------------------------------------------------------------

func _on_subtitle(speaker: String, text: String, duration: float) -> void:
	_sub_queue.append([speaker, text, duration])
	if not _subtitle_box.visible:
		_next_subtitle()


func _next_subtitle() -> void:
	if _sub_queue.is_empty():
		_subtitle_box.visible = false
		return
	var s: Array = _sub_queue.pop_front()
	var speaker: String = s[0]
	var col: String = SPEAKER_COLORS[absi(speaker.hash()) % SPEAKER_COLORS.size()]
	var body := (s[1] as String).replace("[", "[lb]")
	_subtitle.text = "[b][color=%s]%s:[/color][/b] %s" % [col, speaker.to_upper().replace("[", "[lb]"), body]
	# A backed-up queue speeds lines along so nobody is reading old news.
	_sub_time = float(s[2]) / (1.0 + _sub_queue.size() * 0.5)
	_subtitle_box.visible = true


func _update_subtitles(dt: float) -> void:
	if not _subtitle_box.visible:
		return
	_sub_time -= dt
	if _sub_time <= 0.0:
		_next_subtitle()


func _on_toast(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 400
	l.add_theme_color_override("font_color", Color(1, 0.92, 0.6))
	_toasts.add_child(l)
	while _toasts.get_child_count() > MAX_TOASTS:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var t := l.create_tween()
	t.tween_interval(TOAST_TIME)
	t.tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)


# --- Pause, results, restart -----------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _pause.visible:
			_resume()
		elif not _results.visible:
			_open_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart") and _results.visible and multiplayer.is_server():
		get_viewport().set_input_as_handled()
		_main().call("restart_round")
	elif event is InputEventMouseButton and event.pressed and not blocking_input() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Clicking back into the game (after alt-tab) recaptures the mouse instead of throwing.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _main() -> Node:
	return get_parent().get_parent()


func _open_pause() -> void:
	_pause.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume() -> void:
	_pause.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _leave() -> void:
	_main().call("leave_game")


func _on_round_ended(result: Dictionary) -> void:
	var landed: bool = result.get("landed", false)
	if not landed:
		_ambience.call("boom")
		_flash.color = Color(1, 0.65, 0.25, 0.9)
		var t := create_tween()
		t.tween_property(_flash, "color:a", 0.0, 1.4).set_ease(Tween.EASE_OUT)
	_fill_results(result)
	await get_tree().create_timer(1.5 if landed else 3.0).timeout
	if not is_inside_tree():
		return
	_pause.visible = false
	_results.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _fill_results(r: Dictionary) -> void:
	var landed: bool = r.get("landed", false)
	_results_title.text = "LANDED!" if landed else "CRASHED!"
	_results_title.add_theme_color_override("font_color", Color(0.4, 1, 0.5) if landed else Color(1, 0.4, 0.3))
	var lines: Array[String] = []
	if landed:
		if r.get("on_runway", false):
			lines.append("On the runway. Textbook. Probably.")
		else:
			lines.append("In a field. The cows are furious.")
		lines.append("Touchdown sink rate: %.1f m/s" % float(r.get("sink", 0.0)))
	else:
		lines.append("You %s." % str(r.get("reason", "crashed")))
	lines.append("")
	lines.append("[font_size=34][color=#ffd23f][b]SCORE %d[/b][/color][/font_size]" % int(r.get("score", 0)))
	lines.append("")
	lines.append("[b]CHAOS REPORT[/b]")
	var stats: Dictionary = r.get("stats", {})
	for s in STAT_LABELS:
		lines.append("%s: [b]%d[/b]" % [s[1], int(stats.get(s[0], 0))])
	lines.append("[color=#ff8fa3]Chaos score: [b]%d[/b][/color]" % int(r.get("chaos", 0)))
	lines.append("")
	if multiplayer.is_server():
		lines.append("[color=#7fd6ff][b]Host: press [lb]R] to fly again[/b][/color]")
	else:
		lines.append("[color=#7fd6ff]Waiting for the host to press [lb]R]...[/color]")
	_results_text.text = "\n".join(lines)
