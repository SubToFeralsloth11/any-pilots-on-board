class_name FunGames
extends Node
## Activities and weapons: the furnished lounge, board games, dice, darts, hoops, machines,
## slapstick toy weapons and plane-wrecking tools.
##
## setup() (every peer) registers kinds and actions and builds the static lounge decor.
## populate() (host) spawns the stations (networked, stateful fixtures; see FunStation) and the
## loose toys. Every station interactable sends the host action "fun_station"
## [net_id, verb, ...]; the host checks reach and calls the station's act().

const Lounge := preload("res://scripts/fun/lounge.gd")
const ToysScript := preload("res://scripts/fun/toys.gd")
const DiceScript := preload("res://scripts/fun/dice.gd")
const DartScript := preload("res://scripts/fun/dart.gd")
const FlareScript := preload("res://scripts/fun/flare.gd")
const WreckerScript := preload("res://scripts/fun/wrecker.gd")
const STATIONS := {
	"connect_four": preload("res://scripts/fun/connect_four.gd"),
	"checkers": preload("res://scripts/fun/checkers.gd"),
	"dartboard": preload("res://scripts/fun/dartboard.gd"),
	"hoop": preload("res://scripts/fun/hoop.gd"),
	"tv": preload("res://scripts/fun/tv.gd"),
	"jukebox": preload("res://scripts/fun/jukebox.gd"),
	"vending": preload("res://scripts/fun/vending.gd"),
	"slots": preload("res://scripts/fun/slots.gd"),
	"lavatory": preload("res://scripts/fun/lavatory.gd"),
	"bell": preload("res://scripts/fun/bell.gd"),
}
## Station placements: type -> [plane-local position, yaw].
const PLACES := {
	"connect_four": [Vector3(-1.38, 0.72, 7.3), PI / 2],
	"checkers": [Vector3(-1.38, 0.72, 9.3), PI / 2],
	"tv": [Vector3(-1.3, 1.85, 6.1), 0.0],
	"dartboard": [Vector3(-1.2, 1.6, 12.08), 0.0],
	"hoop": [Vector3(1.2, 0.0, 12.08), 0.0],
	"vending": [Vector3(1.6, 0.0, 9.3), -PI / 2],
	"slots": [Vector3(1.65, 0.0, 10.3), -PI / 2],
	"jukebox": [Vector3(1.6, 0.0, 11.3), -PI / 2],
	"lavatory": [Vector3(-1.4, 0.0, 11.1), 0.0],
	"bell": [Vector3(1.1, 1.04, -9.5), 0.0],
}
## Loose things: [kind, plane-local position, yaw, extra]. Yaw PI/2 lays a weapon along X.
const LOOSE := [
	# Weapons rack (cabin bulkhead, lounge side).
	["dart_blaster", Vector3(1.15, 0.7, 6.25), PI / 2, {}],
	["water_pistol", Vector3(1.65, 0.7, 6.25), PI / 2, {}],
	["flare_gun", Vector3(1.15, 1.2, 6.25), PI / 2, {}],
	["power_drill", Vector3(1.65, 1.2, 6.25), PI / 2, {}],
	["blunderbuss", Vector3(1.4, 1.72, 6.25), PI / 2, {}],
	# Bar counter and booths.
	["baguette", Vector3(1.4, 1.12, 7.65), 0.0, {}],
	["confetti_cannon", Vector3(1.68, 1.15, 7.75), 0.0, {}],
	["pillow_fight", Vector3(-1.38, 0.62, 8.58), 0.0, {}],
	["leaf_blower", Vector3(-1.45, 0.72, 8.02), PI / 2, {}],
	["crowbar", Vector3(-1.2, 0.62, 10.02), PI / 2, {}],
	# Galley emergency shelves above the counters.
	["frying_pan", Vector3(1.45, 1.64, -9.78), PI / 2, {}],
	["fire_axe", Vector3(-1.45, 1.64, -9.77), PI / 2, {}],
	# Cargo hold.
	["sledgehammer", Vector3(0.9, 0.12, 13.4), 0.3, {}],
	["golf_club", Vector3(-0.9, 0.08, 13.4), -0.2, {}],
	["golf_ball", Vector3(-0.7, 0.06, 13.0), 0.0, {}],
	["golf_ball", Vector3(-0.6, 0.06, 13.1), 0.0, {}],
	["golf_ball", Vector3(-0.8, 0.06, 13.15), 0.0, {}],
	["basketball", Vector3(1.0, 0.15, 13.0), 0.0, {}],
	["basketball", Vector3(1.35, 0.15, 13.2), 0.0, {}],
	# Dice: two on booth A's table, one jumbo on the lounge floor.
	["dice", Vector3(-1.05, 0.8, 7.0), 0.3, {}],
	["dice", Vector3(-1.05, 0.8, 7.62), 1.1, {}],
	["dice", Vector3(0.0, 0.2, 10.9), 0.4, {"big": true}],
	# Darts on the bar for the dartboard.
	["dart", Vector3(1.42, 1.08, 6.86), PI / 2, {"color": 0}],
	["dart", Vector3(1.42, 1.08, 6.94), PI / 2, {"color": 0}],
	["dart", Vector3(1.42, 1.08, 7.02), PI / 2, {"color": 1}],
	["dart", Vector3(1.42, 1.08, 7.10), PI / 2, {"color": 1}],
	["dart", Vector3(1.42, 1.08, 7.18), PI / 2, {"color": 2}],
	["dart", Vector3(1.42, 1.08, 7.26), PI / 2, {"color": 2}],
]

