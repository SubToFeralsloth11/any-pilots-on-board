class_name PassengerMind
extends RefCounted
## Host-only wants and mood of one passenger: timed requests (meal, drink, coffee, blanket)
## with a patience clock, satisfaction 0..1, and the contract kind's temperament (who tips, who
## sings, who swings at the crew, who goes for the emergency exit). The Npc body asks it what
## to do; it never touches physics itself.

const NEEDS := ["meal", "drink", "coffee", "blanket"]
## patience (s), every: seconds between requests, needs: weights in NEEDS order, tip ($ for a
## prompt serve), unmet: satisfaction lost per expired request, rowdy: party-style mischief,
## fear: turbulence sensitivity, start: satisfaction at boarding, picky: wrong-item penalty.
const PROFILES := {
	"tourists": {"patience": 45.0, "every": Vector2(28, 55), "needs": [3, 3, 1, 1], "tip": 12, "unmet": 0.12,
		"rowdy": 0.0, "fear": 1.0, "start": 0.8, "picky": 1.0},
	"business": {"patience": 32.0, "every": Vector2(24, 42), "needs": [1, 1, 6, 0], "tip": 35, "unmet": 0.18,
		"rowdy": 0.0, "fear": 0.8, "start": 0.7, "picky": 1.5},
	"family": {"patience": 38.0, "every": Vector2(25, 48), "needs": [3, 4, 0, 2], "tip": 18, "unmet": 0.14,
		"rowdy": 0.0, "fear": 1.2, "start": 0.75, "picky": 1.0},
	"party": {"patience": 30.0, "every": Vector2(20, 38), "needs": [1, 6, 0, 0], "tip": 15, "unmet": 0.15,
		"rowdy": 1.0, "fear": 0.6, "start": 0.65, "picky": 1.0},
	"nervous": {"patience": 35.0, "every": Vector2(25, 48), "needs": [0, 2, 1, 4], "tip": 15, "unmet": 0.15,
		"rowdy": 0.0, "fear": 2.6, "start": 0.6, "picky": 1.0},
	"vip": {"patience": 22.0, "every": Vector2(16, 30), "needs": [2, 2, 2, 2], "tip": 120, "unmet": 0.35,
		"rowdy": 0.0, "fear": 1.2, "start": 0.6, "picky": 3.0},
}
const ASK := {
	"meal": ["Excuse me, is there FOOD on this flight?", "I'm starving. Meal, please!", "Chicken or pasta? Either!"],
	"drink": ["Could I get a juice?", "Something to drink, please!", "My throat is a DESERT."],
	"coffee": ["Coffee. Black. NOW.", "I need caffeine to survive this.", "Is there coffee? Please say yes."],
	"blanket": ["It's freezing in here!", "Could I have a blanket?", "My toes are icicles..."],
}
const COMPLAIN := {
	"meal": ["I'm STILL waiting for my meal!", "Worst. Service. EVER.", "I'll be eating my seatbelt then."],
	"drink": ["Forget the drink. I'll lick the window.", "Is this airline allergic to WATER?!"],
	"coffee": ["NO COFFEE?! I'm writing a review!", "I can't feel my productivity!"],
	"blanket": ["Fine. I'll freeze. Thanks a lot.", "I'm turning into a popsicle here!"],
}
const THANKS := ["Oh, lovely!", "Finally! Thank you!", "Now THAT is service.", "You're a star!", "Mmm!"]
const WRONG := {
	"meal": "A tray? I didn't ask for food!", "drink": "That's not what I wanted!",
	"coffee": "Coffee?! Do I LOOK like I want coffee?", "blanket": "A blanket? I'm not cold!",
}
const SINGS := ["*singing* WE'RE ALL GOING ON A... HOLIDAAAY!", "LA LA LAAAA! Everybody now!",
	"*drunk karaoke noises*", "Another round for the whole PLANE!", "WOOOOO! PARTY AT 30,000 FEET!"]
const SHOUTS := ["This is the WORST airline in HISTORY!", "I want to speak to the MANAGER!",
	"I demand a REFUND!", "Do you know who I AM?!", "I'm getting off this plane!"]
const PUNCHES := ["Take THAT, flight attendant!", "Square up, crew!", "Service THIS!"]
const KID := ["Wheeee!", "Are we there yet? Are we there yet?", "Can I see the pilot?!", "*giggles*",
	"I'm a plane! NYYEEOOOWW!"]
