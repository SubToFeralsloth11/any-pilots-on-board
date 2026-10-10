class_name FunDartboard
extends FunStation
## A dartboard with a chalk scoreboard. Darts (kind "dart") that stick within the board call
## score_hit() on the host. Local frame: the board face looks along +Z at the station origin.

const RADIUS := 0.25
const BULL := 0.022
const OUTER_BULL := 0.048
const TREBLE := Vector2(0.135, 0.155)
const DOUBLE := Vector2(0.225, 0.25)
const SECTORS := [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
const BOARD_Y := 0.0
const SCORE_Y := 0.52

var _board_text: Label3D


func default_state() -> Dictionary:
	return {"scores": [], "last": "Grab darts at the bar!"}


func _build() -> void:
	var face := Vector3(PI / 2, 0, 0)
	part(FunLooks.cyl(0.31, 0.31, 0.04, 32), FunLooks.mat(Color(0.62, 0.45, 0.28), 0.95), Vector3(0, 0, 0.02), face)
	part(FunLooks.cyl(RADIUS, RADIUS, 0.03, 32), FunLooks.mat(Color(0.08, 0.08, 0.08)), Vector3(0, 0, 0.05), face)
	var red := FunLooks.mat(Color(0.85, 0.12, 0.12))
	var green := FunLooks.mat(Color(0.1, 0.55, 0.25))
	var cream := FunLooks.mat(FunLooks.CREAM)
	part(FunLooks.cyl(0.2, 0.2, 0.031, 32), cream, Vector3(0, 0, 0.05), face)
	part(FunLooks.cyl(0.13, 0.13, 0.032, 32), FunLooks.mat(Color(0.08, 0.08, 0.08)), Vector3(0, 0, 0.05), face)
	part(FunLooks.cyl(0.11, 0.11, 0.033, 32), cream, Vector3(0, 0, 0.05), face)
	part(FunLooks.torus((DOUBLE.x + DOUBLE.y) / 2 - 0.011, (DOUBLE.x + DOUBLE.y) / 2 + 0.011), red,
		Vector3(0, 0, 0.066), face, Vector3(1, 0.3, 1))
	part(FunLooks.torus((TREBLE.x + TREBLE.y) / 2 - 0.009, (TREBLE.x + TREBLE.y) / 2 + 0.009), green,
		Vector3(0, 0, 0.066), face, Vector3(1, 0.3, 1))
	part(FunLooks.cyl(OUTER_BULL, OUTER_BULL, 0.036, 20), green, Vector3(0, 0, 0.05), face)
	part(FunLooks.cyl(BULL, BULL, 0.04, 16), red, Vector3(0, 0, 0.05), face)
	var wire := FunLooks.metal(FunLooks.CHROME)
	for i in SECTORS.size():
		var a := (i + 0.5) * TAU / SECTORS.size()
		var spoke := part(FunLooks.cyl(0.003, 0.003, RADIUS - OUTER_BULL, 4), wire,
			Vector3(sin(a), cos(a), 0) * (OUTER_BULL + RADIUS) / 2 + Vector3(0, 0, 0.068))
		spoke.rotation = Vector3(0, 0, -a)
		label(str(SECTORS[i]), Vector3(sin(a - TAU / 40), cos(a - TAU / 40), 0) * 0.285 + Vector3(0, 0, 0.05),
			22, Color(1, 1, 0.9))
	collider(Vector3(0.62, 0.62, 0.06), Vector3(0, 0, 0.03))
	# Chalkboard with the scores.
	FunLooks.rounded_box(rig, Vector3(0.86, 0.34, 0.04), 0.02, FunLooks.mat(FunLooks.WOOD), Vector3(0, SCORE_Y, 0.02))
	part(FunLooks.box(Vector3(0.8, 0.28, 0.01)), FunLooks.mat(Color(0.12, 0.2, 0.16), 0.95), Vector3(0, SCORE_Y, 0.045))
	_board_text = label("", Vector3(0, SCORE_Y, 0.052), 18, Color(0.95, 0.95, 0.9))
	_board_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	part(FunLooks.capsule(0.015, 0.09), FunLooks.mat(Color(0.3, 0.3, 0.6)), Vector3(0.33, SCORE_Y - 0.19, 0.06),
		Vector3(0, 0, PI / 2))
	area(Vector3(0.86, 0.34, 0.2), Vector3(0, SCORE_Y, 0.1), "Wipe the darts scoreboard [E]", "wipe")


func _refresh(_fx: String) -> void:
	var lines := PackedStringArray(["DARTS", state.last])
	var scores: Array = state.scores.duplicate()
	scores.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
	for i in mini(3, scores.size()):
		lines.append("%d. %s  %d" % [i + 1, scores[i][0], scores[i][1]])
	_board_text.text = "\n".join(lines)


func _play(fx: String, args: Array) -> void:
	if fx != "hit":
		return
	var at: Vector3 = args[0]
	var pts: int = args[1]
	FunFx.popup(world, at + Vector3(0, 0.1, 0), "+%d" % pts if pts > 0 else "MISS",
		Color(1, 0.9, 0.3) if pts > 0 else Color(0.8, 0.8, 0.8), 64)
	if pts >= 50:
		FunFx.burst(world, at, FunLooks.CONFETTI, 40, 3.0, 0.05, Vector3.UP, 180.0, 1.5, Vector3(0, -3, 0), true)


func act(peer: int, verb: String, _args: Array) -> void:
	if verb == "wipe":
		state = default_state()
		push_state()
		world.notify(peer, "Scoreboard wiped. Fresh start, champ.")


## Host. A dart stuck at global `tip`; returns true if it landed on the board.
func score_hit(tip: Vector3, peer: int) -> bool:
	var local := (world.plane.global_transform * local_xform()).affine_inverse() * tip
	var r := Vector2(local.x, local.y).length()
	if absf(local.z) > 0.15 or r > RADIUS + 0.03:
		return false
	var pts := 0
	var how := ""
	if r <= BULL:
		pts = 50
		how = "BULLSEYE"
	elif r <= OUTER_BULL:
		pts = 25
		how = "outer bull"
	elif r <= DOUBLE.y:
		var angle := fposmod(atan2(local.x, local.y) + TAU / 40.0, TAU)
		var n: int = SECTORS[int(angle / (TAU / SECTORS.size())) % SECTORS.size()]
		var mult := 3 if r >= TREBLE.x and r <= TREBLE.y else (2 if r >= DOUBLE.x else 1)
		pts = n * mult
		var fmt: String = ["", "%d", "double %d", "TREBLE %d"][mult]
		how = fmt % n
	var who := world.display_name(peer) if peer != 0 else "The plane"
	if pts > 0:
		var scores: Array = state.scores
		var found := false
		for s: Array in scores:
			if s[0] == who:
				s[1] = int(s[1]) + pts
				found = true
		if not found:
			scores.append([who, pts])
		state.last = "%s: %s = %d" % [who, how, pts]
		if how == "BULLSEYE":
			world.say("Darts", "BULLSEYE!! %s is a legend." % who, 3.0)
		elif pts >= 40:
			world.say("Darts", "%s hits a %s!" % [who, how], 2.5)
	else:
		state.last = "%s: off the board!" % who
	push_state("hit", [tip, pts])
	return true
