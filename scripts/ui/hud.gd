extends CanvasLayer
## HUD: crosshair and aim prompt, subtitles, toasts, objective, flight strip, the pilot panel,
## a controls cheat-sheet, the pause menu, the results screen, crash flash and the ambience.
## Also: manifest board UI, phase banner, and payout report.

const PilotPanel := preload("res://scripts/ui/pilot_panel.gd")
const Ambience := preload("res://scripts/ui/ambience.gd")
const SettingsMenu := preload("res://scripts/ui/settings_menu.gd")

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
const CHEATS := "[b]CREW CONTROLS[/b]\n" \
	+ "WASD move · Space jump · Shift sprint\n" \
	+ "Ctrl/C crouch & brace · Y shout\n" \
	+ "E interact / pick up / drop\n" \
	+ "LMB throw or punch · RMB use item\n" \
	+ "V camera · MMB ping · T push-to-talk\n" \
	+ "B seatbelt sign (pilot) · G gear · F flaps\n" \
	+ "Esc pause"

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
var _pause_box: VBoxContainer
var _settings: SettingsMenu
var _awards_box: VBoxContainer
var _fps_label: Label

# --- Airline / Manifest UI ---
var _phase_banner: PanelContainer
var _phase_label: Label
var _manifest_ui: ColorRect
var _manifest_cards: VBoxContainer
var _manifest_totals: Label
var _manifest_start_btn: Button
var _payout_report: ColorRect
var _payout_text: RichTextLabel
var _payout_awards: VBoxContainer
var _manifest_visible := false
var _payout_visible := false

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
	_build_phase_banner()
	_build_manifest_ui()
	_build_payout_report()
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
	_build_fps_counter()
	_ambience = Ambience.new()
	_ambience.set("world", world)
	add_child(_ambience)
	world.subtitle.connect(_on_subtitle)
	world.toast.connect(_on_toast)
	world.round_ended.connect(_on_round_ended)
	# Manifest board interactable
	if world.plane != null and world.plane.manifest_board != null:
		world.plane.manifest_board.used.connect(_open_manifest_ui.unbind(1))
	# Airline signals
	if world.airline != null:
		world.airline.phase_changed.connect(_on_airline_phase_changed)
		world.airline.contracts_changed.connect(_refresh_manifest_cards)
		world.airline.bank_changed.connect(_update_phase_banner)
		world.airline.flight_no_changed.connect(_update_phase_banner)
		# Initial update
		_on_airline_phase_changed(world.airline.phase)
		_update_phase_banner()
		_refresh_manifest_cards()


## True while the pause menu (incl. settings) or results screen should swallow gameplay input.
func blocking_input() -> bool:
	return _pause.visible or _results.visible or _manifest_visible or _payout_visible


# --- Airline signal handlers ----------------------------------------------------------------

func _on_airline_phase_changed(phase: String) -> void:
	_update_phase_banner()
	if phase == "manifest":
		_open_manifest_ui()
	elif phase == "boarding":
		_close_manifest_ui()
	elif phase == "flight":
		_close_manifest_ui()
	elif phase == "report":
		_close_manifest_ui()
		_show_payout_report()

func _update_phase_banner() -> void:
	if world.airline == null:
		return
	var phase: String = world.airline.phase
	var flight_no: int = world.airline.flight_no
	var bank: int = world.airline.bank
	var text: String = ""
	match phase:
		"manifest":
			text = "[b]FLIGHT DP-%03d[/b]   [color=#ffd23f]MANIFEST[/color]   Bank: $[b]%d[/b]" % [flight_no, bank]
			text += "\nChoose contracts. Press [E] on the manifest board to open."
		"boarding":
			var timer := 0
			if world.airline.has_method("boarding_timer"):
				timer = int(world.airline.boarding_timer)
			text = "[b]FLIGHT DP-%03d[/b]   [color=#7fd6ff]BOARDING[/color]   Bank: $[b]%d[/b]" % [flight_no, bank]
			text += "\nPassengers boarding... Ramp closes in [b]%ds[/b]." % timer
		"flight":
			text = "[b]FLIGHT DP-%03d[/b]   [color=#9dff8a]IN FLIGHT[/color]   Bank: $[b]%d[/b]" % [flight_no, bank]
			text += "\nServe passengers, protect cargo, survive the weather."
		"report":
			text = "[b]FLIGHT DP-%03d[/b]   [color=#ff8fa3]REPORT[/color]   Bank: $[b]%d[/b]" % [flight_no, bank]
			text += "\nReviewing payout..."
		_:
			text = "[b]FLIGHT DP-%03d[/b]   %s   Bank: $[b]%d[/b]" % [flight_no, phase, bank]
	_phase_label.text = text
	_phase_banner.visible = true

