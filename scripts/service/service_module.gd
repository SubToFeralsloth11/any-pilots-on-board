extends Node
## Cabin service: four galley stations on the front counters (oven, juice fountain, coffee
## machine, blanket bin) built identically on every peer in setup(). [E] on a station asks the
## host to prepare that item; after a short wait it pops out on the counter as a grabbable
## "service_item" (service_item.gd) that crew carry to passengers and serve with [RMB].

const ServiceItem := preload("res://scripts/service/service_item.gd")
const ServiceLooks := preload("res://scripts/service/service_looks.gd")
const Fx := preload("res://scripts/props/fx.gd")
const PropLooks := preload("res://scripts/props/prop_looks.gd")

const TOP := 1.045                     ## Galley worktop height (airliner.gd _build_galley).
## item -> [station centre on the worktop (plane-local), size, prep seconds, prompt]
const STATIONS := {
	"meal": [Vector3(-2.28, TOP, -9.68), Vector3(0.44, 0.38, 0.34), 3.0, "Heat a meal [E]"],
	"drink": [Vector3(-1.93, TOP, -9.72), Vector3(0.22, 0.42, 0.24), 1.2, "Pour a juice [E]"],
	"coffee": [Vector3(-1.68, TOP, -9.72), Vector3(0.22, 0.4, 0.26), 2.0, "Brew a coffee [E]"],
	"blanket": [Vector3(2.28, TOP, -9.64), Vector3(0.4, 0.24, 0.36), 0.4, "Grab a blanket [E]"],
}
const OUT_DZ := 0.28                   ## Items appear this far in front of the station.
const MAX_LOOSE := 4                   ## Per item kind lying around the plane.
const REACH := 2.5
const STEEL := Color(0.78, 0.8, 0.84)
const DARK := Color(0.12, 0.13, 0.16)

var world: World
var _cooking := {}                     ## Host: item -> seconds left.


func setup(w: World) -> void:
	world = w
	world.register_kind("service_item", func(extra: Dictionary) -> Node3D: return ServiceItem.new(world, "service_item", extra))
	world.register_action("dispense", _act_dispense)
	var root := Node3D.new()
	root.name = "Galley"
	world.plane.add_child(root)
	for item: String in STATIONS:
		_build_station(root, item)
	set_physics_process(world.is_server())


func _act_dispense(peer: int, args: Array) -> void:
	var item := String(args[0]) if not args.is_empty() else ""
	if not STATIONS.has(item):
		return
	var p: Player = world.players.get(peer)
	if p == null or p.global_position.distance_to(world.plane.to_global(STATIONS[item][0])) > REACH + 1.0:
		return
	if _cooking.has(item):
		world.notify(peer, "Hang on, it's coming!")
		return
	if _loose(item) >= MAX_LOOSE:
		world.notify(peer, "There are already %d out there. Serve those first!" % MAX_LOOSE)
		return
	_cooking[item] = float(STATIONS[item][2])
	_fx_all(item, false)


func _physics_process(dt: float) -> void:
	for item: String in _cooking.keys():
		_cooking[item] -= dt
		if _cooking[item] > 0.0:
			continue
		_cooking.erase(item)
		var c: Vector3 = STATIONS[item][0]
		var at := Vector3(c.x, TOP + 0.08, c.z + OUT_DZ)
		var o := world.spawn_object("service_item", world.plane.global_transform * Transform3D(Basis.IDENTITY, at),
			{"item": item}) as RigidBody3D
		if o:
			o.linear_velocity = world.plane.global_basis * Vector3(0, 0.8, 0.4)
		_fx_all(item, true)


func _loose(item: String) -> int:
	var n := 0
	for id in world.objects:
		var o: Node = world.objects[id]
		if o.get_meta("kind", "") == "service_item" and o.item == item:
			n += 1
	return n


## Host. Start/ready cue on every peer.
func _fx_all(item: String, ready: bool) -> void:
	for p in world._ready_peers:
		_rpc_fx.rpc_id(p, item, ready)
	_rpc_fx(item, ready)


@rpc("authority", "call_remote", "reliable")
func _rpc_fx(item: String, ready: bool) -> void:
	var at := world.plane.to_global(STATIONS[item][0] + Vector3(0, STATIONS[item][1].y + 0.1, 0))
	if ready:
		FunFx.popup(world, at, "DING!", Color(1, 0.9, 0.4), 60)
		Fx.sound(world, at, "clang", -6.0)
	else:
		FunFx.popup(world, at, {"meal": "heating...", "drink": "glug glug", "coffee": "brewing...",
			"blanket": "fluff!"}[item], Color(0.9, 0.95, 1), 40)


# --- Looks -----------------------------------------------------------------------------------

func _build_station(root: Node3D, item: String) -> void:
	var c: Vector3 = STATIONS[item][0]
	var size: Vector3 = STATIONS[item][1]
	var st := Node3D.new()
	st.position = c
	root.add_child(st)
	match item:
		"meal":
			_oven(st, size)
		"drink":
			_fountain(st, size)
		"coffee":
			_coffee_machine(st, size)
		"blanket":
			_blanket_bin(st, size)
	PropLooks.merge_static(st, [], "galley/" + item)
	FunLooks.collider(world.plane, size, Transform3D(Basis.IDENTITY, c + Vector3(0, size.y / 2.0, 0)))
	var a := Interactable.make(size + Vector3(0.06, 0.1, 0.12), STATIONS[item][3], "dispense", [item])
	a.position = c + Vector3(0, size.y / 2.0, 0.04)
	world.plane.add_area(a)


