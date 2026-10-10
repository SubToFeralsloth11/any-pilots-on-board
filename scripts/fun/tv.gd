extends FunStation
## Wall TV playing the "in-flight movie": the host advances the scene every few seconds and
## anyone can change the channel [E]. Local frame: the screen faces +Z.

const SCENE_TIME := 6.0
const CHANNELS := [
	["SNAKES ON A PLANE 2", ["Now it's BEES.", "Samuel L. is tired.", "The bees have a lawyer.", "THE END?"]],
	["HOW TO LAND A PLANE", ["Step 1: don't.", "Step 2: find a pilot.", "Step 3: there is no pilot.", "Step 4: pray."]],
	["COOKING WITH TURBULENCE", ["Today: soup.", "Today: soup on the ceiling.", "Today: soup on you.", "Bon appétit."]],
	["CLOUD WATCH LIVE", ["A cloud.", "Another cloud.", "...that one looks like a duck.", "Still a cloud."]],
	["THE PILOT IS FINE", ["(A documentary)", "He is resting.", "He is resting very hard.", "Please stop asking."]],
	["EMERGENCY SAFETY VIDEO", ["Your seat is a flotation device.", "So is the guy next to you.", "Panic quietly.", "Thank you."]],
]
const BG := [Color(0.15, 0.05, 0.2), Color(0.05, 0.15, 0.3), Color(0.3, 0.12, 0.05), Color(0.25, 0.45, 0.7),
	Color(0.1, 0.25, 0.12), Color(0.35, 0.05, 0.05)]

var _screen: MeshInstance3D
var _title: Label3D
var _line: Label3D
var _timer := 0.0


func default_state() -> Dictionary:
	return {"ch": 0, "scene": 0}


func _build() -> void:
	var black := FunLooks.mat(Color(0.08, 0.08, 0.09), 0.3, 0.3)
	FunLooks.rounded_box(rig, Vector3(0.95, 0.58, 0.07), 0.03, black, Vector3(0, 0, 0.05))
	_screen = part(FunLooks.box(Vector3(0.86, 0.48, 0.01)), FunLooks.mat(BG[0], 0.2, 0.0, 1.2), Vector3(0, 0.01, 0.087))
	part(FunLooks.box(Vector3(0.1, 0.1, 0.04)), black, Vector3(0, 0, 0.0))
	part(FunLooks.sphere(0.008, 6), FunLooks.mat(Color(0.2, 1, 0.3), 0.3, 0.0, 2.0), Vector3(0.4, -0.26, 0.087))
	label("SKYTUBE", Vector3(-0.36, -0.265, 0.088), 14, Color(0.7, 0.7, 0.75))
	_title = label("", Vector3(0, 0.15, 0.095), 34, Color(1, 0.9, 0.4))
	_line = label("", Vector3(0, -0.05, 0.095), 28, Color(1, 1, 1))
	_line.width = 280.0
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	area(Vector3(0.95, 0.6, 0.3), Vector3(0, 0, 0.15), "Change the channel [E]", "channel")


func _refresh(_fx: String) -> void:
	var ch: int = int(state.ch) % CHANNELS.size()
	var lines: Array = CHANNELS[ch][1]
	_title.text = CHANNELS[ch][0]
	_line.text = lines[int(state.scene) % lines.size()]
	_screen.material_override = FunLooks.mat(BG[ch], 0.2, 0.0, 1.2)


func _play(fx: String, _args: Array) -> void:
	if fx == "static":
		_line.text = "*kssshhhh*"


func _process(dt: float) -> void:
	if not world.is_server():
		return
	_timer += dt
	if _timer >= SCENE_TIME:
		_timer = 0.0
		state.scene = int(state.scene) + 1
		push_state()


func act(peer: int, verb: String, _args: Array) -> void:
	if verb == "channel":
		state.ch = (int(state.ch) + 1) % CHANNELS.size()
		state.scene = 0
		_timer = 0.0
		push_state()
		world.notify(peer, "Now showing: " + CHANNELS[int(state.ch)][0])
