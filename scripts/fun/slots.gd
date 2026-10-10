extends FunStation
## A one-armed bandit. Pull the lever [E]: the reels spin on every screen and land on the
## host's result. Two of a kind pays out a snack; three of a kind pays out a random weapon
## and confetti. Local frame: the front faces +Z, the origin is on the floor.

const SYMBOLS := ["7", "BAR", "$", "<3", "?!", "XO"]
const SYMBOL_COLORS := [Color(0.2, 0.5, 1), Color(0.6, 0.7, 0.8), Color(1, 0.8, 0.1), Color(0.9, 0.1, 0.1),
	Color(1, 0.3, 0.6), Color(0.2, 0.7, 0.3)]
const SPIN_TIME := 1.4
const PRIZES := ["baguette", "frying_pan", "dart_blaster", "water_pistol", "confetti_cannon", "leaf_blower",
	"golf_club", "pillow_fight", "crowbar", "power_drill", "flare_gun", "blunderbuss"]
const SAD := ["The machine laughs at you.", "So close. (Not close.)", "The house always wins. Even at 30,000 feet.",
	"Try again! (Gambling is bad.)"]

var _reels: Array[Label3D] = []
var _lever: Node3D
var _spinning := 0.0
var _busy := false


func default_state() -> Dictionary:
	return {"reels": [0, 1, 2], "pulls": 0, "jackpots": 0}


func _build() -> void:
	var gold := FunLooks.metal(FunLooks.BRASS)
	var body := FunLooks.mat(Color(0.55, 0.1, 0.65), 0.35)
	FunLooks.rounded_box(rig, Vector3(0.55, 0.9, 0.45), 0.05, body, Vector3(0, 0.45, 0))
	FunLooks.rounded_box(rig, Vector3(0.55, 0.55, 0.38), 0.08, body, Vector3(0, 1.17, -0.03))
	part(FunLooks.cyl(0.2, 0.2, 0.36, 24), gold, Vector3(0, 1.45, -0.03), Vector3(0, 0, PI / 2), Vector3(1, 1, 1))
	label("LUCKY\nLANDING", Vector3(0, 1.45, 0.17), 28, Color(1, 0.2, 0.3))
	part(FunLooks.box(Vector3(0.44, 0.2, 0.02)), FunLooks.mat(FunLooks.CREAM, 0.3), Vector3(0, 1.12, 0.165))
	for i in 3:
		var l := label("", Vector3(-0.14 + i * 0.14, 1.12, 0.18), 34, Color.WHITE)
		_reels.append(l)
		part(FunLooks.box(Vector3(0.01, 0.2, 0.025)), gold, Vector3(-0.21 + i * 0.14, 1.12, 0.17))
	part(FunLooks.box(Vector3(0.01, 0.2, 0.025)), gold, Vector3(0.21, 1.12, 0.17))
	for i in 7:
		part(FunLooks.sphere(0.018, 6), FunLooks.mat(Color(1, 0.9, 0.4), 0.3, 0.0, 2.0), Vector3(-0.24 + i * 0.08, 1.37, 0.17))
	part(FunLooks.box(Vector3(0.36, 0.08, 0.1)), FunLooks.mat(FunLooks.INK), Vector3(0, 0.3, 0.2))
	label("PRIZES", Vector3(0, 0.3, 0.255), 18, Color(1, 0.85, 0.3))
	# Lever on the right side.
	part(FunLooks.cyl(0.05, 0.05, 0.05, 16), gold, Vector3(0.3, 0.9, 0), Vector3(0, 0, PI / 2))
	_lever = Node3D.new()
	_lever.position = Vector3(0.33, 0.9, 0)
	rig.add_child(_lever)
	part(FunLooks.cyl(0.015, 0.015, 0.4, 8), FunLooks.metal(FunLooks.CHROME), Vector3(0, 0.2, 0), Vector3.ZERO, Vector3.ONE, _lever)
	part(FunLooks.sphere(0.05, 14), FunLooks.mat(Color(0.95, 0.1, 0.15), 0.25), Vector3(0, 0.42, 0), Vector3.ZERO, Vector3.ONE, _lever)
	collider(Vector3(0.6, 1.65, 0.45), Vector3(0, 0.825, 0))
	area(Vector3(0.7, 1.4, 0.35), Vector3(0, 0.9, 0.35), "Pull the slot machine lever [E]", "pull")


func _refresh(_fx: String) -> void:
	if _spinning > 0.0:
		return
	var reels: Array = state.reels
	for i in 3:
		_reels[i].text = SYMBOLS[int(reels[i])]
		_reels[i].modulate = SYMBOL_COLORS[int(reels[i])]


func _play(fx: String, _args: Array) -> void:
	match fx:
		"spin":
			_spinning = SPIN_TIME
			var tw := _lever.create_tween()
			tw.tween_property(_lever, "rotation:x", 1.2, 0.15)
			tw.tween_property(_lever, "rotation:x", 0.0, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		"jackpot":
			var at := global_point(Vector3(0, 1.5, 0.3))
			FunFx.burst(world, at, FunLooks.CONFETTI, 80, 5.0, 0.06, Vector3.UP, 60.0, 2.0, Vector3(0, -3, 0), true)
			FunFx.popup(world, at + Vector3(0, 0.3, 0), "JACKPOT!!!", Color(1, 0.85, 0.2), 110)
		"small":
			FunFx.popup(world, global_point(Vector3(0, 1.5, 0.3)), "WINNER!", Color(0.5, 1, 0.5), 70)


func _process(dt: float) -> void:
	if _spinning <= 0.0:
		return
	_spinning -= dt
	var reels: Array = state.reels
	for i in 3:
		# Reels stop left to right.
		if _spinning > SPIN_TIME * (0.6 - i * 0.25):
			var s := randi() % SYMBOLS.size()
			_reels[i].text = SYMBOLS[s]
			_reels[i].modulate = SYMBOL_COLORS[s]
		else:
			_reels[i].text = SYMBOLS[int(reels[i])]
			_reels[i].modulate = SYMBOL_COLORS[int(reels[i])]
	if _spinning <= 0.0:
		_refresh("")


func act(peer: int, verb: String, _args: Array) -> void:
	if verb != "pull" or _busy:
		return
	_busy = true
	var reels := [randi() % SYMBOLS.size(), randi() % SYMBOLS.size(), randi() % SYMBOLS.size()]
	# Rig it a little so jackpots actually happen on a short flight.
	if randf() < 0.12:
		reels = [reels[0], reels[0], reels[0]]
	elif randf() < 0.25:
		reels[1] = reels[0]
	state.reels = reels
	state.pulls = int(state.pulls) + 1
	push_state("spin")
	await get_tree().create_timer(SPIN_TIME + 0.1).timeout
	_busy = false
	if not is_inside_tree():
		return
	var tray := global_point(Vector3(0, 0.35, 0.35))
	var who := world.display_name(peer)
	if reels[0] == reels[1] and reels[1] == reels[2]:
		state.jackpots = int(state.jackpots) + 1
		push_state("jackpot")
		var prize: String = PRIZES.pick_random()
		world.spawn_object(prize, Transform3D(world.plane.global_basis, tray), {})
		world.say("Lucky Landing", "JACKPOT! %s wins a %s!" % [who, prize.replace("_", " ")], 3.5)
	elif reels[0] == reels[1] or reels[1] == reels[2] or reels[0] == reels[2]:
		push_state("small")
		world.spawn_object("snack", Transform3D(world.plane.global_basis, tray), {})
		world.notify(peer, "Two of a kind! You win... a snack.")
	else:
		world.notify(peer, SAD.pick_random())
