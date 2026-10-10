class_name Interactable
extends Area3D
## Something the player can press [E] on (seat, lever, door, crate...).
## By default pressing E sends world.request(action, args) to the host.
## If `local_only` is set, `used` is emitted on the pressing peer instead.

signal used(player: Node)

const LAYER := 1 << 5   ## Physics layer 6: interact volumes only.

var prompt := ""
var action := ""
var args: Array = []
var local_only := false
var enabled := true


static func make(size: Vector3, p_prompt: String, p_action: String, p_args: Array = []) -> Interactable:
	var a := Interactable.new()
	a.prompt = p_prompt
	a.action = p_action
	a.args = p_args
	a.collision_layer = LAYER
	a.collision_mask = 0
	a.monitoring = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	a.add_child(shape)
	return a


func get_prompt() -> String:
	return prompt if enabled else ""
