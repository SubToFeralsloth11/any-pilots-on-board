extends FunStation
## A brass service bell on the galley counter. [E] goes DING and the flight attendant
## responds (whatever state they're in). Local frame: the origin sits on the countertop.

const COOLDOWN_MS := 2500
const LINES := [
	"Yes? I'm a little busy keeping us alive.",
	"Ding me one more time. I dare you.",
	"Today's in-flight meal is: panic.",
	"Have you tried sitting down? Or flying the plane?",
	"Peanuts are in the cargo hold. Everything is in the cargo hold.",
	"Your call is important to us. Please hold. Forever.",
	"If you can hear this, you are not the pilot. Please find one.",
	"No, the bar is not closed. Nothing is closed. Nothing matters.",
	"Ma'am, that's a fire axe, not a cocktail stirrer.",
	"The captain says hi. The captain is unconscious. I'm doing a voice.",
]

var _next_ms := 0
var _dome: Node3D


func _build() -> void:
	var brass := FunLooks.metal(FunLooks.BRASS)
	part(FunLooks.cyl(0.07, 0.075, 0.02, 20), FunLooks.mat(FunLooks.WOOD_DARK, 0.4), Vector3(0, 0.01, 0))
	_dome = Node3D.new()
	_dome.position = Vector3(0, 0.02, 0)
	rig.add_child(_dome)
	part(FunLooks.sphere(0.055, 18), brass, Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1, 0.8, 1), _dome)
	part(FunLooks.cyl(0.006, 0.006, 0.03, 8), brass, Vector3(0, 0.055, 0), Vector3.ZERO, Vector3.ONE, _dome)
	part(FunLooks.sphere(0.012, 8), brass, Vector3(0, 0.072, 0), Vector3.ZERO, Vector3.ONE, _dome)
	label("RING FOR\nSERVICE", Vector3(0, 0.16, 0), 16, Color(1, 0.9, 0.5)).billboard = BaseMaterial3D.BILLBOARD_ENABLED
	area(Vector3(0.25, 0.25, 0.25), Vector3(0, 0.08, 0), "Ring the service bell [E]", "ding")


func _play(fx: String, _args: Array) -> void:
	if fx != "ding":
		return
	FunFx.popup(world, global_point(Vector3(0, 0.2, 0)), "DING!", Color(1, 0.9, 0.4), 70)
	_dome.scale = Vector3(1.1, 0.8, 1.1)
	var tw := _dome.create_tween()
	tw.tween_property(_dome, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func act(_peer: int, verb: String, _args: Array) -> void:
	if verb != "ding":
		return
	push_state("ding")
	var now := Time.get_ticks_msec()
	if now < _next_ms:
		return
	_next_ms = now + COOLDOWN_MS
	world.say("Flight Attendant", LINES.pick_random(), 3.5)
