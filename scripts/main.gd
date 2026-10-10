extends Node
## Title menu, input map, and round lifecycle (create / restart / leave the World).
##
## Command line (after `--`): --host | --join=IP  [--name=NAME]  [--quit-after=SECONDS]
## Dev checks: --shot=PATH.png [--shot-at=SECONDS] [--at=x,y,z plane-local] [--look=yawdeg,pitchdeg]

const WorldScript := preload("res://scripts/world.gd")

const ACTIONS := {
	"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
	"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "crouch": [KEY_CTRL, KEY_C],
	"interact": [KEY_E], "shout": [KEY_Y], "gear": [KEY_G], "flaps": [KEY_F], "pause": [KEY_ESCAPE], "restart": [KEY_R],
	"throw": [MOUSE_BUTTON_LEFT], "use": [MOUSE_BUTTON_RIGHT],
}

var world: Node3D
var menu: Control
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _status: Label


static func setup_input() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for code in ACTIONS[action]:
			var ev: InputEvent
			if action in ["throw", "use"]:
				ev = InputEventMouseButton.new()
				ev.button_index = code
			else:
				ev = InputEventKey.new()
				ev.physical_keycode = code
			InputMap.action_add_event(action, ev)


func _ready() -> void:
	setup_input()
	Net.joined.connect(_on_joined)
	Net.join_failed.connect(func() -> void: _back_to_menu("Couldn't connect. Check the IP and that the host is running."))
	Net.host_lost.connect(func() -> void: _back_to_menu("The host left. The plane is gone."))
	_build_menu()
	var args := _cli_args()
	if args.has("name"):
		_name_edit.text = args.name
	if args.has("quit-after"):
		get_tree().create_timer(float(args["quit-after"])).timeout.connect(get_tree().quit)
	if args.has("shot"):
		_dev_shot(args)
	if args.has("host"):
		_on_host()
	elif args.has("join"):
		_ip_edit.text = args.join
		_on_join()


func _cli_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else ""
	return out


## Saves one frame for automated visual checks, optionally from a chosen spot in the plane.
func _dev_shot(args: Dictionary) -> void:
	await get_tree().create_timer(float(args.get("shot-at", "3"))).timeout
	var p: Player = world.local_player if world else null
	if p and args.has("at"):
		var v := (args.at as String).split_floats(",")
		p.stand()
		p.global_position = world.plane.to_global(Vector3(v[0], v[1], v[2]))
	if p and args.has("look"):
		var l := (args.look as String).split_floats(",")
		p.rotation.y = deg_to_rad(l[0])
		p.look_pitch = deg_to_rad(l[1])
		p.head.rotation.x = p.look_pitch
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args.shot)
	print("SHOT ", args.shot)


