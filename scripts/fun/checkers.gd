class_name FunCheckers
extends FunStation
## A checkers board with 12 + 12 loose physical pieces (kind "checker"). Move pieces by hand
## (pick up [E], drop [E]); they slide when the plane tilts. [E] on the board's edge re-racks
## every piece; [E] on the table corner flips the board in a rage.
## Local frame: the origin is the board centre on the tabletop.

const SQ := 0.05
const THICK := 0.03
const RAGE := ["*flips the board*", "THIS GAME IS RIGGED", "I was winning anyway.", "*checkers everywhere*"]

var pieces: Array[int] = []      ## Host: net ids of this board's checkers.


func _build() -> void:
	var dark := FunLooks.mat(Color(0.15, 0.13, 0.12), 0.6)
	var light := FunLooks.mat(Color(0.93, 0.85, 0.68), 0.6)
	FunLooks.rounded_box(rig, Vector3(SQ * 8 + 0.06, THICK, SQ * 8 + 0.06), 0.012, FunLooks.mat(FunLooks.WOOD, 0.4),
		Vector3(0, THICK / 2, 0))
	for r in 8:
		for c in 8:
			part(FunLooks.box(Vector3(SQ, 0.004, SQ)), dark if (r + c) % 2 == 0 else light,
				Vector3((c - 3.5) * SQ, THICK + 0.002, (r - 3.5) * SQ))
	collider(Vector3(SQ * 8 + 0.06, THICK, SQ * 8 + 0.06), Vector3(0, THICK / 2, 0))
	label("CHECKERS", Vector3(0, THICK + 0.005, SQ * 4 + 0.02), 14, Color(1, 0.9, 0.6), Vector3(-PI / 2, 0, 0))
	area(Vector3(SQ * 8 + 0.1, 0.06, 0.08), Vector3(0, THICK, SQ * 4 + 0.06), "Re-rack the checkers [E]", "rack")
	area(Vector3(0.12, 0.1, 0.12), Vector3(SQ * 4 + 0.14, 0.02, -SQ * 4 - 0.05), "Flip the board! [E]", "flip")
	part(FunLooks.cyl(0.04, 0.04, 0.01, 12), FunLooks.mat(Color(0.9, 0.2, 0.2), 0.4), Vector3(SQ * 4 + 0.14, 0.005, -SQ * 4 - 0.05))
	label("RAGE\nQUIT", Vector3(SQ * 4 + 0.14, 0.015, -SQ * 4 - 0.05), 10, Color(1, 1, 1), Vector3(-PI / 2, 0, 0))


## Host. Start squares (local) for piece i: 0..11 red on rows 0-2, 12..23 black on rows 5-7.
func start_pos(i: int) -> Vector3:
	var side := i / 12
	var k := i % 12
	var r := k / 4 + (5 if side == 1 else 0)
	var c := (k % 4) * 2 + (1 if r % 2 == 0 else 0)
	return Vector3((c - 3.5) * SQ, THICK + 0.004 + 0.012, (r - 3.5) * SQ)


## Host. Puts every checker back on its square, spawning any that went missing.
func rack() -> void:
	var up := world.plane.global_basis
	for i in 24:
		var at := global_point(start_pos(i))
		var id: int = pieces[i] if i < pieces.size() else 0
		var body := world.get_object(id) as RigidBody3D
		if body == null or world.holders.values().has(id):
			body = world.spawn_object("checker", Transform3D(up, at), {"side": i / 12}) as RigidBody3D
			if i < pieces.size():
				pieces[i] = World.net_id(body)
			else:
				pieces.append(World.net_id(body))
			continue
		body.global_transform = Transform3D(up, at)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO


func _play(fx: String, _args: Array) -> void:
	if fx == "flip":
		FunFx.popup(world, global_point(Vector3(0, 0.3, 0)), "TABLE FLIP!", Color(1, 0.4, 0.3), 80)


func act(peer: int, verb: String, _args: Array) -> void:
	match verb:
		"rack":
			rack()
			world.notify(peer, "Checkers re-racked. Red moves first.")
		"flip":
			for id in pieces:
				var b := world.get_object(id) as RigidBody3D
				if b and not world.holders.values().has(id):
					b.apply_central_impulse(world.plane.global_basis.y * randf_range(0.08, 0.15)
						+ Vector3(randf_range(-0.05, 0.05), 0, randf_range(-0.05, 0.05)))
					b.angular_velocity = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
			push_state("flip")
			world.say(world.display_name(peer), RAGE.pick_random(), 2.0)