func _refresh_manifest_cards() -> void:
	if world.airline == null:
		return
	for child in _manifest_cards.get_children():
		child.queue_free()
	
	var contracts: Array = world.airline.contracts
	var pax_total := 0
	var cargo_total := 0
	var payout_total := 0
	
	for c in contracts:
		var card := _make_contract_card(c)
		_manifest_cards.add_child(card)
		if c.accepted:
			if c.type == "passengers":
				pax_total += c.count
			else:
				cargo_total += c.count
			payout_total += c.payout
	
	_manifest_totals.text = "ACCEPTED:  Passengers [b]%d/32[/b]   Cargo [b]%d/10[/b]   Est. Payout: $[b]%d[/b]" % [pax_total, cargo_total, payout_total]
	
	var has_pax := false
	for c in contracts:
		if c.accepted and c.type == "passengers":
			has_pax = true
			break
	_manifest_start_btn.disabled = not has_pax
	_manifest_start_btn.text = "Start Boarding" if has_pax else "Accept at least one passenger contract"

# --- Manifest UI builders -------------------------------------------------------------------

func _build_phase_banner() -> void:
	_phase_banner = PanelContainer.new()
	_phase_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phase_banner.add_theme_stylebox_override("panel", _round_panel(Color(0.04, 0.06, 0.14, 0.9), Color(1, 0.84, 0.2), 16.0))
	_place(_phase_banner, Vector2(0.5, 0), Rect2(-400, 16, 800, 0))
	_phase_label = Label.new()
	_phase_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.add_theme_font_size_override("font_size", 20)
	_phase_label.add_theme_color_override("font_color", Color(1, 0.92, 0.6))
	_phase_banner.add_child(_phase_label)
	_root.add_child(_phase_banner)
	_phase_banner.visible = false

func _build_manifest_ui() -> void:
	_manifest_ui = _overlay()
	_manifest_ui.color = Color(0.02, 0.04, 0.12, 0.85)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _round_panel(Color(0.06, 0.09, 0.22, 0.95), Color(1, 0.84, 0.2), 24.0))
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_place(panel, Vector2(0.5, 0.5), Rect2(0, 0, 0, 0))
	_manifest_ui.add_child(panel)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)
	
	var title := _title("MANIFEST  •  FLIGHT DP-%03d" % (world.airline.flight_no if world.airline else 1), 40, Color(1, 0.84, 0.2))
	vbox.add_child(title)
	
	var subtitle := Label.new()
	subtitle.text = "Toggle contracts to accept/decline. At least one passenger contract required to start."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)
	
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 320
	vbox.add_child(scroll)
	
	_manifest_cards = VBoxContainer.new()
	_manifest_cards.add_theme_constant_override("separation", 10)
	scroll.add_child(_manifest_cards)
	
	_manifest_totals = Label.new()
	_manifest_totals.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_manifest_totals.add_theme_font_size_override("font_size", 18)
	_manifest_totals.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	vbox.add_child(_manifest_totals)
	
	_manifest_start_btn = _button(vbox, "Start Boarding", _on_manifest_confirm)
	_manifest_start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	var close_btn := _button(vbox, "Close (ESC)", _close_manifest_ui)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	_manifest_ui.visible = false