func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := func(color: Color, radius: int, pad: float) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = color
		s.set_corner_radius_all(radius)
		s.content_margin_left = pad
		s.content_margin_right = pad
		s.content_margin_top = pad * 0.6
		s.content_margin_bottom = pad * 0.6
		return s
	var theme := Theme.new()
	theme.default_font_size = 19
	theme.set_color("font_color", "Label", Color(0.1, 0.15, 0.35))
	theme.set_stylebox("normal", "LineEdit", style.call(Color(1, 1, 1, 0.95), 10, 12.0))
	theme.set_stylebox("focus", "LineEdit", style.call(Color(1, 0.9, 0.5, 0.35), 10, 12.0))
	theme.set_color("font_color", "LineEdit", Color(0.1, 0.15, 0.35))
	for state in ["normal", "hover", "pressed", "focus"]:
		var col: Color = {"normal": Color(0.2, 0.45, 0.95), "hover": Color(0.3, 0.58, 1.0),
			"pressed": Color(0.95, 0.6, 0.15), "focus": Color(0.2, 0.45, 0.95)}[state]
		var sb: StyleBoxFlat = style.call(col, 14, 16.0)
		sb.shadow_color = Color(0.05, 0.1, 0.3, 0.35)
		sb.shadow_offset = Vector2(0, 4)
		sb.shadow_size = 2
		if state == "focus":
			sb.draw_center = false
			sb.border_color = Color(1, 0.85, 0.2)
			sb.set_border_width_all(3)
		theme.set_stylebox(state, "Button", sb)
	theme.set_font_size("font_size", "Button", 22)
	theme.set_color("font_outline_color", "Button", Color(0.05, 0.1, 0.3))
	theme.set_constant("outline_size", "Button", 5)
	menu.theme = theme
	add_child(menu)
	# Cartoon sky with blocky clouds and a strip of farmland.
	var sky := TextureRect.new()
	var grad := GradientTexture2D.new()
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, Color(0.2, 0.5, 0.95))
	grad.gradient.set_color(1, Color(0.72, 0.88, 1.0))
	grad.fill_from = Vector2(0, 0)
	grad.fill_to = Vector2(0, 1)
	sky.texture = grad
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(sky)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 9:
		var cloud := Control.new()
		cloud.anchor_left = rng.randf_range(-0.05, 0.9)
		cloud.anchor_top = rng.randf_range(0.05, 0.6)
		cloud.modulate.a = rng.randf_range(0.7, 0.95)
		menu.add_child(cloud)
		var s := rng.randf_range(0.6, 1.4)
		for part in [Rect2(0, 20, 160, 40), Rect2(25, 0, 70, 30), Rect2(80, 6, 60, 26)]:
			var r := ColorRect.new()
			r.position = part.position * s
			r.size = part.size * s
			cloud.add_child(r)
	var ground := HBoxContainer.new()
	ground.anchor_top = 0.86
	ground.anchor_right = 1.0
	ground.anchor_bottom = 1.0
	ground.add_theme_constant_override("separation", 0)
	menu.add_child(ground)
	for c in [Color(0.55, 0.8, 0.3), Color(0.93, 0.82, 0.32), Color(0.36, 0.66, 0.26), Color(0.62, 0.44, 0.27),
			Color(0.78, 0.86, 0.38), Color(0.98, 0.66, 0.25), Color(0.45, 0.75, 0.5)]:
		var field := ColorRect.new()
		field.color = c
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ground.add_child(field)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style.call(Color(1, 1, 1, 0.82), 22, 28.0))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	menu.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(480, 0)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "ANY PILOTS ON BOARD?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(1, 0.84, 0.2))
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.15, 0.35))
	title.add_theme_constant_override("outline_size", 16)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "The pilot passed out. You said you could fly. You can't."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(sub)
	_name_edit = _field(box, "Your name", "Passenger %d" % (randi() % 900 + 100))
	var host := Button.new()
	host.text = "Host a flight (solo or with friends)"
	host.pressed.connect(_on_host)
	box.add_child(host)
	_ip_edit = _field(box, "Host IP", "127.0.0.1")
	var join := Button.new()
	join.text = "Join a friend's flight"
	join.pressed.connect(_on_join)
	box.add_child(join)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(get_tree().quit)
	box.add_child(quit)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size.x = 480
	box.add_child(_status)
	var ips := Net.lan_addresses()
	if not ips.is_empty():
		_status.text = "Friends on your Wi-Fi join you at: " + ", ".join(ips)


func _field(parent: Control, label: String, value: String) -> LineEdit:
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 15)
	parent.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.custom_minimum_size.y = 40
	parent.add_child(e)
	return e


func _on_host() -> void:
	Net.local_name = _name_edit.text.strip_edges()
	var err := Net.host()
	if err != OK:
		_status.text = "Couldn't host on port %d (error %d). Is another game already hosting?" % [Net.PORT, err]
		return
	_start_world()


func _on_join() -> void:
	Net.local_name = _name_edit.text.strip_edges()
	var err := Net.join(_ip_edit.text.strip_edges())
	if err != OK:
		_status.text = "Couldn't start connecting (error %d)." % err
		return
	_status.text = "Connecting to %s..." % _ip_edit.text


func _on_joined() -> void:
	_start_world()


func _start_world() -> void:
	menu.visible = false
	world = WorldScript.new()
	world.name = "World"
	add_child(world)


## Host only: everyone gets a fresh round.
func restart_round() -> void:
	if not multiplayer.is_server():
		return
	_rpc_restart.rpc()
	_rpc_restart()


@rpc("authority", "call_remote", "reliable")
func _rpc_restart() -> void:
	if world:
		remove_child(world)
		world.queue_free()
	_start_world()


func leave_game() -> void:
	Net.leave()
	_back_to_menu("")


func _back_to_menu(message: String) -> void:
	if world:
		world.queue_free()
		world = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.visible = true
	_status.text = message
