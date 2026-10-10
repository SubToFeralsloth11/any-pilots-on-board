extends FunWeapon
## Tools that break the plane. Each hit is a host raycast from the holder's eye against
## WORLD | PROP | NPC | PLAYER: the hull, walls, windows and wings take world.damage_plane_at(),
## players get knocked back, passengers fall over, props get whacked (and smashed if breakable).
##
## Kinds: fire_axe, sledgehammer, crowbar, power_drill, flare_gun (fires a "flare" that sets
## engines on fire), blunderbuss (confetti shotgun that blows out windows).

const TOOLS := {
	"fire_axe": {"name": "fire axe", "mass": 2.2, "cooldown": 0.8, "reach": 2.3, "damage": 0.08, "push": 8.0,
		"hint": "[RMB] CHOP. Walls, windows, wings, friendships. Labelled 'IN CASE OF FIRE', not 'TO CAUSE FIRE'."},
	"sledgehammer": {"name": "sledgehammer", "mass": 6.0, "cooldown": 1.4, "reach": 2.1, "damage": 0.13, "push": 13.0,
		"hint": "[RMB] SMASH. The plane is technically made of things you can hit."},
	"crowbar": {"name": "crowbar", "mass": 1.6, "cooldown": 0.55, "reach": 2.0, "damage": 0.05, "push": 6.0,
		"hint": "[RMB] pry, whack and generally vandalise. Windows pop right out."},
	"power_drill": {"name": "power drill", "mass": 1.4, "cooldown": 0.12, "reach": 1.5, "damage": 0.02, "push": 2.0,
		"hint": "Spam [RMB] to drill holes in the plane. Why would you. Why."},
	"flare_gun": {"name": "flare gun", "mass": 0.9, "cooldown": 1.8, "reach": 0.0, "damage": 0.0, "push": 0.0,
		"hint": "[RMB] fires a flare. Do NOT shoot it at an engine. (Through a broken window. Hypothetically.)"},
	"blunderbuss": {"name": "confetti blunderbuss", "mass": 3.0, "cooldown": 2.0, "reach": 7.0, "damage": 0.035, "push": 7.0,
		"hint": "[RMB] Party shotgun. Seven barrels of confetti. Windows hate it."},
}
const MASK := Layers.WORLD | Layers.PROP | Layers.NPC | Layers.PLAYER
const PELLETS := 7
const CRUNCH := ["*CRUNCH*", "*structural noises*", "That's load-bearing, probably.", "*metal screams*",
	"The plane felt that.", "Whoops. That was a rib."]
const SPARKS := [Color(1, 0.85, 0.3), Color(1, 0.55, 0.1), Color(1, 1, 0.8)]


func _configure(_extra: Dictionary) -> void:
	var spec: Dictionary = TOOLS[kind]
	display = spec.name
	hint = spec.hint
	mass = spec.mass
	physics_material_override = FunLooks.phys(0.5, 0.1)
	angular_damp = 1.0
	match kind:
		"fire_axe": _build_axe()
		"sledgehammer": _build_sledge()
		"crowbar": _build_crowbar()
		"power_drill": _build_drill()
		"flare_gun": _build_flare_gun()
		"blunderbuss": _build_blunderbuss()


func cooldown() -> float:
	return TOOLS[kind].cooldown


func _muzzle() -> Vector3:
	var z := {"fire_axe": -0.42, "sledgehammer": -0.45, "crowbar": -0.36, "power_drill": -0.3,
		"flare_gun": -0.22, "blunderbuss": -0.55}
	return global_transform * Vector3(0, 0, z[kind])


# --- Looks -----------------------------------------------------------------------------------

func _handle(length: float, z: float, color: Color, grip: Color) -> void:
	part(FunLooks.cyl(0.02, 0.024, length, 12), FunLooks.mat(color, 0.55), Vector3(0, 0, z), Vector3(PI / 2, 0, 0))
	part(FunLooks.capsule(0.028, 0.16), FunLooks.mat(grip, 0.9), Vector3(0, 0, z + length / 2 - 0.06), Vector3(PI / 2, 0, 0))
	for i in 3:
		part(FunLooks.torus(0.026, 0.032), FunLooks.mat(grip.darkened(0.3), 0.9),
			Vector3(0, 0, z + length / 2 - 0.11 + i * 0.045), Vector3(PI / 2, 0, 0))