var world: World
var stations := {}       ## type -> FunStation (every peer, filled as stations spawn).


func setup(w: World) -> void:
	world = w
	Lounge.build(world.plane)
	world.register_kind("fun_station", func(extra: Dictionary) -> Node3D:
		return STATIONS[extra.type].new(world, self, extra))
	for k in ["basketball", "golf_ball", "checker"]:
		world.register_kind(k, func(extra: Dictionary) -> Node3D: return ToysScript.new(world, k, extra))
	world.register_kind("dice", func(extra: Dictionary) -> Node3D: return DiceScript.new(world, "dice", extra))
	world.register_kind("dart", func(extra: Dictionary) -> Node3D: return DartScript.new(world, "dart", extra))
	world.register_kind("flare", func(extra: Dictionary) -> Node3D: return FlareScript.new(world, "flare", extra))
	for k: String in FunWeapon.SPECS:
		world.register_kind(k, func(extra: Dictionary) -> Node3D: return FunWeapon.new(world, k, extra))
	for k: String in WreckerScript.TOOLS:
		world.register_kind(k, func(extra: Dictionary) -> Node3D: return WreckerScript.new(world, k, extra))
	world.register_action("fun_station", _act_station)


func populate() -> void:
	for type: String in PLACES:
		world.spawn_object("fun_station", Transform3D.IDENTITY,
			{"type": type, "pos": PLACES[type][0], "yaw": PLACES[type][1]})
	(stations["checkers"] as FunCheckers).rack()
	for l: Array in LOOSE:
		var xform := world.plane.global_transform * Transform3D(Basis(Vector3.UP, l[2]), l[1])
		world.spawn_object(l[0], xform, l[3])


## Host. Routes [net_id, verb, ...] from a station interactable.
func _act_station(peer: int, args: Array) -> void:
	if args.size() < 2:
		return
	var st := world.get_object(int(args[0])) as FunStation
	if st == null or not st.near(peer):
		return
	st.act(peer, String(args[1]), args.slice(2))


## Host. A die settled; announce it.
func report_roll(peer: int, value: int) -> void:
	var who := world.display_name(peer) if peer != 0 else "The plane"
	var flavour := " Nice!" if value == 6 else (" Ouch." if value == 1 else "")
	world.say("", "%s rolled a %d!%s" % [who, value, flavour], 2.5)