const CALMED := ["Fine! FINE! I'll sit down!", "Put me down! ...okay, I'm sitting.", "Hmph."]
const EXIT := "I'M GETTING OFF THIS PLANE!"

var npc: Node                 ## The Npc body (npc.gd).
var world: World
var kind := "tourists"
var p: Dictionary
var satisfaction := 0.75
var need := ""
var need_total := 0.0
var need_left := 0.0
var act := ""                 ## Current mischief: sing, shout, bin, punch, exit, wander.
var target_peer := 0          ## Crew member a "punch" act goes after.

var _next_need := 0.0
var _trouble_t := 0.0
var _act_t := 0.0
var _line_t := 0.0


func _init(body: Node, w: World, contract_kind: String) -> void:
	npc = body
	world = w
	kind = contract_kind if PROFILES.has(contract_kind) else "tourists"
	p = PROFILES[kind]
	satisfaction = float(p.start)
	_next_need = randf_range(8.0, 24.0)
	_trouble_t = randf_range(15.0, 30.0)


func change(amount: float) -> void:
	satisfaction = clampf(satisfaction + amount, 0.0, 1.0)


## Very unhappy: ignores the seatbelt sign and makes trouble.
func enraged() -> bool:
	return satisfaction < 0.15


func _in_flight() -> bool:
	return world.airline != null and world.airline.phase == "flight" and not world.round_over


## Called every few physics frames. `seated` = in their seat and not panicking.
func tick(dt: float, seated: bool) -> void:
	if not _in_flight():
		return
	if npc.scared:
		change(-0.004 * float(p.fear) * dt)
	if need == "":
		if seated:
			_next_need -= dt
			if _next_need <= 0.0:
				_ask()
	else:
		need_left -= dt
		if need_left <= 0.0:
			_unmet()
	if seated:
		_trouble_t -= dt
		if _trouble_t <= 0.0:
			_trouble_t = randf_range(7.0, 14.0)
			_maybe_trouble()


func _ask() -> void:
	var weights: Array = p.needs
	var total := 0
	for w: int in weights:
		total += w
	var roll := randi() % maxi(total, 1)
	need = NEEDS[0]
	for i in NEEDS.size():
		roll -= int(weights[i])
		if roll < 0:
			need = NEEDS[i]
			break
	need_total = float(p.patience) * randf_range(0.85, 1.15)
	need_left = need_total
	npc.show_need(need, need_total, need_left)
	npc.say_line((ASK[need] as Array).pick_random())


func _unmet() -> void:
	change(-float(p.unmet))
	world.say(npc.display, (COMPLAIN[need] as Array).pick_random(), 3.0)
	need = ""
	npc.show_need("", 0.0, 0.0)
	var every: Vector2 = p.every
	_next_need = randf_range(every.x, every.y) * 0.6


## Host. Crew hands over `item`. Returns the tip (> 0), or -1 when it was the wrong thing.
func serve(peer: int, item: String) -> int:
	if need != item:
		change(-0.03 * float(p.picky))
		npc.say_line(WRONG.get(item, "That's not what I wanted!") if need != "" else "I didn't ask for anything!")
		return -1
	var speed := clampf(need_left / maxf(need_total, 0.01), 0.0, 1.0)
	change(0.18 + 0.14 * speed)
	var tip := maxi(1, roundi(float(p.tip) * (0.5 + speed) * (0.5 + satisfaction)))
	world.airline.add_tip(peer, tip, "%s served %s" % [npc.display, item])
	need = ""
	npc.show_need("", 0.0, 0.0)
	npc.eat(item)
	npc.say_line(THANKS.pick_random())
	var every: Vector2 = p.every
	_next_need = randf_range(every.x, every.y)
	return tip


## Picks some mischief for a seated passenger, depending on kind and mood.
func _maybe_trouble() -> void:
	var belt: bool = world.seatbelt_sign
	if npc.child:
		if not belt and randf() < 0.35:
			_start("wander", npc.aisle_spot(randf_range(-8.0, 5.0)), 4.0, KID.pick_random())
		return
	if belt and not enraged():
		return
	var crew := _nearest_crew(10.0)
	if kind == "party" and randf() < float(p.rowdy) * (1.2 - satisfaction) * 0.45:
		var options := ["sing", "sing", "bin"]
		if satisfaction < 0.5 and crew != 0:
			options.append("punch")
		_begin(options.pick_random(), crew)
		return
	if satisfaction >= 0.3 or randf() > 0.6:
		return
	if enraged() and world.flight.phase == FlightModel.Phase.FLYING and randf() < 0.35:
		_begin("exit", 0)
	elif crew != 0 and randf() < 0.45:
		_begin("punch", crew)
	else:
		_begin("shout", 0)


