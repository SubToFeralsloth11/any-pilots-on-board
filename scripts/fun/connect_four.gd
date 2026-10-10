extends FunStation
## Connect Four standing on a lounge table. Press [E] on a column to drop a disc.
## The first two players to move claim RED and YELLOW; alone, you may play both sides.
## Four in a row (any direction) wins; a full board is a draw. The red button resets.
## Local frame: the board faces +Z, columns run along X, the origin is the tabletop.

const COLS := 7
const ROWS := 6
const CELL := 0.09
const NAMES := ["", "RED", "YELLOW"]
const COLORS := [Color(0.08, 0.1, 0.32), Color(0.92, 0.16, 0.16), Color(1.0, 0.82, 0.12)]
const FRAME := Color(0.13, 0.36, 0.9)
const WIN_LINES := ["Four in a row! %s is a genius.", "%s wins! Somebody alert the newspapers.",
	"%s connects four. The plane is still falling, but good for you."]

var _cells: Array[MeshInstance3D] = []
var _status: Label3D


func default_state() -> Dictionary:
	var grid: Array[int] = []
	grid.resize(COLS * ROWS)
	grid.fill(0)
	return {"grid": grid, "turn": 1, "owners": [0, 0, 0], "names": ["", "", ""], "winner": 0, "line": []}


func _build() -> void:
	var blue := FunLooks.mat(FRAME, 0.35)
	var w := COLS * CELL + 0.06
	var h := ROWS * CELL + 0.06
	part(FunLooks.box(Vector3(w, h, 0.05)), blue, Vector3(0, 0.07 + h / 2, 0))
	part(FunLooks.box(Vector3(w, 0.02, 0.07)), blue, Vector3(0, 0.08 + h, 0))
	for sx in [-1.0, 1.0]:
		part(FunLooks.capsule(0.03, h + 0.1), blue, Vector3(sx * (w / 2 + 0.02), 0.07 + h / 2, 0))
		part(FunLooks.cyl(0.035, 0.05, 0.36), blue, Vector3(sx * (w / 2 + 0.02), 0.03, 0), Vector3(PI / 2, 0, 0))
	for i in COLS * ROWS:
		var m := part(FunLooks.cyl(0.038, 0.038, 0.06, 16), FunLooks.mat(COLORS[0]), _cell_pos(i),
			Vector3(PI / 2, 0, 0))
		_cells.append(m)
	for c in COLS:
		var x := (c - (COLS - 1) / 2.0) * CELL
		area(Vector3(CELL * 0.95, h + 0.15, 0.4), Vector3(x, 0.07 + h / 2, 0), "", "drop", [c])
		label(str(c + 1), Vector3(x, 0.12 + h, 0.04), 22, Color(1, 1, 1, 0.8))
	# Reset button on a little post beside the board.
	var bx := w / 2 + 0.1
	part(FunLooks.cyl(0.02, 0.03, 0.12), FunLooks.metal(FunLooks.CHROME), Vector3(bx, 0.06, 0.08))
	part(FunLooks.sphere(0.035), FunLooks.mat(Color(0.95, 0.15, 0.15), 0.3), Vector3(bx, 0.13, 0.08),
		Vector3.ZERO, Vector3(1, 0.6, 1))
	label("RESET", Vector3(bx, 0.2, 0.08), 20, Color(1, 0.6, 0.6))
	area(Vector3(0.14, 0.25, 0.14), Vector3(bx, 0.12, 0.08), "Reset Connect Four [E]", "reset")
	_status = label("", Vector3(0, h + 0.28, 0.02), 18)
	_status.width = 420.0
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _cell_pos(i: int) -> Vector3:
	var c := i % COLS
	var r := i / COLS
	return Vector3((c - (COLS - 1) / 2.0) * CELL, 0.1 + 0.03 + r * CELL + CELL / 2, 0)