func _build_axe() -> void:
	_box_shape(Vector3(0.24, 0.07, 0.86), Vector3(0.04, 0, -0.02))
	_handle(0.8, 0.0, Color(0.9, 0.12, 0.12), Color(0.15, 0.15, 0.17))
	var steel := FunLooks.metal(Color(0.7, 0.72, 0.76))
	FunLooks.rounded_box(vis, Vector3(0.06, 0.05, 0.1), 0.015, FunLooks.metal(Color(0.85, 0.15, 0.12)), Vector3(0, 0, -0.38))
	part(FunLooks.prism(Vector3(0.2, 0.17, 0.035)), steel, Vector3(0.11, 0, -0.38), Vector3(PI / 2, 0, -PI / 2))
	part(FunLooks.box(Vector3(0.01, 0.03, 0.2)), FunLooks.metal(Color(0.95, 0.95, 1)), Vector3(0.205, 0, -0.38))
	part(FunLooks.prism(Vector3(0.08, 0.1, 0.03)), steel, Vector3(-0.07, 0, -0.38), Vector3(PI / 2, 0, PI / 2))
	FunLooks.label(vis, "FIRE", Vector3(0, 0.026, -0.12), 22, Color(1, 1, 1), Vector3(-PI / 2, 0, PI / 2))


func _build_sledge() -> void:
	_box_shape(Vector3(0.14, 0.14, 0.95), Vector3(0, 0, -0.02))
	_handle(0.9, 0.04, FunLooks.WOOD_LIGHT, Color(0.95, 0.75, 0.1))
	var iron := FunLooks.mat(Color(0.25, 0.26, 0.3), 0.35, 0.7)
	part(FunLooks.cyl(0.07, 0.07, 0.26, 18), iron, Vector3(0, 0, -0.42), Vector3(0, 0, PI / 2))
	for sx in [-1.0, 1.0]:
		part(FunLooks.cyl(0.074, 0.074, 0.02, 18), FunLooks.metal(FunLooks.CHROME), Vector3(sx * 0.125, 0, -0.42),
			Vector3(0, 0, PI / 2))
		part(FunLooks.sphere(0.066, 14), iron, Vector3(sx * 0.13, 0, -0.42), Vector3.ZERO, Vector3(0.3, 1, 1))
	part(FunLooks.torus(0.025, 0.04), FunLooks.metal(FunLooks.BRASS), Vector3(0, 0, -0.34), Vector3(PI / 2, 0, 0))


func _build_crowbar() -> void:
	_box_shape(Vector3(0.06, 0.12, 0.8), Vector3(0, 0.02, -0.02))
	var red := FunLooks.mat(Color(0.85, 0.1, 0.12), 0.3, 0.4)
	part(FunLooks.cyl(0.016, 0.016, 0.62, 6), red, Vector3(0, 0, 0), Vector3(PI / 2, 0, 0))
	part(FunLooks.torus(0.05, 0.068), red, Vector3(0, 0.055, -0.31), Vector3(0, 0, PI / 2), Vector3(1, 1, 1))
	part(FunLooks.prism(Vector3(0.04, 0.06, 0.012)), FunLooks.metal(FunLooks.CHROME), Vector3(0, 0.105, -0.27),
		Vector3(0, 0, 0))
	part(FunLooks.prism(Vector3(0.035, 0.07, 0.012)), FunLooks.metal(FunLooks.CHROME), Vector3(0, 0.01, 0.34),
		Vector3(-PI / 2 - 0.3, 0, 0))
	part(FunLooks.capsule(0.022, 0.18), FunLooks.mat(FunLooks.INK, 0.9), Vector3(0, 0, 0.18), Vector3(PI / 2, 0, 0))


func _build_drill() -> void:
	_box_shape(Vector3(0.09, 0.28, 0.34), Vector3(0, -0.05, 0))
	var yellow := FunLooks.mat(Color(1, 0.78, 0.1), 0.45)
	var black := FunLooks.mat(Color(0.12, 0.12, 0.14), 0.7)
	part(FunLooks.capsule(0.05, 0.26), yellow, Vector3(0, 0.03, 0.0), Vector3(PI / 2, 0, 0))
	part(FunLooks.cyl(0.04, 0.05, 0.06, 16), black, Vector3(0, 0.03, -0.15), Vector3(PI / 2, 0, 0))
	part(FunLooks.cyl(0.022, 0.03, 0.05, 12), FunLooks.metal(FunLooks.CHROME), Vector3(0, 0.03, -0.2), Vector3(PI / 2, 0, 0))
	var bit := part(FunLooks.cyl(0.003, 0.008, 0.12, 8), FunLooks.metal(Color(0.85, 0.85, 0.9)), Vector3(0, 0.03, -0.27),
		Vector3(-PI / 2, 0, 0))
	bit.name = "Bit"
	part(FunLooks.capsule(0.032, 0.17), black, Vector3(0, -0.1, 0.06), Vector3(0.25, 0, 0))
	FunLooks.rounded_box(vis, Vector3(0.09, 0.06, 0.12), 0.02, black, Vector3(0, -0.19, 0.08))
	part(FunLooks.box(Vector3(0.02, 0.035, 0.03)), FunLooks.mat(Color(0.9, 0.15, 0.1)), Vector3(0, -0.04, -0.03))
	for i in 4:
		part(FunLooks.box(Vector3(0.092, 0.006, 0.02)), black, Vector3(0, 0.05, 0.06 + i * 0.025))


