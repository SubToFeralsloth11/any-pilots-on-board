extends FunStation
## A cramped lavatory booth in the lounge corner. The door opens and closes [E] (it blocks
## when shut). Inside, the flush button [E] triggers a vacuum flush that, for a moment, yanks
## loose objects and people toward the bowl.
## Local frame: the booth's door wall faces +X; the origin is the booth's floor centre.

const SIZE := Vector3(1.0, 2.25, 1.38)
const DOOR_W := 0.68
const FLUSH_TIME := 1.6
const FLUSH_REACH := 3.0
const FLUSH_LINES := ["FWOOOOOSHHHHHH", "*the plane briefly loses a little cabin pressure*",
	"*an eldritch gurgle*", "Where did my shoe go?", "FLUSH COMPLETE. Contents: classified."]

var _door: Node3D
var _door_shape: CollisionShape3D
var _bowl_lid: Node3D
var _sign: Label3D
var _flush_t := 0.0
var _push_t := 0.0


func default_state() -> Dictionary:
	return {"open": false, "flushes": 0}


func _build() -> void:
	var wall := FunLooks.mat(Color(0.88, 0.86, 0.82), 0.6)
	var trim := FunLooks.mat(Color(0.25, 0.3, 0.4), 0.4)
	var hx := SIZE.x / 2
	var hz := SIZE.z / 2
	# Two side panels and the front wall around the doorway (the plane wall closes the back).
	for sz in [-1.0, 1.0]:
		FunLooks.rounded_box(rig, Vector3(SIZE.x, SIZE.y, 0.05), 0.02, wall, Vector3(0, SIZE.y / 2, sz * hz))
		collider(Vector3(SIZE.x, SIZE.y, 0.05), Vector3(0, SIZE.y / 2, sz * hz))
	var side := (SIZE.z - DOOR_W) / 2
	for sz in [-1.0, 1.0]:
		var cz: float = sz * (DOOR_W / 2 + side / 2)
		FunLooks.rounded_box(rig, Vector3(0.05, SIZE.y, side), 0.02, wall, Vector3(hx, SIZE.y / 2, cz))
		collider(Vector3(0.05, SIZE.y, side), Vector3(hx, SIZE.y / 2, cz))
	part(FunLooks.box(Vector3(0.05, 0.25, DOOR_W)), wall, Vector3(hx, SIZE.y - 0.125, 0))
	part(FunLooks.box(Vector3(SIZE.x + 0.04, 0.04, SIZE.z + 0.04)), trim, Vector3(0, SIZE.y, 0))
	# Bi-fold door on a hinge at -Z.
	_door = Node3D.new()
	_door.position = Vector3(hx, 0, -DOOR_W / 2)
	rig.add_child(_door)
	FunLooks.rounded_box(_door, Vector3(0.04, 1.95, DOOR_W - 0.02), 0.015, FunLooks.mat(Color(0.95, 0.93, 0.88), 0.5),
		Vector3(0, 0.99, DOOR_W / 2))
	part(FunLooks.capsule(0.015, 0.12), FunLooks.metal(FunLooks.CHROME), Vector3(0.04, 1.0, DOOR_W - 0.1), Vector3.ZERO,
		Vector3.ONE, _door)
	_sign = FunLooks.label(_door, "", Vector3(0.025, 1.6, DOOR_W / 2), 28, Color.WHITE, Vector3(0, PI / 2, 0))
	_door_shape = collider(Vector3(0.05, 1.95, DOOR_W), Vector3(hx, 0.975, 0))
	label("LAVATORY", Vector3(hx + 0.03, 2.05, 0), 26, Color(0.3, 0.6, 1), Vector3(0, PI / 2, 0))
	area(Vector3(0.3, 1.9, DOOR_W), Vector3(hx + 0.05, 0.95, 0), "", "door")
	# Inside: toilet, flush button, sink, mirror.
	var porcelain := FunLooks.mat(Color(0.97, 0.97, 0.98), 0.15)
	var bowl_at := Vector3(-0.25, 0, -0.1)
	part(FunLooks.cyl(0.13, 0.1, 0.32, 18), porcelain, bowl_at + Vector3(0, 0.16, 0))
	part(FunLooks.sphere(0.2, 18), porcelain, bowl_at + Vector3(0.05, 0.36, 0), Vector3.ZERO, Vector3(1.15, 0.35, 0.9))
	part(FunLooks.torus(0.12, 0.19), FunLooks.mat(Color(0.2, 0.45, 0.9), 0.4), bowl_at + Vector3(0.05, 0.43, 0),
		Vector3.ZERO, Vector3(1.15, 1, 0.9))
	FunLooks.rounded_box(rig, Vector3(0.18, 0.4, 0.4), 0.04, porcelain, bowl_at + Vector3(-0.2, 0.55, 0))
	_bowl_lid = Node3D.new()
	_bowl_lid.position = bowl_at + Vector3(-0.12, 0.45, 0)
	rig.add_child(_bowl_lid)
	part(FunLooks.sphere(0.19, 16), FunLooks.mat(Color(0.2, 0.45, 0.9), 0.4), Vector3(0.0, 0.0, 0), Vector3(0, 0, -PI / 2),
		Vector3(0.12, 1.15, 0.9), _bowl_lid)
	_bowl_lid.rotation.z = 0.1
	collider(Vector3(0.5, 0.45, 0.42), bowl_at + Vector3(-0.05, 0.225, 0))
	var btn := bowl_at + Vector3(-0.42, 1.05, 0.25)
	part(FunLooks.cyl(0.05, 0.05, 0.02, 16), FunLooks.metal(FunLooks.CHROME), btn, Vector3(0, 0, PI / 2))
	part(FunLooks.cyl(0.035, 0.035, 0.03, 16), FunLooks.mat(Color(0.95, 0.15, 0.15), 0.3, 0.0, 0.6), btn + Vector3(0.01, 0, 0),
		Vector3(0, 0, PI / 2))
	label("FLUSH\n(vacuum)", btn + Vector3(0.03, 0.1, 0), 14, Color(1, 0.4, 0.4), Vector3(0, PI / 2, 0))
	area(Vector3(0.3, 0.3, 0.3), btn + Vector3(0.1, 0, 0), "Flush [E]  (what's the worst that could happen?)", "flush")
	var sink := Vector3(-0.3, 0.85, 0.42)
	part(FunLooks.cyl(0.14, 0.09, 0.1, 16), porcelain, sink, Vector3.ZERO, Vector3(1, 1, 0.8))
	part(FunLooks.capsule(0.012, 0.1), FunLooks.metal(FunLooks.CHROME), sink + Vector3(-0.08, 0.1, 0), Vector3(0, 0, 1.2))
	part(FunLooks.box(Vector3(0.01, 0.4, 0.32)), FunLooks.mat(Color(0.8, 0.9, 1), 0.02, 0.9), Vector3(-0.48, 1.45, 0.38))
	var bulb := OmniLight3D.new()
	bulb.position = Vector3(0, SIZE.y - 0.25, 0)
	bulb.light_energy = 0.6
	bulb.omni_range = 1.5
	rig.add_child(bulb)


