class_name FunStation
extends Node3D
## A fixed activity bolted to the plane (board game, scoreboard, machine).
##
## It is a networked object (kind "fun_station") so its state reaches late joiners:
## get_spawn_extra() carries `state`, and every host change is broadcast with the "state" net
## event. The node itself stays at the world origin; its visuals (`rig`) and colliders hang off
## the plane so they tilt with it. Interactables send the host action "fun_station"
## with args [net_id, verb, ...], which the Fun module routes to act().

const REACH := 3.5

var world: World
var module: FunGames
var type := ""
var state := {}
var rig: Node3D                 ## Plane-attached visual root; local origin = station position.
var _pos := Vector3.ZERO
var _yaw := 0.0
var _shapes: Array[CollisionShape3D] = []


func _init(w: World, fun: FunGames, extra: Dictionary) -> void:
	world = w
	module = fun
	type = extra.get("type", "")
	_pos = extra.get("pos", Vector3.ZERO)
	_yaw = float(extra.get("yaw", 0.0))
	var s: Dictionary = extra.get("state", {})
	state = s.duplicate(true) if not s.is_empty() else default_state()


func _ready() -> void:
	rig = Node3D.new()
	rig.name = "Fun_" + type
	rig.transform = local_xform()
	world.plane.add_child(rig)
	module.stations[type] = self
	_build()
	_refresh("")


func _exit_tree() -> void:
	if is_instance_valid(rig):
		rig.queue_free()
	for s in _shapes:
		if is_instance_valid(s):
			s.queue_free()


## Plane-local transform of the station.
func local_xform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, _yaw), _pos)


## Station-local point to world space.
func global_point(local: Vector3) -> Vector3:
	return world.plane.to_global(local_xform() * local)


## Host. True when the player is close enough to operate the station.
func near(peer: int) -> bool:
	var p: Player = world.players.get(peer)
	return p != null and p.global_position.distance_to(global_point(Vector3.ZERO)) <= REACH + 1.5


func get_spawn_extra() -> Dictionary:
	return {"type": type, "pos": _pos, "yaw": _yaw, "state": state}


## Host only. Broadcasts the whole state; `fx` names a one-shot cosmetic for _play().
func push_state(fx := "", fx_args: Array = []) -> void:
	world.object_event(World.net_id(self), "state", [state, fx, fx_args])


func on_net_event(event: String, args: Array) -> void:
	if event == "state":
		state = args[0]
		_refresh(args[1])
		if args[1] != "":
			_play(args[1], args[2])


## Adds an [E] volume that requests `verb` on this station.
func area(size: Vector3, pos: Vector3, prompt: String, verb: String, extra: Array = []) -> Interactable:
	var a := Interactable.make(size, prompt, "fun_station", [World.net_id(self), verb] + extra)
	a.position = pos
	rig.add_child(a)
	return a


## Adds a sit-down spot (local seat point at cushion height).
func seat(pos: Vector3, size := Vector3(0.4, 0.4, 0.4), prompt := "Sit down [E]") -> void:
	var a := Interactable.make(size, prompt, "sit")
	a.local_only = true
	a.set_meta("seat", local_xform() * pos)
	a.position = pos + Vector3(0, 0.1, 0)
	rig.add_child(a)


## Collision box in station-local space.
func collider(size: Vector3, center: Vector3, basis := Basis.IDENTITY) -> CollisionShape3D:
	var cs := FunLooks.collider(world.plane, size, local_xform() * Transform3D(basis, center))
	_shapes.append(cs)
	return cs


func part(mesh: Mesh, material: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE,
		parent: Node3D = null) -> MeshInstance3D:
	return FunLooks.part(parent if parent else rig, mesh, material, pos, rot, scl)


func label(text: String, pos: Vector3, size := 32, color := Color.WHITE, rot := Vector3.ZERO) -> Label3D:
	return FunLooks.label(rig, text, pos, size, color, rot)


# --- Overridables ----------------------------------------------------------------------------

func default_state() -> Dictionary:
	return {}


## Builds visuals, colliders and interactables (every peer).
func _build() -> void:
	pass


## Makes the visuals match `state` (every peer).
func _refresh(_fx: String) -> void:
	pass


## One-shot cosmetic named by push_state (every peer).
func _play(_fx: String, _args: Array) -> void:
	pass


## Host only: a player pressed one of this station's interactables.
func act(_peer: int, _verb: String, _args: Array) -> void:
	pass