func _begin(what: String, crew: int) -> void:
	match what:
		"sing":
			_start("sing", npc.aisle_spot(), 8.0, SINGS.pick_random())
		"bin":
			_start("bin", npc.aisle_spot(), 2.5, "Where's my duty free? It's in here somewhere!")
		"shout":
			_start("shout", npc.aisle_spot(), 6.0, SHOUTS.pick_random())
		"punch":
			target_peer = crew
			_start("punch", npc.crew_spot(crew), 14.0, "Hey! YOU! Come here!")
		"exit":
			var side := "left" if npc.seat.x < 0.0 else "right"
			_start("exit", npc.exit_spot(side), 3.0, EXIT)


func _start(what: String, spot: Vector3, duration: float, line: String) -> void:
	act = what
	_act_t = duration
	_line_t = 2.5
	npc.roam(spot)
	world.say(npc.display, line, 3.0)


## Host. Called while the passenger stands at the mischief spot. Returns false when done.
func stand_tick(dt: float) -> bool:
	_act_t -= dt
	_line_t -= dt
	match act:
		"sing":
			if _line_t <= 0.0:
				_line_t = randf_range(2.5, 4.0)
				npc.say_line(SINGS.pick_random())
				world.npcs.panic_near(npc, 0.05)
		"shout":
			if _line_t <= 0.0:
				_line_t = randf_range(2.5, 4.0)
				npc.say_line(SHOUTS.pick_random())
		"bin":
			if _act_t > 0.0 and _line_t <= 0.0:
				_line_t = 99.0
				world.npcs.open_bin(npc)
		"punch":
			var pl: Player = world.players.get(target_peer)
			if pl == null or world.pilot_peer == target_peer:
				return false
			var to: Vector3 = pl.global_position - npc.global_position
			if to.length() < 1.4:
				var up := world.plane.global_basis.y
				world.push_player(target_peer, (to - up * to.dot(up)).normalized() * 7.0 + up * 3.0)
				world.shake_all(0.15)
				world.say(npc.display, PUNCHES.pick_random(), 2.5)
				return false
			if to.length() > 1.6:
				npc.roam(npc.crew_spot(target_peer))
		"exit":
			if _line_t <= 0.0 and _act_t < 1.5:
				_line_t = 99.0
				var side := "left" if npc.seat.x < 0.0 else "right"
				if world.flight.phase == FlightModel.Phase.FLYING and not world.plane.doors[side].open:
					world.set_plane("door:" + side, true)
					world.say(npc.display, "*yanks the emergency handle*", 2.5)
	return _act_t > 0.0


func end_act() -> void:
	act = ""
	target_peer = 0


## Crew grabbed or carried them: mischief stops for a while.
func calm_down() -> void:
	if act != "" or satisfaction < 0.3:
		npc.say_line(CALMED.pick_random())
	end_act()
	_trouble_t = randf_range(35.0, 50.0)
	change(-0.03)


func jolt(s: float) -> void:
	change(-0.012 * s * float(p.fear))
	if float(p.fear) > 2.0:
		npc.add_panic(0.45 * s)
		if randf() < 0.5:
			world.say(npc.display, ["AAAAAAH!", "WE'RE GOING DOWN!", "I KNEW IT! I KNEW THIS WOULD HAPPEN!",
				"Hold me! Someone HOLD ME!"].pick_random(), 2.0)


func pocket() -> void:
	change(-0.04 * float(p.fear))
	if float(p.fear) > 2.0:
		npc.add_panic(0.8)


func _nearest_crew(reach: float) -> int:
	var best := 0
	var best_d := reach
	for peer: int in world.players:
		if peer == world.pilot_peer:
			continue
		var d: float = (world.players[peer] as Player).global_position.distance_to(npc.global_position)
		if d < best_d:
			best_d = d
			best = peer
	return best
