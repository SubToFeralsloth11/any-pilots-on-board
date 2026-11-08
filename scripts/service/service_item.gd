extends FunToy
## A cabin-service item from the galley (kind "service_item", extra {"item": meal|drink|coffee|
## blanket}). Hold it, aim at the passenger who asked for it and press [RMB] to hand it over.

const ServiceLooks := preload("res://scripts/service/service_looks.gd")
const SERVE_REACH := 2.6
const SERVE_CONE := 0.82          ## cos of the aiming cone half-angle.

var item := "meal"


func _configure(extra: Dictionary) -> void:
	item = String(extra.get("item", "meal"))
	display = ServiceLooks.NAMES.get(item, item)
	hint = "Aim at the passenger asking for a %s and press [RMB] to serve it." % display
	mass = ServiceLooks.mass(item)
	physics_material_override = FunLooks.phys(0.7, 0.05)
	add_shape(ServiceLooks.shape(item))
	ServiceLooks.build(vis, item)


func _look_key(_extra: Dictionary) -> String:
	return "service/" + item


## HUD prompt while held (Player shows this instead of the generic one).
func held_prompt() -> String:
	return "Serve the %s [RMB]  Drop [E]  Throw [LMB]" % display


## Host. Hands the item to the passenger nearest the holder's crosshair (within reach).
func use(peer: int, origin: Vector3, dir: Vector3) -> void:
	var best: Node = null
	var best_dot := SERVE_CONE
	for n: Node in world.npcs.people:
		var head: Vector3 = n.global_position + world.plane.global_basis.y * 0.4
		var to := head - origin
		var dot := to.normalized().dot(dir)
		if to.length() < SERVE_REACH and dot > best_dot:
			best_dot = dot
			best = n
	if best == null:
		world.notify(peer, "Aim at a passenger to hand over the %s." % display)
		return
	if best.mind.serve(peer, item) > 0:
		world.despawn_object(World.net_id(self))
