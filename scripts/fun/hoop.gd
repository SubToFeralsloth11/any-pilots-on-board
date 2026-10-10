extends FunStation
## A basketball hoop bolted to a bulkhead with a score counter on the backboard.
## The host counts a basket when a "basketball" drops down through the rim.
## Local frame: the backboard faces +Z; the origin is on the wall at floor level.

const RIM := Vector3(0, 1.75, 0.32)
const RIM_R := 0.22
const LINES := ["SWISH! %s scores!", "%s with the slam dunk! (at 30,000 feet)", "Nothing but net, %s!",
	"%s: from downtown!", "BUCKETS! %s is on fire!"]

var _score_label: Label3D
var _net: Node3D
var _prev := {}       ## Host: ball net_id -> height relative to the rim last frame.


func default_state() -> Dictionary:
	return {"score": 0, "streak": 0, "best": 0, "last": ""}


func _build() -> void:
	var white := FunLooks.mat(Color(0.97, 0.97, 0.97), 0.3)
	var red := FunLooks.mat(Color(0.9, 0.15, 0.15), 0.4)
	var orange := FunLooks.metal(Color(1.0, 0.45, 0.1))
	FunLooks.rounded_box(rig, Vector3(0.8, 0.52, 0.04), 0.02, white, Vector3(0, 2.0, 0.04))
	for edge in [[Vector3(0.24, 0.015, 0.01), Vector3(0, 1.88, 0.065)], [Vector3(0.24, 0.015, 0.01), Vector3(0, 2.04, 0.065)],
			[Vector3(0.015, 0.16, 0.01), Vector3(-0.12, 1.96, 0.065)], [Vector3(0.015, 0.16, 0.01), Vector3(0.12, 1.96, 0.065)]]:
		part(FunLooks.box(edge[0]), red, edge[1])
	collider(Vector3(0.8, 0.52, 0.05), Vector3(0, 2.0, 0.04))
	# Bracket and rim.
	part(FunLooks.box(Vector3(0.14, 0.04, 0.1)), orange, Vector3(0, RIM.y - 0.02, 0.1))
	part(FunLooks.torus(RIM_R - 0.012, RIM_R + 0.012), orange, RIM)
	for i in 8:
		var a := i * TAU / 8
		collider(Vector3(0.03, 0.03, 0.09), RIM + Vector3(cos(a), 0, sin(a)) * RIM_R, Basis(Vector3.UP, -a))
	# Net: shrinking rings joined by strings, gently swaying.
	_net = Node3D.new()
	_net.position = RIM
	rig.add_child(_net)
	var cord := FunLooks.mat(Color(1, 1, 1, 0.85), 0.8)
	for i in 3:
		var r := RIM_R - 0.03 * (i + 1)
		part(FunLooks.torus(r - 0.004, r + 0.004), cord, Vector3(0, -0.09 * (i + 1), 0), Vector3.ZERO, Vector3.ONE, _net)
	for i in 10:
		var a := i * TAU / 10
		var top := Vector3(cos(a), 0, sin(a)) * RIM_R
		var bottom := Vector3(cos(a + 0.3), 0, sin(a + 0.3)) * (RIM_R - 0.09) + Vector3(0, -0.27, 0)
		var s := part(FunLooks.cyl(0.004, 0.004, top.distance_to(bottom), 4), cord, (top + bottom) / 2,
			Vector3.ZERO, Vector3.ONE, _net)
		s.basis = Basis(_perp(bottom - top), (top - bottom).normalized(), (bottom - top).cross(_perp(bottom - top)).normalized())
	_score_label = label("", Vector3(0, 2.17, 0.07), 34, Color(0.9, 0.15, 0.15))
	_score_label.outline_modulate = Color(1, 1, 1, 1)
	label("SKY HOOPS", Vector3(0, 2.32, 0.07), 26, Color(0.13, 0.36, 0.9))


func _perp(v: Vector3) -> Vector3:
	return v.cross(Vector3.FORWARD if absf(v.normalized().z) < 0.9 else Vector3.RIGHT).normalized()


func _refresh(_fx: String) -> void:
	_score_label.text = "BUCKETS %d   STREAK %d   BEST %d" % [state.score, state.streak, state.best]


func _play(fx: String, args: Array) -> void:
	if fx != "score":
		return
	var at := global_point(RIM)
	FunFx.burst(world, at, FunLooks.CONFETTI, 50, 3.5, 0.06, Vector3.UP, 90.0, 1.6, Vector3(0, -3, 0), true)
	FunFx.popup(world, at + Vector3(0, 0.3, 0), "+%d" % int(args[0]), Color(1, 0.6, 0.2), 80)
	_net.scale = Vector3(1.15, 1.4, 1.15)
	var tw := _net.create_tween()
	tw.tween_property(_net, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _physics_process(_dt: float) -> void:
	if not world.is_server():
		return
	var inv := (world.plane.global_transform * local_xform()).affine_inverse()
	var seen := {}
	for id: int in world.objects:
		var ball := world.objects[id] as FunToy
		if ball == null or ball.kind != "basketball":
			continue
		seen[id] = true
		var p := inv * ball.global_position - RIM
		var was: float = _prev.get(id, 0.0)
		_prev[id] = p.y
		if was > 0.0 and p.y <= 0.0 and Vector2(p.x, p.z).length() < RIM_R - 0.03 and ball.linear_velocity.length() < 25.0:
			_score(ball.last_peer)
	for id: int in _prev.keys():
		if not seen.has(id):
			_prev.erase(id)


func _score(peer: int) -> void:
	var who := world.display_name(peer) if peer != 0 else "Gravity"
	var pts := 2
	state.score = int(state.score) + pts
	state.streak = int(state.streak) + 1 if state.last == who else 1
	state.best = maxi(int(state.best), int(state.streak))
	state.last = who
	world.say("Sky Hoops", LINES.pick_random() % who, 2.5)
	push_state("score", [pts])
