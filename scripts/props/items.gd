extends RefCounted
## Host-side [RMB] behaviour for every Props kind, plus the crate loot table and its jokes.
## Every effect goes through World (object_event, set_plane, say, notify, push_player) so all
## peers see the same thing. `p` is the held prop (scripts/props/prop.gd).

const Looks := preload("res://scripts/props/prop_looks.gd")

const EXTINGUISHER_CHARGES := 60
const TAPE_STRIPS := 3
const FIRE_REACH := 4.5            ## Spray puts out an engine fire within this distance.
const TAPE_REACH := 2.4
const WRENCH_REACH := 2.6
const WRENCH_REPAIR := 0.35

## Weighted crate loot: [kind, weight].
const LOOT := [["extinguisher", 2], ["duct_tape", 2], ["wrench", 2], ["banana", 3], ["rubber_chicken", 2],
	["megaphone", 1], ["parachute", 2], ["snack", 3]]

const FOUND := {
	"extinguisher": ["A FIRE EXTINGUISHER! Finally, something useful.", "Fire extinguisher get! The engines fear you now."],
	"duct_tape": ["Duct tape. The pilot's best friend. (You are the pilot.)", "Duct tape! Fixes windows, morale, everything."],
	"wrench": ["A wrench. You don't know engines, but engines don't know that.", "Wrench acquired. Percussive maintenance time."],
	"banana": ["A single banana. Packed with love. And potassium.", "Banana! Someone smuggled fruit. Respect."],
	"rubber_chicken": ["A rubber chicken. Why. WHY was this in the cargo hold.", "You found a rubber chicken. It stares at you."],
	"megaphone": ["A megaphone! Your opinions are about to get LOUDER.", "Megaphone found. The passengers will regret this."],
	"parachute": ["A PARACHUTE! ...it says 'probably' on it.", "Parachute! Only one, though. Choose your friends wisely."],
	"snack": ["Snacks! The real treasure.", "A bag of snacks. Best find of the flight, honestly."],
}

const SQUEAKS := ["*SQUEAK*", "*squeeeeak*", "*SQUONK*", "*squee-squee*", "*sad squeak*"]
const MEGAPHONE := ["This is your captain speaking. I am not your captain.",
	"Please remain calm. I am not calm.", "Does anyone know what the flappy bits on the wing do?",
	"In the event of a water landing, I don't know, swim?", "We will be landing shortly. Somewhere. Somehow.",
	"Whoever has the window seat, please stop opening it.", "The seatbelt sign is on. It's also on fire.",
	"Snacks will be served after we stop falling.", "Can I get a round of applause for gravity?",
	"Tray tables up! Expectations down!", "If you can hear this, I found a megaphone."]
const SNACK_EATEN := ["Crunchy. Salty. Worth it.", "You ate the whole bag. Pilot fuel.",
	"Delicious. You feel 2% more qualified to fly.", "Those were someone else's. Oh well."]
const DRINK := ["*glug glug* ...*BURRRP*", "*slurp* Ahh. Refreshing panic juice.", "*glug* That was warm. Why was it warm."]
const EXTINGUISHED := ["FIRE'S OUT! I'm basically a firefighter now.", "Take THAT, fire!",
	"Engine fire extinguished. Add it to my pilot résumé."]
const TAPED := ["Fixed it. Structurally... questionable.", "There. Good as new. Don't touch it.",
	"Window patched! The wind can't hurt us now. Probably."]


## Random crate loot kind.
static func roll() -> String:
	var total := 0
	for e: Array in LOOT:
		total += int(e[1])
	var r := randi() % total
	for e: Array in LOOT:
		r -= int(e[1])
		if r < 0:
			return e[0]
	return "snack"