func _build_flare_gun() -> void:
	_box_shape(Vector3(0.08, 0.2, 0.3), Vector3(0, -0.04, 0))
	var orange := FunLooks.mat(Color(1, 0.4, 0.05), 0.4)
	part(FunLooks.cyl(0.035, 0.035, 0.24, 16), orange, Vector3(0, 0.02, -0.06), Vector3(PI / 2, 0, 0))
	part(FunLooks.torus(0.03, 0.042), FunLooks.mat(FunLooks.INK), Vector3(0, 0.02, -0.18), Vector3(PI / 2, 0, 0))
	FunLooks.rounded_box(vis, Vector3(0.06, 0.07, 0.1), 0.02, orange, Vector3(0, 0.0, 0.08))
	part(FunLooks.capsule(0.028, 0.15), orange, Vector3(0, -0.1, 0.1), Vector3(0.35, 0, 0))
	part(FunLooks.torus(0.022, 0.03), FunLooks.mat(FunLooks.INK), Vector3(0, -0.05, 0.03), Vector3(0, 0, PI / 2))
	part(FunLooks.cyl(0.008, 0.012, 0.04), FunLooks.mat(FunLooks.INK), Vector3(0, 0.06, 0.12), Vector3(0.6, 0, 0))
	FunLooks.label(vis, "SOS", Vector3(0.037, 0.0, 0.08), 18, Color(1, 1, 1), Vector3(0, PI / 2, 0))


func _build_blunderbuss() -> void:
	_box_shape(Vector3(0.14, 0.2, 0.9), Vector3(0, -0.02, 0.05))
	var brass := FunLooks.metal(FunLooks.BRASS)
	part(FunLooks.cyl(0.11, 0.035, 0.55, 18), brass, Vector3(0, 0.02, -0.22), Vector3(-PI / 2, 0, 0))
	part(FunLooks.torus(0.1, 0.12), brass, Vector3(0, 0.02, -0.5), Vector3(PI / 2, 0, 0))
	for i in PELLETS:
		var a := i * TAU / PELLETS
		part(FunLooks.sphere(0.018, 6), FunLooks.mat(FunLooks.CONFETTI[i % FunLooks.CONFETTI.size()], 0.4, 0.0, 0.6),
			Vector3(cos(a) * 0.06, 0.02 + sin(a) * 0.06, -0.49))
	FunLooks.rounded_box(vis, Vector3(0.07, 0.1, 0.42), 0.03, FunLooks.mat(FunLooks.WOOD, 0.5), Vector3(0, -0.03, 0.25),
		Vector3(-0.15, 0, 0))
	part(FunLooks.torus(0.02, 0.03), brass, Vector3(0, -0.06, 0.05), Vector3(0, 0, PI / 2))
	part(FunLooks.capsule(0.012, 0.06), brass, Vector3(0, 0.07, 0.04), Vector3(0.5, 0, 0))
	for i in 2:
		part(FunLooks.torus(0.036, 0.046), brass, Vector3(0, 0.02, -0.05 + i * 0.1), Vector3(PI / 2, 0, 0))


# --- Host ------------------------------------------------------------------------------------

func _fire(peer: int, origin: Vector3, dir: Vector3) -> void:
	var spec: Dictionary = TOOLS[kind]
	var id := World.net_id(self)
	match kind:
		"flare_gun":
			var muzzle := _muzzle()
			var flare := world.spawn_object("flare", Transform3D(Basis.IDENTITY, muzzle), {}) as FunToy
			if flare:
				flare.last_peer = peer
				flare.linear_velocity = dir * 24.0
			world.object_event(id, "fx", ["flare", muzzle, dir])
			world.push_player(peer, -dir * 2.0)
		"blunderbuss":
			var hull_hits := 0
			for i in PELLETS:
				var spread := dir.rotated(Vector3.UP, randf_range(-0.14, 0.14))
				spread = spread.rotated(spread.cross(Vector3.UP).normalized(), randf_range(-0.1, 0.1))
				if _strike(peer, origin, spread, spec, 1.0 / PELLETS * 2.0) == "plane":
					hull_hits += 1
			world.object_event(id, "fx", ["blunder", _muzzle(), dir])
			world.push_player(peer, -dir * 11.0 + Vector3(0, 2.5, 0))
			world.shake_all(0.25)
			if hull_hits > 2:
				world.say(world.display_name(peer), "Happy birthday, plane!", 2.0)
		_:
			world.object_event(id, "swing", [0.4 if kind == "power_drill" else 1.2])
			var what := _strike(peer, origin, dir, spec, 1.0)
			if what == "":
				world.object_event(id, "fx", ["whiff", _muzzle(), dir])
			elif what == "plane" and kind != "power_drill" and randf() < 0.35:
				world.say(world.display_name(peer), CRUNCH.pick_random(), 2.0)


