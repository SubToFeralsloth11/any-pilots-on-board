extends Node
## Host-driven story: captain intro, blackout, "is anyone a pilot?", cockpit unlock,
## TOWER tutorial and coaching, random chaos events and the ending lines.
##
## Lives at /root/Main/World/Story on every peer. Only the host runs the state machine;
## clients receive subtitles via world.say and the objective via _rpc_objective / apply_sync.

enum Act { INTRO, ASK, COCKPIT, ENDED }

const ASK_TIMEOUT := 20.0
const CHAOS_MIN := 25.0
const CHAOS_MAX := 50.0
const COACH_GAP := 8.0          ## Minimum seconds between any two TOWER tips.
const TIP_REPEAT := 25.0        ## Minimum seconds before the same tip again.
const SHOUT_COOLDOWN := 1.2
const FLOAT_TIME := 4.0
const PITCH_UP_KEY := "S"       ## Flight-sim style, matches Player._send_pilot_input.
const PITCH_DOWN_KEY := "W"
const Npc := preload("res://scripts/npcs/npc.gd")
const CHAOS := ["turbulence", "bird", "fire", "bins", "captain", "ramp", "trolley", "air_pocket", "lightning",
	"sputter", "bird_engine"]
const FLASH_TIME := 0.6
## Pitch lurches are eased in (rad/s): an instant pitch change would teleport the
## cockpit metres through anything standing in it.
const NUDGE_RATE := 0.3

const LIES := ["Yeah. Totally. I've played a flight sim. Once.", "Pilot? Me? Yes. Absolutely. (No.)",
	"I've seen Top Gun like nine times.", "Sure! How hard can it be? It's mostly buttons.",
	"I once flew a kite for three whole minutes.", "My uncle owns a plane. Well, a drawing of one."]
const SHOUTS := ["WHO PACKED THE SNAKES?!", "I'M A DOCTOR! ...of philosophy.", "Does anyone have gum?",
	"STAY CALM! (I'm not calm.)", "This is fine.", "AAAAAAAAAH!", "I'd like to speak to the manager of the sky!",
	"Is it too late to ask for the vegetarian meal?", "Everybody lean LEFT!", "I believe I can fly!",
	"Has anyone seen my shoe?", "WHEEEEEE!", "I demand a window seat!", "Totally under control!"]
const CAPTAIN_WAKE := ["Wha—? Who's flying? ...Is it me? Oh no. *thud*",
	"Ladies and gentlemen, please enjoy the in-flight... *snore*",
	"I can see the fish... it's so beautiful... *thud*",
	"Autopilot? We don't have one. I just say that. Night night.",
	"Remember: up is good, down is bad. Zzz...", "Tell my wife... the fish... was MID. *thud*"]
const BIRD := ["*THWACK* A goose just came through the window. It looks furious.",
	"BIRD STRIKE! A seagull is now technically a passenger.",
	"*SPLAT* A pigeon has entered the cabin and is demanding peanuts."]
const CRASH := ["...Flight 404? Hello? ...I'll just write 'arrived'.",
	"Tower to Flight 404: that's... technically a landing.",
	"And THAT is why we don't let passengers fly.", "Hm. The insurance people are gonna love this."]

var world: World
var objective := ""             ## Current goal text (synced to every peer; the HUD shows it).
var act := Act.INTRO
var cockpit_open := false

var _lines: Array[Dictionary] = []   ## Host: queued subtitles {speaker, text, dur, then}.
var _line_t := 1.0
var _ask_t := 0.0
var _chaos_t := 0.0
var _last_chaos := ""
var _float_t := 0.0
var _taught := false
var _time := 0.0
var _coach_t := 0.0
var _check_t := 0.0
var _tips := {}                 ## tip key -> time it was last said.
var _shouted := {}              ## peer -> time of the last shout.
var _flight_phase := FlightModel.Phase.FLYING
var _flash: ColorRect
var _flash_t := 0.0
var _nudge := 0.0               ## Host: pitch lurch still to apply (rad).