func _oven(r: Node3D, s: Vector3) -> void:
	FunLooks.rounded_box(r, s, 0.04, FunLooks.metal(STEEL), Vector3(0, s.y / 2, 0))
	FunLooks.rounded_box(r, Vector3(s.x - 0.12, s.y - 0.14, 0.02), 0.02, FunLooks.mat(DARK, 0.2), Vector3(-0.03, s.y / 2 - 0.02, s.z / 2 + 0.005))
	FunLooks.rounded_box(r, Vector3(s.x - 0.18, s.y - 0.22, 0.01), 0.02, FunLooks.mat(Color(1.0, 0.55, 0.15), 0.3, 0.0, 1.5),
		Vector3(-0.03, s.y / 2 - 0.02, s.z / 2 + 0.012))
	FunLooks.part(r, FunLooks.box(Vector3(0.24, 0.025, 0.03)), FunLooks.metal(Color(0.9, 0.9, 0.92)), Vector3(-0.03, s.y - 0.06, s.z / 2 + 0.03))
	for i in 2:
		FunLooks.part(r, FunLooks.cyl(0.025, 0.025, 0.03, 12), FunLooks.mat(DARK, 0.4), Vector3(s.x / 2 - 0.05, 0.12 + i * 0.12, s.z / 2 + 0.01),
			Vector3(PI / 2, 0, 0))
	FunLooks.label(r, "OVEN", Vector3(-0.03, s.y + 0.06, s.z / 2 - 0.02), 22, Color(1, 0.85, 0.4))


func _fountain(r: Node3D, s: Vector3) -> void:
	FunLooks.rounded_box(r, Vector3(s.x, s.y * 0.35, s.z), 0.03, FunLooks.mat(Color(0.2, 0.45, 0.9), 0.4), Vector3(0, s.y * 0.175, 0))
	FunLooks.part(r, FunLooks.cyl(s.x * 0.45, s.x * 0.45, s.y * 0.5, 18), FunLooks.mat(Color(1.0, 0.6, 0.1, 0.75), 0.1),
		Vector3(0, s.y * 0.6, -0.02))
	FunLooks.part(r, FunLooks.sphere(s.x * 0.46, 16), FunLooks.mat(Color(0.95, 0.95, 0.97), 0.3), Vector3(0, s.y * 0.85, -0.02),
		Vector3.ZERO, Vector3(1, 0.4, 1))
	FunLooks.part(r, FunLooks.box(Vector3(0.05, 0.03, 0.08)), FunLooks.mat(DARK, 0.3), Vector3(0, s.y * 0.38, s.z / 2))
	FunLooks.label(r, "JUICE", Vector3(0, s.y + 0.06, 0), 20, Color(1, 0.7, 0.3))


func _coffee_machine(r: Node3D, s: Vector3) -> void:
	FunLooks.rounded_box(r, Vector3(s.x, s.y, s.z * 0.6), 0.03, FunLooks.mat(Color(0.75, 0.15, 0.15), 0.3), Vector3(0, s.y / 2, -s.z * 0.2))
	FunLooks.rounded_box(r, Vector3(s.x, 0.04, s.z), 0.015, FunLooks.mat(DARK, 0.4), Vector3(0, 0.02, 0))
	FunLooks.rounded_box(r, Vector3(s.x, 0.08, s.z), 0.03, FunLooks.mat(Color(0.75, 0.15, 0.15), 0.3), Vector3(0, s.y - 0.04, 0))
	FunLooks.part(r, FunLooks.cyl(0.02, 0.03, 0.05, 10), FunLooks.metal(STEEL), Vector3(0, s.y - 0.1, 0.04))
	FunLooks.part(r, FunLooks.sphere(0.02, 8), FunLooks.mat(Color(0.3, 1, 0.4), 0.3, 0.0, 2.0), Vector3(0.06, s.y * 0.7, s.z * 0.1 + 0.005))
	FunLooks.label(r, "COFFEE", Vector3(0, s.y + 0.06, 0), 20, Color(1, 0.85, 0.6))


func _blanket_bin(r: Node3D, s: Vector3) -> void:
	var wood := FunLooks.mat(FunLooks.WOOD, 0.6)
	FunLooks.rounded_box(r, Vector3(s.x, 0.03, s.z), 0.01, wood, Vector3(0, 0.015, 0))
	for sx in [-1.0, 1.0]:
		FunLooks.rounded_box(r, Vector3(0.03, s.y, s.z), 0.01, wood, Vector3(sx * (s.x / 2 - 0.015), s.y / 2, 0))
	FunLooks.rounded_box(r, Vector3(s.x, s.y, 0.03), 0.01, wood, Vector3(0, s.y / 2, -s.z / 2 + 0.015))
	for i in 3:
		var b := Node3D.new()
		b.position = Vector3(0, 0.07 + i * 0.075, 0.02)
		b.rotation.y = (i - 1) * 0.12
		r.add_child(b)
		ServiceLooks.build_parts(b, "blanket")
	FunLooks.label(r, "BLANKETS", Vector3(0, s.y + 0.06, 0), 20, Color(0.6, 0.8, 1))