## One hit-scan along dir. Returns "plane", "player", "npc", "prop" or "" for a miss.
func _strike(peer: int, origin: Vector3, dir: Vector3, spec: Dictionary, share: float) -> String:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * float(spec.reach), MASK)
	var excl: Array[RID] = [get_rid()]
	var me: Player = world.players.get(peer)
	if me:
		excl.append(me.get_rid())
	q.exclude = excl
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return ""
	var at: Vector3 = hit.position
	var body: Object = hit.collider
	var push := float(spec.push) * share
	var id := World.net_id(self)
	if body is Airliner:
		var part_name := world.damage_plane_at(at, float(spec.damage) * share)
		world.object_event(id, "fx", ["chunk", at, -dir, part_name])
		world.add_stat("things_broken")
		return "plane"
	if body is Player:
		world.push_player((body as Player).peer_id, (dir * Vector3(1, 0, 1)).normalized() * push + Vector3(0, push * 0.4, 0))
		world.object_event(id, "hit", [at])
		return "player"
	var rb := body as RigidBody3D
	if rb == null:
		return ""
	rb.apply_impulse((dir + Vector3(0, 0.3, 0)) * clampf(rb.mass * push * 0.6, 1.0, 150.0), at - rb.global_position)
	if rb.has_method("on_punched"):
		rb.on_punched(peer, dir)
	if share >= 1.0 and rb.has_method("smash"):
		rb.call("smash", peer)
	world.object_event(id, "hit", [at])
	return "npc" if rb.is_in_group("npc") else "prop"


# --- Cosmetics -------------------------------------------------------------------------------

func on_net_event(event: String, args: Array) -> void:
	if event == "hit":
		var word: String = {"fire_axe": "CHOP!", "sledgehammer": "WHAM!!", "crowbar": "CLANG!",
			"power_drill": "BZZZT", "blunderbuss": "POP!"}.get(kind, "POW!")
		FunFx.popup(world, args[0], word, Color(1, 0.8, 0.2), 80)
		return
	if event == "fx" and args[0] in ["chunk", "flare", "blunder"]:
		var at: Vector3 = args[1]
		var dir: Vector3 = args[2]
		match args[0]:
			"chunk":
				FunFx.burst(world, at, SPARKS, 18, 4.0, 0.03, dir, 50.0, 0.6)
				FunFx.burst(world, at, [Color(0.7, 0.7, 0.72), Color(0.95, 0.95, 0.97)], 8, 2.5, 0.05, dir, 60.0, 1.2)
				var word: String = {"fire_axe": "CHUNK!", "sledgehammer": "KRUNCH!!", "crowbar": "SKREEE",
					"power_drill": "brrrrr", "blunderbuss": "pok!"}.get(kind, "CRUNCH")
				FunFx.popup(world, at - dir * 0.2, word, Color(1, 0.55, 0.2), 70 if kind != "blunderbuss" else 44)
				if kind == "power_drill":
					var bit := vis.get_node_or_null("Bit") as Node3D
					if bit:
						var tw := bit.create_tween()
						tw.tween_property(bit, "rotation:y", bit.rotation.y + TAU * 3, 0.12)
			"flare":
				FunFx.burst(world, at, [Color(1, 0.3, 0.1), Color(1, 0.8, 0.3)], 16, 3.0, 0.05, dir, 25.0, 0.5, Vector3.ZERO)
				FunFx.popup(world, at, "FWOOMP", Color(1, 0.4, 0.1), 60)
			"blunder":
				FunFx.burst(world, at, FunLooks.CONFETTI, 120, 14.0, 0.06, dir, 18.0, 2.5, Vector3(0, -2.5, 0), true)
				FunFx.burst(world, at, [Color(1, 1, 0.85), Color(0.6, 0.6, 0.6)], 14, 3.0, 0.15, dir, 35.0, 0.5, Vector3.ZERO)
				FunFx.popup(world, at + dir * 0.5, "KA-BLAMMO!", FunLooks.CONFETTI.pick_random(), 100)
		return
	super(event, args)