func _refresh(_fx: String) -> void:
	var open: bool = state.open
	_door.rotation.y = -1.35 if open else 0.0
	_door_shape.disabled = open
	_sign.text = "VACANT" if open else "OCCUPIED\n(probably)"
	_sign.modulate = Color(0.4, 1, 0.4) if open else Color(1, 0.35, 0.35)
	for a in rig.get_children():
		if a is Interactable and (a as Interactable).args[1] == "door":
			(a as Interactable).prompt = "Close the lavatory door [E]" if open else "Open the lavatory door [E]"


func _play(fx: String, _args: Array) -> void:
	if fx != "flush":
		return
	var at := global_point(Vector3(-0.2, 0.5, -0.1))
	FunFx.burst(world, at, [Color(0.4, 0.75, 1, 0.9), Color(0.85, 0.95, 1, 0.8)], 40, 3.0, 0.05, Vector3.UP, 50.0, 1.0)
	FunFx.popup(world, at + Vector3(0, 0.6, 0), "FWOOOSH", Color(0.5, 0.8, 1), 90)
	var tw := _bowl_lid.create_tween()
	tw.tween_property(_bowl_lid, "rotation:z", -0.4, 0.1)
	for i in 4:
		tw.tween_property(_bowl_lid, "rotation:z", 0.1 if i % 2 == 0 else -0.25, 0.15)
	tw.tween_property(_bowl_lid, "rotation:z", 0.1, 0.2)


func act(peer: int, verb: String, _args: Array) -> void:
	match verb:
		"door":
			state.open = not bool(state.open)
			push_state()
		"flush":
			if _flush_t > 0.0:
				return
			_flush_t = FLUSH_TIME
			state.flushes = int(state.flushes) + 1
			push_state("flush")
			world.shake_all(0.15)
			world.say(world.display_name(peer), FLUSH_LINES.pick_random(), 2.5)


func _physics_process(dt: float) -> void:
	if not world.is_server() or _flush_t <= 0.0:
		return
	_flush_t -= dt
	var bowl := global_point(Vector3(-0.2, 0.5, -0.1))
	for o: Node3D in world.objects.values():
		var b := o as RigidBody3D
		if b == null or b.freeze:
			continue
		var to := bowl - b.global_position
		if to.length() < FLUSH_REACH and to.length() > 0.15:
			b.apply_central_force(to.normalized() * 35.0 * minf(b.mass, 5.0) * (1.0 - to.length() / FLUSH_REACH))
	_push_t -= dt
	if _push_t <= 0.0:
		_push_t = 0.2
		for peer: int in world.players:
			var to: Vector3 = bowl - (world.players[peer] as Player).global_position
			if to.length() < FLUSH_REACH:
				world.push_player(peer, to.normalized() * 1.6 * (1.0 - to.length() / FLUSH_REACH))
