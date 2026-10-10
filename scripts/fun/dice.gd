extends FunToy
## A six-sided die (kind "dice"; extra {"big": true} for the jumbo fuzzy one). Throw it [LMB],
## punch it, or let the plane tip it over: once it settles, the host reads the face pointing
## along the plane's up axis and the Fun module announces the roll.

## Local face normal -> pips. Opposite faces sum to 7.
const FACES := [[Vector3.UP, 1], [Vector3.DOWN, 6], [Vector3.RIGHT, 2], [Vector3.LEFT, 5],
	[Vector3.BACK, 3], [Vector3.FORWARD, 4]]
## Pip layout per value in face units (-1..1).
const PIPS := {
	1: [Vector2(0, 0)],
	2: [Vector2(-1, -1), Vector2(1, 1)],
	3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
	4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
	5: [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)],
	6: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)],
}
const SETTLE_TIME := 0.5

var size := 0.08
var _rolling := false
var _still := 0.0
var _roller := 0             ## Peer who rolled it (0 = the plane did).


func _configure(extra: Dictionary) -> void:
	var big := bool(extra.get("big", false))
	size = 0.24 if big else 0.08
	display = "jumbo fuzzy die" if big else "die"
	hint = "Throw it [LMB] to roll. Or just punch it."
	mass = 1.2 if big else 0.08
	physics_material_override = FunLooks.phys(0.45, 0.35)
	var b := BoxShape3D.new()
	b.size = Vector3.ONE * size
	add_shape(b)
	var body := FunLooks.mat(Color(1, 0.55, 0.8), 0.95) if big else FunLooks.mat(Color(0.98, 0.97, 0.94), 0.3)
	FunLooks.rounded_box(vis, Vector3.ONE * size, size * 0.18, body)
	var pip := FunLooks.mat(FunLooks.INK if not big else Color(0.98, 0.98, 0.98), 0.5)
	for f: Array in FACES:
		var n: Vector3 = f[0]
		var u := Vector3.RIGHT if absf(n.x) < 0.5 else Vector3.BACK
		var v := n.cross(u)
		for p: Vector2 in PIPS[f[1]]:
			var at := n * size * 0.49 + (u * p.x + v * p.y) * size * 0.26
			var flat := Vector3.ONE - n.abs() * 0.7
			part(FunLooks.sphere(size * 0.085, 8), pip, at, Vector3.ZERO, flat)


func get_prompt() -> String:
	return "Pick up the %s [E]   Roll it [LMB]" % display


func on_thrown(peer: int) -> void:
	super(peer)
	_start(peer)


func on_punched(peer: int, dir: Vector3) -> void:
	super(peer, dir)
	_start(peer)


func on_released() -> void:
	super()
	if linear_velocity.length() > 1.0:
		_start(last_peer)


func _start(peer: int) -> void:
	_rolling = true
	_roller = peer
	_still = 0.0


## The value facing the plane's ceiling.
func face_up() -> int:
	var up := world.plane.global_basis.y
	var best := -2.0
	var value := 1
	for f: Array in FACES:
		var d := (global_basis * (f[0] as Vector3)).normalized().dot(up)
		if d > best:
			best = d
			value = f[1]
	return value


func _physics_process(dt: float) -> void:
	if not world.is_server() or holder != 0:
		return
	if not _rolling and linear_velocity.length() > 2.5:
		_start(0)
	if not _rolling:
		return
	if linear_velocity.length() < 0.06 and angular_velocity.length() < 0.25:
		_still += dt
		if _still >= SETTLE_TIME:
			_rolling = false
			var v := face_up()
			world.object_event(World.net_id(self), "rolled", [v])
			(world.fun as FunGames).report_roll(_roller, v)
	else:
		_still = 0.0


func on_net_event(event: String, args: Array) -> void:
	if event == "rolled":
		FunFx.popup(world, global_position + Vector3(0, size + 0.15, 0), str(args[0]), Color(1, 0.95, 0.4), 80)