func _make_contract_card(contract: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _round_panel(
		Color(0.1, 0.14, 0.28, 0.95),
		Color(0.2, 0.45, 0.95) if contract.accepted else Color(0.4, 0.4, 0.5),
		14.0
	))
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	card.add_child(hbox)
	
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	hbox.add_child(left)
	
	var kind_color := Color(0.4, 0.8, 1.0) if contract.type == "passengers" else Color(1.0, 0.7, 0.3)
	var kind_icon := "👥" if contract.type == "passengers" else "📦"
	var risk_stars: String = "★".repeat(int(contract.risk)) + "☆".repeat(3 - int(contract.risk))
	
	var header := Label.new()
	header.text = "[color=#%s][b]%s %s[/b][/color]  [color=#aaa]%s[/color]  [color=#ffd23f]%s[/color]" % [
		kind_color.to_html(false), kind_icon, contract.name, contract.kind, risk_stars
	]
	header.add_theme_font_size_override("font_size", 18)
	left.add_child(header)
	
	var blurb := Label.new()
	blurb.text = contract.blurb
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size.x = 420
	blurb.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	left.add_child(blurb)
	
	var details := Label.new()
	details.text = "Count: [b]%d[/b]   Payout: $[b]%d[/b]" % [contract.count, contract.payout]
	details.add_theme_font_size_override("font_size", 16)
	details.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	left.add_child(details)
	
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(right)
	
	var toggle := Button.new()
	toggle.text = "ACCEPTED" if contract.accepted else "DECLINED"
	toggle.custom_minimum_size = Vector2(160, 48)
	toggle.add_theme_stylebox_override("normal", _box(
		Color(0.2, 0.6, 0.25) if contract.accepted else Color(0.6, 0.2, 0.2), 12
	))
	toggle.add_theme_stylebox_override("hover", _box(
		Color(0.3, 0.75, 0.3) if contract.accepted else Color(0.8, 0.3, 0.3), 12
	))
	toggle.add_theme_stylebox_override("pressed", _box(
		Color(0.15, 0.5, 0.2) if contract.accepted else Color(0.5, 0.15, 0.15), 12
	))
	toggle.pressed.connect(func() -> void: _toggle_contract(contract.id))
	right.add_child(toggle)
	
	return card

func _toggle_contract(contract_id: int) -> void:
	if world.airline != null:
		world.request("manifest_toggle", [contract_id])

func _on_manifest_confirm() -> void:
	if world.airline != null:
		world.request("manifest_confirm", [])

func _open_manifest_ui() -> void:
	if _manifest_visible or _payout_visible or _results.visible:
		return
	_manifest_visible = true
	_manifest_ui.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_manifest_cards()

func _close_manifest_ui() -> void:
	if not _manifest_visible:
		return
	_manifest_visible = false
	_manifest_ui.visible = false
	if not _payout_visible and not _pause.visible and not _results.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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


func _box(color: Color, radius: int, h_margin := 14, v_margin := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = h_margin
	s.content_margin_right = h_margin
	s.content_margin_top = v_margin
	s.content_margin_bottom = v_margin
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
	_pause_box = VBoxContainer.new()
	_pause_box.add_theme_constant_override("separation", 14)
	_pause_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_place(_pause_box, Vector2(0.5, 0.5), Rect2(-170, -170, 340, 340))
	_pause.add_child(_pause_box)
	_pause_box.add_child(_title("PAUSED", 48, Color.WHITE))
	var sub := Label.new()
	sub.text = "(the plane is not. Good luck.)"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_box.add_child(sub)
	_button(_pause_box, "Resume", _resume)
	_button(_pause_box, "Settings", _open_settings)
	_button(_pause_box, "Leave flight", _leave)
	_settings = SettingsMenu.new()
	_settings.closed.connect(func() -> void: _pause_box.visible = true)
	_pause.add_child(_settings)


func _build_results() -> void:
	_results = _overlay()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _round_panel(Color(0.06, 0.09, 0.22, 0.92), Color(1, 0.84, 0.2)))
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_place(panel, Vector2(0.5, 0.5), Rect2(0, 0, 0, 0))
	_results.add_child(panel)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	panel.add_child(cols)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	cols.add_child(box)
	_results_title = _title("", 64, Color.WHITE)
	box.add_child(_results_title)
	_results_text = _rich(460)
	_results_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_results_text)
	var leave := _button(box, "Leave flight", _leave)
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_awards_box = VBoxContainer.new()
	_awards_box.add_theme_constant_override("separation", 8)
	cols.add_child(_awards_box)