func _refresh(_fx: String) -> void:
	var grid: Array = state.grid
	var line: Array = state.line
	for i in _cells.size():
		var v: int = grid[i]
		_cells[i].material_override = FunLooks.mat(COLORS[v], 0.3, 0.0, 0.8 if line.has(i) else 0.0)
	var names: Array = state.names
	var who := "%s: %s   vs   %s: %s" % [NAMES[1], _or_open(names[1]), NAMES[2], _or_open(names[2])]
	var winner: int = state.winner
	var turn: int = state.turn
	var head: String
	if winner == 3:
		head = "DRAW! Nobody wins. Press RESET."
	elif winner != 0:
		head = "%s (%s) WINS! Press RESET." % [_or_open(names[winner]), NAMES[winner]]
	else:
		head = "%s to play. Aim at a column, press [E]." % NAMES[turn]
	_status.text = "CONNECT FOUR\n%s\n%s" % [who, head]
	_status.modulate = COLORS[turn].lightened(0.3) if winner == 0 else Color(0.6, 1, 0.6)
	for a in rig.get_children():
		if a is Interactable and (a as Interactable).args[1] == "drop":
			var col: int = (a as Interactable).args[2]
			(a as Interactable).prompt = "Drop a %s disc in column %d [E]" % [NAMES[turn], col + 1] \
				if winner == 0 else "Game over. Hit RESET"


func _or_open(n: String) -> String:
	return n if n != "" else "(open)"


func _play(fx: String, args: Array) -> void:
	if fx != "drop":
		return
	var cell: MeshInstance3D = _cells[int(args[0])]
	var target := cell.position
	cell.position = Vector3(target.x, 0.1 + ROWS * CELL + 0.15, target.z)
	var tw := cell.create_tween()
	tw.tween_property(cell, "position", target, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func act(peer: int, verb: String, args: Array) -> void:
	match verb:
		"reset":
			state = default_state()
			push_state()
			world.say(world.display_name(peer), "*resets the Connect Four board*", 2.0)
		"drop":
			if args.size() > 0:
				_drop(peer, clampi(int(args[0]), 0, COLS - 1))


func _drop(peer: int, col: int) -> void:
	if int(state.winner) != 0:
		world.notify(peer, "That game is over. Press the red RESET button.")
		return
	var turn: int = state.turn
	var other := 3 - turn
	var owners: Array = state.owners
	var names: Array = state.names
	for c in [1, 2]:
		if owners[c] != 0 and not world.players.has(owners[c]):
			owners[c] = 0
			names[c] = ""
	if owners[turn] == 0:
		if owners[other] == peer and world.players.size() > 1:
			world.notify(peer, "Waiting for someone to play %s." % NAMES[turn])
			return
		if owners[other] != peer:
			owners[turn] = peer
			names[turn] = world.display_name(peer)
	elif owners[turn] != peer:
		world.notify(peer, "It's %s's turn (%s)." % [names[turn], NAMES[turn]])
		return
	var grid: Array = state.grid
	var cell := -1
	for r in ROWS:
		if grid[r * COLS + col] == 0:
			cell = r * COLS + col
			break
	if cell < 0:
		world.notify(peer, "Column %d is full." % (col + 1))
		return
	grid[cell] = turn
	var line := _four_from(grid, cell)
	if not line.is_empty():
		state.winner = turn
		state.line = line
		var winner_name := world.display_name(peer)
		world.say("Connect Four", WIN_LINES.pick_random() % winner_name, 4.0)
	elif not grid.has(0):
		state.winner = 3
		world.say("Connect Four", "A draw! Everyone loses equally.", 3.5)
	else:
		state.turn = other
	push_state("drop", [cell])


## The winning cells through `cell`, or [] if it doesn't make four.
func _four_from(grid: Array, cell: int) -> Array:
	var c0 := cell % COLS
	var r0 := cell / COLS
	var who: int = grid[cell]
	for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
		var line := [cell]
		for s: int in [1, -1]:
			var c := c0 + d.x * s
			var r := r0 + d.y * s
			while c >= 0 and c < COLS and r >= 0 and r < ROWS and grid[r * COLS + c] == who:
				line.append(r * COLS + c)
				c += d.x * s
				r += d.y * s
		if line.size() >= 4:
			return line
	return []
