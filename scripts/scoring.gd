class_name Scoring
## End-of-round result from the flight outcome and the chaos stats, plus per-player crew awards.

## Most-of-a-stat awards: [stat key, title, blurb (%s = formatted number)]. Order = display order.
const AWARDS := [
	["windows_broken", "Window Enthusiast", "%s windows opened. Permanently."],
	["times_fell_out", "Frequent Flyer (outside the plane)", "Left the plane %s times. Without the plane."],
	["pilot_seconds", "Captain Now", "%s seconds at the controls. Nobody stopped them."],
	["fumbles", "Butterfingers", "Lost grip on %s things."],
	["things_thrown", "Throwing Arm", "%s things yeeted across the cabin."],
	["punches_landed", "Brawler", "%s punches thrown at the furniture."],
	["players_punched", "Workplace Incident", "Punched the crew %s times. HR has been notified."],
]
const VIOLENCE := ["punches_landed", "players_punched"]


static func result(f: FlightModel, s: Dictionary, player_stats := {}, names := {}) -> Dictionary:
	var landed := f.phase == FlightModel.Phase.LANDED
	var td := f.touchdown
	var chaos := int(s.windows_broken) * 50 + int(s.items_lost) * 10 + int(s.things_broken) * 15 \
		+ int(s.players_fell) * 75 + int(s.passengers_lost) * 100
	var score := 0
	if landed:
		score = 1000 + (500 if td.get("on_runway", false) else 0) \
			+ int(maxf(0.0, 500.0 - float(td.get("sink", 5.0)) * 100.0)) \
			- int(s.passengers_lost) * 150 - int(s.windows_broken) * 25
	return {"landed": landed, "reason": td.get("reason", ""), "on_runway": td.get("on_runway", false),
		"sink": td.get("sink", 0.0), "score": maxi(score, 0), "chaos": chaos, "stats": s.duplicate(),
		"player_stats": player_stats.duplicate(true), "awards": awards(player_stats, names)}


## Pure: picks the funny awards. Every peer in `names` competes (missing stats count as 0).
## A "most" award needs a non-zero leader; ties go to the lowest peer id. "Pacifist" goes to
## the lowest peer with no punches at all, only when someone else did punch (or playing solo).
## Returns [{title, peer, name, value, text}].
static func awards(player_stats: Dictionary, names: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var peers: Array = names.keys()
	for p: int in player_stats:
		if not peers.has(p):
			peers.append(p)
	peers.sort()
	for a: Array in AWARDS:
		var best := 0
		var best_val := 0.0
		for p: int in peers:
			var v := _stat(player_stats, p, a[0])
			if v > best_val:
				best_val = v
				best = p
		if best_val > 0.0:
			var shown := str(roundi(best_val))
			out.append({"title": a[1], "peer": best, "name": _name(names, best), "value": best_val,
				"text": a[2] % shown})
	var calm: Array = peers.filter(func(p: int) -> bool: return _violence(player_stats, p) == 0.0)
	if not calm.is_empty() and (peers.size() == 1 or calm.size() < peers.size()):
		out.append({"title": "Pacifist", "peer": calm[0], "name": _name(names, calm[0]), "value": 0.0,
			"text": "0 punches. Suspiciously well behaved."})
	return out


static func _stat(player_stats: Dictionary, peer: int, key: String) -> float:
	return float((player_stats.get(peer, {}) as Dictionary).get(key, 0.0))


static func _violence(player_stats: Dictionary, peer: int) -> float:
	var total := 0.0
	for k: String in VIOLENCE:
		total += _stat(player_stats, peer, k)
	return total


static func _name(names: Dictionary, peer: int) -> String:
	return str(names.get(peer, "Passenger %d" % peer))