func _build_fps_counter() -> void:
	_fps_label = Label.new()
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.add_theme_font_size_override("font_size", 18)
	_fps_label.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
	_place(_fps_label, Vector2(0.5, 0), Rect2(-60, 8, 120, 26))
	_fps_label.visible = false
	_root.add_child(_fps_label)


## Chunky rounded panel with a coloured rim and a soft drop shadow.
func _round_panel(color: Color, rim: Color, pad := 24.0) -> StyleBoxFlat:
	var s := _box(color, int(pad))
	s.border_color = rim
	s.set_border_width_all(4)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 6)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.75
	s.content_margin_bottom = pad * 0.75
	return s


# --- Per frame -------------------------------------------------------------------------------


func _process(dt: float) -> void:
	_time += dt
	var p := world.local_player
	var piloting := p != null and p.piloting
	var prompt := p.aim_prompt if p else ""
	var blocked := blocking_input()
	if blocked:
		prompt = ""
		# The local Player captures the mouse when it spawns (after the manifest auto-opens):
		# any open menu must keep the cursor free so its buttons can be clicked.
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _prompt.text != prompt:
		_prompt.text = prompt
		_crosshair.queue_redraw()
	_crosshair.visible = not blocked
	if _pilot.visible != piloting:
		_pilot.visible = piloting
		_place_subtitles(piloting)
	_update_subtitles(dt)
	_update_objective()
	_strip.text = _strip_text()
	if _cheats.visible:
		_cheats.modulate.a = clampf(CHEAT_TIME + 1.0 - _time, 0.0, 1.0)
		_cheats.visible = _time < CHEAT_TIME + 1.0
	_fps_label.visible = Settings.show_fps
	if _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()


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
	if speaker.strip_edges() == "":
		# Narrator / sound-effect line: no speaker label, italic.
		_subtitle.text = "[i]%s[/i]" % body
	else:
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
		if _settings.visible:
			_settings.close()
		elif _pause.visible:
			_resume()
		elif _manifest_visible:
			_close_manifest_ui()
		elif not _results.visible and not _payout_visible:
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
	_settings.visible = false
	_pause_box.visible = true
	_pause.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _leave() -> void:
	_main().call("leave_game")


func _open_settings() -> void:
	_pause_box.visible = false
	_settings.open()




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
	_fill_awards(r.get("awards", []))


## One chunky card per crew award (from Scoring.awards via the round result).
func _fill_awards(awards: Array) -> void:
	for child in _awards_box.get_children():
		child.queue_free()
	_awards_box.visible = not awards.is_empty()
	if awards.is_empty():
		return
	_awards_box.add_child(_title("CREW AWARDS", 30, Color(1, 0.84, 0.2)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_awards_box.add_child(grid)
	for i in awards.size():
		var a: Dictionary = awards[i]
		var card := PanelContainer.new()
		var tint := Color(SPEAKER_COLORS[i % SPEAKER_COLORS.size()])
		card.add_theme_stylebox_override("panel", _round_panel(Color(0.12, 0.16, 0.34, 0.95), tint, 14.0))
		var r := _rich(270)
		r.text = "[font_size=21][color=#%s][b]%s[/b][/color][/font_size]\n[b]%s[/b]  [color=#c8d4ff]%s[/color]" % [
			tint.to_html(false), str(a.title).replace("[", "[lb]"), str(a.name).replace("[", "[lb]"),
			str(a.text).replace("[", "[lb]")]
		card.add_child(r)
		grid.add_child(card)


# --- Payout Report --------------------------------------------------------------------------

func _build_payout_report() -> void:
	_payout_report = _overlay()
	_payout_report.color = Color(0.02, 0.04, 0.12, 0.85)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _round_panel(Color(0.06, 0.09, 0.22, 0.95), Color(1, 0.84, 0.2), 24.0))
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_place(panel, Vector2(0.5, 0.5), Rect2(0, 0, 0, 0))
	_payout_report.add_child(panel)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 28)
	margin.add_child(hbox)
	
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	hbox.add_child(left)
	
	_payout_text = _rich(520)
	_payout_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_payout_text.add_theme_font_size_override("normal_font_size", 18)
	_payout_text.add_theme_font_size_override("bold_font_size", 20)
	left.add_child(_payout_text)
	
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	left.add_child(btn_row)
	
	var next_btn := _button(btn_row, "Next Flight [R]", _on_next_flight)
	next_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	var leave_btn := _button(btn_row, "Leave", _leave)
	leave_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	_payout_awards = VBoxContainer.new()
	_payout_awards.add_theme_constant_override("separation", 8)
	hbox.add_child(_payout_awards)
	
	_payout_report.visible = false