## [RMB] while holding `p`. Holder validation is done by World before this runs.
static func use(p: Variant, peer: int, origin: Vector3, dir: Vector3) -> void:
	var w: World = p.world
	var id := World.net_id(p)
	var who := w.display_name(peer)
	match String(p.kind):
		"extinguisher":
			_spray(p, w, id, peer, origin, dir)
		"duct_tape":
			_tape(p, w, id, peer, origin, dir)
		"wrench":
			_whack(p, w, id, peer, origin, dir)
		"banana":
			if p.state.get("peeled", false):
				w.notify(peer, Looks.HINTS.peel)
			else:
				p.state.peeled = true
				w.object_event(id, "eat")
				w.object_event(id, "peeled")
				w.say(who, "*munch munch* ...now what do I do with this peel?", 2.5)
		"peel":
			w.notify(peer, Looks.HINTS.peel)
		"snack":
			w.object_event(id, "eat")
			w.notify(peer, SNACK_EATEN.pick_random())
			w.despawn_object(id)
		"rubber_chicken":
			p.cooldown = 0.3
			w.object_event(id, "squeak")
			w.say(who, SQUEAKS.pick_random(), 1.5)
		"megaphone":
			p.cooldown = 2.0
			w.object_event(id, "horn")
			w.say(who, String(MEGAPHONE.pick_random()).to_upper(), 3.5)
			if w.npcs and w.npcs.has_method("panic_all"):
				w.npcs.call("panic_all", 0.15)
		"parachute":
			w.notify(peer, "You check the straps. Probably fine. Only one way to find out.")
		"can":
			if p.state.get("empty", false):
				w.notify(peer, "It's empty. You shake it anyway, hopefully.")
			else:
				p.state.empty = true
				w.object_event(id, "chomp")
				w.say(who, DRINK.pick_random(), 2.0)
		"pillow":
			p.cooldown = 3.0
			w.say(who, "*takes a 2-second power nap* ...I'M AWAKE.", 2.5)
		"laptop":
			w.notify(peer, "412 unread emails. You close the laptop. Not today.")
		"suitcase", "bag":
			w.notify(peer, ["It's full of socks.", "Just a single sandwich in there. Respect.",
				"It's locked. 0000? No. 1234? ...yes."].pick_random())
		_:
			w.notify(peer, "You wave the %s around. Nothing happens." % Looks.display_name(p.kind))


static func _spray(p: Variant, w: World, id: int, peer: int, origin: Vector3, dir: Vector3) -> void:
	var charges := int(p.state.get("charges", EXTINGUISHER_CHARGES))
	if charges <= 0:
		w.notify(peer, "*pfft* It's empty. You are now holding a red rock.")
		return
	p.state.charges = charges - 1
	p.cooldown = 0.12
	w.object_event(id, "spray", [dir])
	var pl: Player = w.players.get(peer)
	if pl == null:
		return
	for i in 2:
		var fire: Vector3 = w.plane.engine_fire_point(i)
		if w.plane.engine_fire[i] and (pl.global_position.distance_to(fire) <= FIRE_REACH
				or origin.distance_to(fire) <= FIRE_REACH):
			w.set_plane("fire:%d" % i, false)
			w.add_stat("fires_put_out")
			w.say(w.display_name(peer), EXTINGUISHED.pick_random(), 3.0)
	# Newton's third law, but funnier: a stronger kick outside makes it a jetpack.
	var kick := 4.0 if w.plane.is_outside(pl.global_position) else 1.6
	w.push_player(peer, -dir * kick)
	if charges - 1 == 10:
		w.notify(peer, "The extinguisher is sputtering. 10 puffs left.")


static func _tape(p: Variant, w: World, id: int, peer: int, origin: Vector3, dir: Vector3) -> void:
	var probe := origin + dir * 0.8
	var best := -1
	var best_d := TAPE_REACH
	for i in w.plane.windows.size():
		if not w.plane.windows[i].broken:
			continue
		var d := w.plane.to_global(w.plane.windows[i].pos).distance_to(probe)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		w.notify(peer, "No broken window in reach. You tape your own mouth shut instead. Mmmf.")
		return
	var strips := int(p.state.get("strips", TAPE_STRIPS)) - 1
	p.state.strips = strips
	w.set_plane("window:%d" % best, false)
	w.object_event(id, "tape")
	w.say(w.display_name(peer), TAPED.pick_random(), 2.5)
	if strips <= 0:
		w.notify(peer, "That was the last strip. The roll is just cardboard now.")
		w.despawn_object(id)
	else:
		w.notify(peer, "%d strip%s left." % [strips, "" if strips == 1 else "s"])


static func _whack(p: Variant, w: World, id: int, peer: int, origin: Vector3, dir: Vector3) -> void:
	p.cooldown = 0.5
	var pl: Player = w.players.get(peer)
	var e := w.plane.engine_near(origin + dir * 1.0, 3.0)
	if e < 0 and pl:
		e = w.plane.engine_near(pl.global_position, 3.5)
	if e >= 0:
		w.repair_engine(e, WRENCH_REPAIR)
		w.object_event(id, "clang")
		w.notify(peer, "CLANG! %s engine at %d%%. Science!" % [["Left", "Right"][e], int(w.flight.engine_power[e] * 100.0)])
		return
	var exclude: Array[RID] = [p.get_rid()]
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * WRENCH_REACH, Layers.PROP | Layers.NPC, exclude)
	var hit: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(q)
	var target: Variant = hit.get("collider")
	if target == null:
		w.notify(peer, "You whack the air menacingly. The air is unbothered.")
		return
	w.object_event(id, "clang")
	if target.has_method("smash") and target.smash(peer):
		return
	if target is RigidBody3D:
		var body := target as RigidBody3D
		body.apply_central_impulse((dir + Vector3(0, 0.3, 0)) * clampf(body.mass * 3.0, 1.0, 60.0))
	if target.has_method("on_punched"):
		target.on_punched(peer, dir)