func setup(w: World) -> void:
	world = w
	world.register_action("shout", _on_shout)
	world.pilot_changed.connect(_on_pilot_changed)
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_flash = ColorRect.new()
	_flash.color = Color(0.92, 0.95, 1.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.visible = false
	layer.add_child(_flash)


func populate() -> void:
	print("[story] intro")
	_set_objective("Enjoy your flight. Sit back. Relax. Don't touch anything.")
	_queue("CAPTAIN", "Good evening, this is your captain speaking. Welcome to Flight 404.", 3.0)
	_queue("CAPTAIN", "Quick update: I ate the fish. The fish is fighting back.", 3.2)
	_queue("CAPTAIN", "*gurgle* ...gonna close my eyes for just a—", 2.5)
	_queue("", "", 0.0, _blackout)


## Host. World asks before letting someone sit in the pilot seat.
func can_pilot(_peer: int) -> bool:
	return cockpit_open


func get_sync() -> Dictionary:
	return {"objective": objective, "act": act, "open": cockpit_open}


func apply_sync(d: Dictionary) -> void:
	objective = d.get("objective", "")
	act = int(d.get("act", Act.INTRO)) as Act
	cockpit_open = d.get("open", false)


# --- Objective -------------------------------------------------------------------------

func _set_objective(text: String) -> void:
	if text == objective:
		return
	objective = text
	for p in world._ready_peers:
		_rpc_objective.rpc_id(p, text)


@rpc("authority", "call_remote", "reliable")
func _rpc_objective(text: String) -> void:
	objective = text


# --- Lightning flash (cosmetic, every peer) ---------------------------------------------

## Host. White screen flash on every peer.
func _flash_all() -> void:
	for p in world._ready_peers:
		_rpc_flash.rpc_id(p)
	_rpc_flash()


@rpc("authority", "call_remote", "reliable")
func _rpc_flash() -> void:
	_flash_t = FLASH_TIME
	_flash.visible = true


func _process(dt: float) -> void:
	if _flash_t <= 0.0:
		return
	_flash_t -= dt
	_flash.color.a = clampf(_flash_t / FLASH_TIME, 0.0, 1.0) * (0.6 + 0.4 * float(int(_flash_t * 20.0) % 2))
	_flash.visible = _flash_t > 0.0


# --- Line queue (host) -----------------------------------------------------------------

## Queues a subtitle. `then` runs when the line starts; an empty text is a pause of `dur`.
func _queue(speaker: String, text: String, dur := 3.0, then := Callable()) -> void:
	_lines.append({"speaker": speaker, "text": text, "dur": dur, "then": then})


func _run_lines(dt: float) -> void:
	_line_t -= dt
	if _line_t > 0.0 or _lines.is_empty():
		return
	var l: Dictionary = _lines.pop_front()
	var text: String = l.text
	_line_t = l.dur
	if text != "":
		_line_t += 0.4
		world.say(l.speaker, text, l.dur)
		if l.speaker == "ATTENDANT":
			world.npcs.attendant_say(text)
	var then: Callable = l.then
	if then.is_valid():
		then.call()


# --- Main beats ------------------------------------------------------------------------

func _blackout() -> void:
	print("[story] blackout: the captain is down")
	world.say("", "*THUD*", 1.5)
	world.shake_all(0.9)
	_nudge -= 0.15
	world.flight.bump = 0.8
	world.npcs.captain_blackout()
	world.npcs.panic_all(0.35)
	_set_objective("Uh oh.")
	_queue("", "", 1.6)
	_queue("ATTENDANT", "Captain? ...CAPTAIN?!", 2.0)
	_queue("ATTENDANT", "IS ANYONE ON BOARD A PILOT?!", 4.0, _start_ask)


func _start_ask() -> void:
	print("[story] asking for a pilot")
	act = Act.ASK
	_ask_t = ASK_TIMEOUT
	_set_objective("Press [Y] to say you're a pilot. (You are not.)")


func _volunteer(peer: int, eager: bool) -> void:
	act = Act.COCKPIT
	var who := world.display_name(peer)
	print("[story] volunteer: %s (%s)" % [who, "eager" if eager else "picked"])
	_lines.clear()
	_line_t = 0.0
	if eager:
		_queue(who, LIES.pick_random(), 3.5)
		_queue("ATTENDANT", "Oh thank goodness! The cockpit's at the front. I've unlocked the door!", 3.5, _unlock)
	else:
		_queue("ATTENDANT", "Nobody?! Fine. YOU. %s. You have pilot energy." % who, 3.5)
		_queue(who, "...I do? I mean— yes. Yes I do.", 3.0)
		_queue("ATTENDANT", "Cockpit's at the front. Door's open. GO!", 3.0, _unlock)
	world.notify(peer, "You're the pilot now. Good luck. You'll need it.")


func _unlock() -> void:
	print("[story] cockpit unlocked")
	cockpit_open = true
	world.locked_doors.erase("cockpit")
	world.set_plane("door:cockpit", true)
	_set_objective("Get to the cockpit and fly the plane!")
	_chaos_t = randf_range(5.0, 8.0)


func _on_shout(peer: int, _args: Array) -> void:
	if act == Act.ASK:
		_volunteer(peer, true)
		return
	if _time - float(_shouted.get(peer, -10.0)) < SHOUT_COOLDOWN:
		return
	_shouted[peer] = _time
	world.say(world.display_name(peer), SHOUTS.pick_random(), 2.5)
	world.npcs.panic_all(0.04)


func _on_pilot_changed(peer: int) -> void:
	if not world.is_server() or act == Act.ENDED:
		return
	if peer == 0:
		if cockpit_open:
			_set_objective("Nobody is flying! Get back in the pilot seat!")
			world.say("TOWER", "Flight 404, your pilot seat looks... empty? Please tell me it's not empty.", 3.5)
		return
	print("[story] pilot: %s" % world.display_name(peer))
	_set_objective("Land at the airport (HUD marker). Gear down [G] before touchdown!")
	if _taught:
		return
	_taught = true
	_lines.clear()
	_line_t = 0.0
	_queue("TOWER", "Flight 404, this is TOWER. Who am I talking to?", 3.0)
	_queue(world.display_name(peer), "...The pilot. Obviously.", 2.5)
	_queue("TOWER", "Riiight. [%s] nose down, [%s] nose up. [A]/[D] to bank." % [PITCH_DOWN_KEY, PITCH_UP_KEY], 4.0)
	_queue("TOWER", "[Shift]/[Ctrl] throttle up and down. [G] drops the landing gear.", 4.0)
	_queue("TOWER", "The airport is marked on your HUD. Land heading north. Gently. PLEASE.", 4.0)


# --- Simulation (host) -----------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if not world.is_server():
		return
	_time += dt
	_run_lines(dt)
	var f := world.flight
	if f.phase != _flight_phase:
		_flight_phase = f.phase
		_on_flight_phase()
	if act == Act.ASK:
		_ask_t -= dt
		if _ask_t <= 0.0 and not world.players.is_empty():
			_volunteer(world.players.keys().pick_random(), false)
	if _nudge != 0.0 and f.phase == FlightModel.Phase.FLYING:
		var step := clampf(_nudge, -NUDGE_RATE * dt, NUDGE_RATE * dt)
		f.pitch += step
		_nudge -= step
	if _float_t > 0.0:
		_float_t -= dt
		f.bump = -0.85
	if not cockpit_open or act == Act.ENDED or f.phase != FlightModel.Phase.FLYING:
		return
	_chaos_t -= dt
	if _chaos_t <= 0.0:
		_chaos_t = randf_range(CHAOS_MIN, CHAOS_MAX)
		_chaos()
	if world.pilot_peer != 0:
		_check_t -= dt
		if _check_t <= 0.0:
			_check_t = 1.0
			_coach()


func _on_flight_phase() -> void:
	var f := world.flight
	match f.phase:
		FlightModel.Phase.ROLLING:
			print("[story] touchdown")
			_lines.clear()
			world.say("TOWER", "TOUCHDOWN! ...You actually did it?! Brakes are automatic. Mostly.", 3.5)
			if not f.touchdown.get("on_runway", true):
				_queue("TOWER", "...That's a field. But we'll allow it.", 3.0)
			_line_t = 4.0
		FlightModel.Phase.LANDED:
			print("[story] landed")
			act = Act.ENDED
			_lines.clear()
			world.say("ATTENDANT", "Ladies and gentlemen... we're alive?", 4.0)
			world.npcs.attendant_say("WE'RE ALIVE?!")
			_set_objective("You landed! Nobody tell the airline.")
		FlightModel.Phase.CRASHED:
			print("[story] crashed: %s" % f.touchdown.get("reason", "unknown"))
			act = Act.ENDED
			_lines.clear()
			world.say("TOWER", CRASH.pick_random(), 4.0)
			_set_objective("Well... that happened.")


# --- Chaos events ----------------------------------------------------------------------

func _chaos() -> void:
	var options: Array = CHAOS.filter(func(k: String) -> bool: return k != _last_chaos and _chaos_ok(k))
	if options.is_empty():
		return
	var k: String = options.pick_random()
	_last_chaos = k
	print("[story] chaos: " + k)
	var plane := world.plane
	match k:
		"turbulence":
			world.flight.bump = 1.0
			_nudge += randf_range(-0.06, 0.06)
			world.shake_all(0.8)
			for id in world.objects:
				var rb := world.objects[id] as RigidBody3D
				if rb and not rb.freeze:
					rb.apply_central_impulse(Vector3(randf_range(-3, 3), randf_range(2, 5), randf_range(-3, 3)) * rb.mass)
			for peer in world.players:
				world.push_player(peer, Vector3(randf_range(-4, 4), 3.0, randf_range(-4, 4)))
			world.npcs.panic_all(0.5)
			world.say("ATTENDANT", "TURBULENCE! Hold onto something! Or someone!", 3.0)
		"bird":
			var intact: Array[int] = []
			for i in plane.windows.size():
				if not plane.windows[i].broken:
					intact.append(i)
			if not intact.is_empty():
				world.break_window(intact.pick_random())
				world.shake_all(0.4)
				world.say("", BIRD.pick_random(), 3.5)
		"fire":
			var i := 0 if not plane.engine_fire[0] else 1
			if not plane.engine_fire[0] and not plane.engine_fire[1]:
				i = randi() % 2
			world.set_plane("fire:%d" % i, true)
			world.shake_all(0.5)
			world.say("ATTENDANT", "The %s engine is ON FIRE! Someone go out on the wing with an extinguisher!"
				% ["left", "right"][i], 4.0)
		"bins":
			for n in randi_range(3, 5):
				var sx := -1.0 if randf() < 0.5 else 1.0
				var local := Vector3(sx * 1.45, 2.25, randf_range(-8.5, 5.0))
				var xf := Transform3D(plane.global_basis * Basis.from_euler(Vector3(randf(), randf(), randf()) * TAU),
					plane.to_global(local))
				var obj := world.spawn_object("suitcase" if randf() < 0.5 else "bag", xf, {}) as RigidBody3D
				if obj:
					obj.linear_velocity = plane.global_basis * Vector3(-sx * randf_range(1.0, 3.0), -1.0, 0)
			world.npcs.panic_all(0.2)
			world.say("", "*CLUNK* The overhead bins have given up. LUGGAGE INCOMING!", 3.0)
		"captain":
			var line: String = CAPTAIN_WAKE.pick_random()
			world.npcs.captain_wake(line)
			world.say("CAPTAIN", line, 3.5)
		"ramp":
			world.set_plane("ramp", true)
			world.say("ATTENDANT", "The cargo ramp just opened BY ITSELF! Someone close the ramp! Lever's in the back!", 4.0)
		"trolley":
			var cart: RigidBody3D = null
			for id in world.objects:
				var o: Node3D = world.objects[id]
				if o.get_meta("kind", "") == "cart":
					cart = o as RigidBody3D
					break
			if cart == null:
				cart = world.spawn_object("cart", Transform3D(plane.global_basis, plane.to_global(Vector3(0, 0.4, -9.3))),
					{}) as RigidBody3D
			if cart:
				cart.linear_velocity = plane.global_basis * Vector3(0, 0, 7.0)
			world.say("ATTENDANT", "The drinks trolley has ESCAPED! It's coming down the aisle! Protect your knees!", 3.5)
		"air_pocket":
			_float_t = FLOAT_TIME
			world.npcs.panic_all(0.3)
			world.say("", "AIR POCKET! Everything is... floating?! WHEEEE!", 3.0)
		"lightning":
			world.damage_plane("hull", 0.15)
			_flash_all()
			world.shake_all(0.7)
			world.flight.bump = 0.6
			world.npcs.panic_all(0.45)
			world.say("", "*KRA-KOOOOM* LIGHTNING! Everyone's hair is now standing up. Even the bald guy's.", 3.5)
		"sputter":
			var e := randi() % 2
			world.damage_plane("engine%d" % e, 0.3)
			world.shake_all(0.4)
			world.npcs.panic_all(0.2)
			world.say("", "*cough* *cough* *BANG* The %s engine is making noises engines shouldn't make."
				% ["left", "right"][e], 3.5)
		"bird_engine":
			var e := randi() % 2
			world.damage_plane("engine%d" % e, 0.35)
			world.shake_all(0.6)
			world.say("", "*FWUMP* A goose flew into the %s engine. The goose did not win. Neither did the engine."
				% ["left", "right"][e], 3.5)
			if randf() < 0.5 and not world.plane.engine_fire[e]:
				world.set_plane("fire:%d" % e, true)
				_queue("ATTENDANT", "And now it's ON FIRE. Extinguisher! Wing! Somebody! GO!", 3.5)


## Health of a plane part (1 = intact, 0 = destroyed).
func _health(part: String) -> float:
	return float(world.plane.damage.get(part, 1.0))


func _chaos_ok(k: String) -> bool:
	var plane := world.plane
	match k:
		"bird":
			return plane.windows.any(func(w: Dictionary) -> bool: return not w.broken)
		"fire":
			return not (plane.engine_fire[0] and plane.engine_fire[1])
		"ramp":
			return not plane.ramp_open
		"captain":
			return is_instance_valid(world.npcs.captain) and world.npcs.captain.state == Npc.State.OUT
	return true


# --- TOWER coaching ----------------------------------------------------------------------

## Picks the most urgent tip for the current flight state (rate-limited).
func _coach() -> void:
	if _time < _coach_t or not _lines.is_empty():
		return
	var f := world.flight
	var thr := FlightModel.runway_threshold()
	var to := Vector2(thr.x - f.pos.x, thr.z - f.pos.z)
	var dist := to.length()
	var alt := f.altitude()
	var heading_off := absf(wrapf(f.yaw, -PI, PI))
	var engine: float = (f.engine_power[0] + f.engine_power[1]) * 0.5
	var lined := absf(f.pos.x - FlightModel.RUNWAY_CENTER.x) < 120.0 and heading_off < 0.3 and f.pos.z > thr.z
	if f.stalled or f.speed < f.stall_speed() + 5.0:
		_tip("stall", "STALL WARNING! Nose down, full throttle! [%s] + [Shift]!" % PITCH_DOWN_KEY)
	elif alt < 120.0 and dist > 2500.0:
		_tip("pull_up", "PULL UP! [%s]! The ground is NOT the airport!" % PITCH_UP_KEY)
	elif alt < 300.0 and not f.gear_down:
		_tip("gear", "Gear! Press [G]! Wheels are not optional!")
	elif f.pitch < -0.3:
		_tip("dive", "That's a LOT of nose-down. Ease up! [%s]" % PITCH_UP_KEY)
	elif absf(f.roll) > 0.6:
		_tip("bank", "Wings level! You're scaring the cows.")
	elif dist < 5000.0 and f.speed > 78.0:
		_tip("fast", "Way too fast! Throttle down with [Ctrl]. This isn't a race.")
	elif dist < 5000.0 and not lined:
		_tip("line_up", "You're not lined up! The runway points north. Use [A]/[D] to line up.")
	elif _health("engine0") < 0.35 or _health("engine1") < 0.35:
		_tip("engine_out", "You've lost an engine! Use more rudder... I mean, bank the other way! Gently!")
	elif _health("wing0") < 0.4 or _health("wing1") < 0.4:
		_tip("wing", "Your wing looks... lighter than it should. Small turns. TINY turns.")
	elif _health("hull") < 0.4 or _health("tail") < 0.4:
		_tip("hull", "Flight 404, your plane is held together by hope and duct tape. Land SOON.")
	elif engine < 0.5:
		_tip("engine", "Your engines sound... crunchy. Maybe deal with that fire?")
	elif dist < 3000.0 and lined and f.gear_down:
		_tip("good", "Lined up, gear down... that's actually... good? Keep it gentle!")
	else:
		_tip("where", "The airport is %.1f km away, %s. Follow the HUD marker." % [dist / 1000.0, _side(to)], 45.0)


func _tip(key: String, text: String, repeat := TIP_REPEAT) -> void:
	if _time - float(_tips.get(key, -1000.0)) < repeat:
		return
	_tips[key] = _time
	_coach_t = _time + COACH_GAP
	world.say("TOWER", text, 3.5)


## "ahead", "to your left" or "to your right", relative to the plane's heading.
func _side(to: Vector2) -> String:
	var yaw := world.flight.yaw
	var right := Vector2(cos(yaw), -sin(yaw))
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var d := to.normalized()
	if d.dot(fwd) > 0.9:
		return "dead ahead"
	if d.dot(fwd) < -0.3:
		return "BEHIND you"
	return "to your right" if d.dot(right) > 0.0 else "to your left"