func _show_payout_report() -> void:
	if _payout_visible or _results.visible:
		return
	_payout_visible = true
	_payout_report.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_next_flight() -> void:
	if multiplayer.is_server():
		_main().call("restart_round")
	_payout_visible = false
	_payout_report.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _fill_payout_report(r: Dictionary) -> void:
	var payout: Dictionary = r.get("payout", {})
	var line_items: Array = payout.get("line_items", [])
	var total: int = payout.get("total", 0)
	var new_bank: int = payout.get("new_bank", 0)
	var tips_total: int = payout.get("tips_total", 0)
	var penalties_total: int = payout.get("penalties_total", 0)
	var repair_cost: int = payout.get("repair_cost", 0)
	
	var lines: Array[String] = []
	lines.append("[b]PAYOUT REPORT[/b]")
	lines.append("")
	
	if line_items.is_empty():
		lines.append("[i]No contracts accepted.[/i]")
	else:
		for item in line_items:
			var label: String = item.get("label", "")
			var amount: int = item.get("amount", 0)
			var color := "#9dff8a" if amount >= 0 else "#ff6b5b"
			var sign := "+" if amount > 0 else ""
			lines.append("%s  [color=%s][b]%s%d[/b][/color]" % [label, color, sign, amount])
	
	lines.append("")
	lines.append("[color=#ffd23f][b]TOTAL: %s%d[/b][/color]" % ["+" if total >= 0 else "", total])
	lines.append("")
	lines.append("Bank: $[b]%d[/b]  [color=#7fd6ff]→[/color]  New Bank: $[b]%d[/b]" % [new_bank - total, new_bank])
	
	if tips_total > 0:
		lines.append("[color=#ffd23f]Tips earned: +%d[/color]" % tips_total)
	if penalties_total > 0:
		lines.append("[color=#ff6b5b]Penalties: -%d[/color]" % penalties_total)
	if repair_cost > 0:
		lines.append("[color=#ff8fa3]Repairs: -%d[/color]" % repair_cost)
	
	_payout_text.text = "\n".join(lines)
	
	_fill_payout_awards(r.get("awards", []))

func _fill_payout_awards(awards: Array) -> void:
	for child in _payout_awards.get_children():
		child.queue_free()
	_payout_awards.visible = not awards.is_empty()
	if awards.is_empty():
		return
	_payout_awards.add_child(_title("CREW AWARDS", 30, Color(1, 0.84, 0.2)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_payout_awards.add_child(grid)
	for i in awards.size():
		var a: Dictionary = awards[i]
		var card := PanelContainer.new()
		var tint := Color(SPEAKER_COLORS[i % SPEAKER_COLORS.size()])
		card.add_theme_stylebox_override("panel", _round_panel(Color(0.12, 0.16, 0.34, 0.95), tint, 14.0))
		var r := _rich(270)
		r.text = "[font_size=21][color=#%s][b]%s[/b][/color][/font_size]\n[b]%s[/b]  [color=#c8d4ff]%s[/color]" % [
			tint.to_html(false), str(a.title).replace("[", "[lb]"), str(a.name).replace("[", "[lb]"),
			str(a.text).replace("[", "[lb]")]
		card.add_child(r)
		grid.add_child(card)

# Updated round end handler
func _on_round_ended(result: Dictionary) -> void:
	var landed: bool = result.get("landed", false)
	if not landed:
		_ambience.call("boom")
		_flash.color = Color(1, 0.65, 0.25, 0.9)
		var t := create_tween()
		t.tween_property(_flash, "color:a", 0.0, 1.4).set_ease(Tween.EASE_OUT)
	_fill_results(result)
	if result.has("payout"):
		_fill_payout_report(result)
	await get_tree().create_timer(1.5 if landed else 3.0).timeout
	if not is_inside_tree():
		return
	_pause.visible = false
	_results.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
