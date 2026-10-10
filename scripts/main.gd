extends Node
## Title menu, input map, and round lifecycle (create / restart / leave the World).
##
## Command line (after `--`): --host | --join=IP  [--name=NAME]  [--quit-after=SECONDS]
## Dev checks: --shot=PATH.png [--shot-at=SECONDS] [--at=x,y,z plane-local] [--look=yawdeg,pitchdeg]

const WorldScript := preload("res://scripts/world.gd")

const ACTIONS := {
	"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
	"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "crouch": [KEY_CTRL, KEY_C],
	"interact": [KEY_E], "shout": [KEY_Y], "gear": [KEY_G], "pause": [KEY_ESCAPE], "restart": [KEY_R],
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
	add_child(menu)
	var bg := ColorRect.new()
	bg.color = Color(0.45, 0.7, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(460, 0)
	box.position = Vector2(-230, -220)
	box.add_theme_constant_override("separation", 10)
	menu.add_child(box)
	var title := Label.new()
	title.text = "ANY PILOTS ON BOARD?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.15, 0.35))
	title.add_theme_constant_override("outline_size", 12)
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
	box.add_child(_status)
	var ips := Net.lan_addresses()
	if not ips.is_empty():
		_status.text = "Friends on your Wi-Fi join you at: " + ", ".join(ips)


func _field(parent: Control, label: String, value: String) -> LineEdit:
	var l := Label.new()
	l.text = label
	parent.add_child(l)
	var e := LineEdit.new()
	e.text = value
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
