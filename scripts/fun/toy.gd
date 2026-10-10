class_name FunToy
extends RigidBody3D
## Base for every loose fun-module object (balls, checkers, dice, darts, weapons): a networked,
## grabbable prop-layer rigid body that remembers who handled it last. Subclasses build their
## look under `vis` and their collision shapes in _configure(). Afterwards the static pieces of
## `vis` are merged into one cached mesh (PropLooks.merge_static); direct children of `vis` with
## an explicit name (e.g. the drill "Bit") stay separate so they can animate.

const PropLooks := preload("res://scripts/props/prop_looks.gd")

var world: World
var kind := ""
var display := "thing"         ## Name used in prompts and announcements.
var hint := ""                 ## Toast shown to whoever picks it up.
var holder := 0                ## Host: peer currently holding it.
var last_peer := 0             ## Host: last peer who grabbed, threw or punched it.
var vis: Node3D                ## Visual root (weapons animate it).


func _init(w: World, k: String, extra: Dictionary = {}) -> void:
	world = w
	kind = k
	collision_layer = Layers.PROP
	collision_mask = Layers.WORLD | Layers.PLAYER | Layers.PROP | Layers.NPC
	linear_damp = 0.08
	angular_damp = 0.6
	can_sleep = true
	add_to_group("grabbable")
	vis = Node3D.new()
	add_child(vis)
	_configure(extra)
	var keep: Array = []
	for c in vis.get_children():
		if not String(c.name).begins_with("@"):
			keep.append(c)
	PropLooks.merge_static(vis, keep, "fun/" + _look_key(extra))


## Sets mass, physics material, shapes and visuals. Overridden per kind.
func _configure(_extra: Dictionary) -> void:
	pass


## Identifies everything in `extra` that changes the look (merged-mesh cache key).
func _look_key(extra: Dictionary) -> String:
	return "%s/%s" % [kind, extra]


func add_shape(shape: Shape3D, xform := Transform3D.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xform
	add_child(cs)


func part(mesh: Mesh, material: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	return FunLooks.part(vis, mesh, material, pos, rot, scl)


func get_prompt() -> String:
	return "Pick up the %s [E]" % display


func on_grabbed(peer: int) -> void:
	holder = peer
	last_peer = peer
	if hint != "":
		world.notify(peer, hint)


func on_released() -> void:
	holder = 0


func on_thrown(peer: int) -> void:
	last_peer = peer


func on_punched(peer: int, _dir: Vector3) -> void:
	last_peer = peer
