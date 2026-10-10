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


## --- Airline payout (pure static function) -------------------------------------------
## contracts: Array of contract dicts (from Airline.contracts)
## passenger_report: contract_id -> {boarded, delivered, lost, satisfaction}
## cargo_report: contract_id -> {units, delivered, condition}
## flight_info: {landed, on_runway, diverted, crashed}
## damage: plane.damage dict (part -> health 0..1)
## tips: Array of {peer, amount, reason}
## penalties: Array of {amount, reason}
## bank: current bank balance (before this flight)
## Returns: {line_items: Array[{label, amount}], total: int, new_bank: int}
static func payout(contracts: Array, passenger_report: Dictionary, cargo_report: Dictionary,
		flight_info: Dictionary, damage: Dictionary, tips: Array, penalties: Array, bank: int) -> Dictionary:
	
	var line_items: Array[Dictionary] = []
	var total := 0
	
	# Passenger contracts
	for c in contracts:
		if c.type != "passengers" or not c.accepted:
			continue
		var report: Dictionary = passenger_report.get(c.id, {})
		var boarded: int = int(report.get("boarded", 0))
		var delivered: int = int(report.get("delivered", 0))
		var lost: int = int(report.get("lost", 0))
		var satisfaction: float = float(report.get("satisfaction", 1.0))
		
		if boarded == 0:
			line_items.append({"label": "%s (no shows)" % c.name, "amount": 0})
			continue
		
		var base: int = c.payout
		# Satisfaction multiplier: 0.5 to 1.5
		var mult: float = lerp(0.5, 1.5, satisfaction)
		var earned := int(base * mult * (delivered / float(max(boarded, 1))))
		
		line_items.append({"label": "%s (%d/%d delivered, sat %.0f%%)" % [c.name, delivered, boarded, satisfaction * 100], "amount": earned})
		total += earned
		
		if lost > 0:
			var penalty := lost * 150  # Penalty per lost passenger
			line_items.append({"label": "Lost passengers: %d × $150" % lost, "amount": -penalty})
			total -= penalty
	
	# Cargo contracts
	for c in contracts:
		if c.type != "cargo" or not c.accepted:
			continue
		var report: Dictionary = cargo_report.get(c.id, {})
		var units: int = int(report.get("units", 0))
		var delivered: int = int(report.get("delivered", 0))
		var condition: float = float(report.get("condition", 1.0))
		
		if units == 0:
			line_items.append({"label": "%s (not loaded)" % c.name, "amount": 0})
			continue
		
		var base: int = c.payout
		# Condition multiplier: 0.2 to 1.0
		var mult: float = lerp(0.2, 1.0, condition)
		var earned := int(base * mult * (delivered / max(units, 1)))
		
		line_items.append({"label": "%s (%d/%d units, cond %.0f%%)" % [c.name, delivered, units, condition * 100], "amount": earned})
		total += earned
	
	# Tips
	var tips_total := 0
	for t in tips:
		var amt := int(t.amount)
		if amt > 0:
			line_items.append({"label": "Tip: %s" % t.reason, "amount": amt})
			tips_total += amt
	total += tips_total
	
	# Penalties
	var penalties_total := 0
	for p in penalties:
		var amt := int(p.amount)
		if amt > 0:
			line_items.append({"label": "Penalty: %s" % p.reason, "amount": -amt})
			penalties_total += amt
	total -= penalties_total
	
	# Plane repairs (damage)
	var repair_cost := 0
	var part_names := {
		"engine0": "Left Engine", "engine1": "Right Engine",
		"wing0": "Left Wing", "wing1": "Right Wing",
		"tail": "Tail", "hull": "Hull"
	}
	for part in damage:
		var hp := float(damage[part])
		if hp < 1.0:
			var cost := int((1.0 - hp) * 500)  # Up to 500 per part
			repair_cost += cost
			line_items.append({"label": "Repair: %s (%d%% damage)" % [part_names.get(part, part), roundi((1.0 - hp) * 100)], "amount": -cost})
	total -= repair_cost
	
	# Diversion / crash penalties
	if flight_info.get("diverted", false):
		line_items.append({"label": "Diversion penalty", "amount": -1000})
		total -= 1000
	if flight_info.get("crashed", false):
		line_items.append({"label": "Crash penalty", "amount": -2000})
		total -= 2000
	
	var new_bank := bank + total
	
	return {"line_items": line_items, "total": total, "new_bank": new_bank,
		"tips_total": tips_total, "penalties_total": penalties_total, "repair_cost": repair_cost}


## --- Unit tests (run from tests/run_tests.gd) -----------------------------------------
static func _test_payout_all_delivered() -> bool:
	var contracts := [
		{"id": 1, "type": "passengers", "kind": "tourists", "name": "Tourists", "count": 10, "payout": 2000, "risk": 1, "accepted": true},
		{"id": 2, "type": "cargo", "kind": "luggage", "name": "Luggage", "count": 5, "payout": 750, "risk": 1, "accepted": true},
	]
	var pax_report := {1: {"boarded": 10, "delivered": 10, "lost": 0, "satisfaction": 1.0}}
	var cargo_report := {2: {"units": 5, "delivered": 5, "condition": 1.0}}
	var flight_info := {"landed": true, "on_runway": true, "diverted": false, "crashed": false}
	var damage := {"engine0": 1.0, "engine1": 1.0, "wing0": 1.0, "wing1": 1.0, "tail": 1.0, "hull": 1.0}
	var tips := [{"peer": 1, "amount": 50, "reason": "Great service"}]
	var penalties := []
	var r := payout(contracts, pax_report, cargo_report, flight_info, damage, tips, penalties, 1000)
	return r.total == 2800 and r.new_bank == 3800  # 2000 + 750 + 50 = 2800

static func _test_payout_passengers_lost() -> bool:
	var contracts := [
		{"id": 1, "type": "passengers", "kind": "tourists", "name": "Tourists", "count": 10, "payout": 2000, "risk": 1, "accepted": true},
	]
	var pax_report := {1: {"boarded": 10, "delivered": 7, "lost": 3, "satisfaction": 0.7}}
	var cargo_report := {}
	var flight_info := {"landed": true, "on_runway": true, "diverted": false, "crashed": false}
	var damage := {"engine0": 1.0, "engine1": 1.0, "wing0": 1.0, "wing1": 1.0, "tail": 1.0, "hull": 1.0}
	var tips := []
	var penalties := []
	var r := payout(contracts, pax_report, cargo_report, flight_info, damage, tips, penalties, 0)
	# base 2000 * 0.85 sat_mult * 0.7 delivered = 1190, minus 3*150 = 450 lost penalty = 740
	return r.total == 740

static func _test_payout_crash() -> bool:
	var contracts := [
		{"id": 1, "type": "passengers", "kind": "tourists", "name": "Tourists", "count": 10, "payout": 2000, "risk": 1, "accepted": true},
	]
	var pax_report := {1: {"boarded": 10, "delivered": 0, "lost": 10, "satisfaction": 0.0}}
	var cargo_report := {}
	var flight_info := {"landed": false, "on_runway": false, "diverted": false, "crashed": true}
	var damage := {"engine0": 0.5, "engine1": 1.0, "wing0": 1.0, "wing1": 1.0, "tail": 1.0, "hull": 1.0}
	var tips := []
	var penalties := []
	var r := payout(contracts, pax_report, cargo_report, flight_info, damage, tips, penalties, 5000)
	# 0 from pax (lost all) - 1500 lost penalty - 2000 crash - 250 repair = -3750, bank 5000 -> 1250
	return r.total == -3750 and r.new_bank == 1250

static func _test_payout_diversion() -> bool:
	var contracts := [
		{"id": 1, "type": "passengers", "kind": "tourists", "name": "Tourists", "count": 10, "payout": 2000, "risk": 1, "accepted": true},
	]
	var pax_report := {1: {"boarded": 10, "delivered": 10, "lost": 0, "satisfaction": 1.0}}
	var cargo_report := {}
	var flight_info := {"landed": true, "on_runway": false, "diverted": true, "crashed": false}
	var damage := {"engine0": 1.0, "engine1": 1.0, "wing0": 1.0, "wing1": 1.0, "tail": 1.0, "hull": 1.0}
	var tips := []
	var penalties := []
	var r := payout(contracts, pax_report, cargo_report, flight_info, damage, tips, penalties, 0)
	# 2000 - 1000 diversion = 1000
	return r.total == 1000

static func _test_payout_damaged_cargo() -> bool:
	var contracts := [
		{"id": 1, "type": "cargo", "kind": "fragile", "name": "Antiques", "count": 4, "payout": 2000, "risk": 2, "accepted": true},
	]
	var pax_report := {}
	var cargo_report := {1: {"units": 4, "delivered": 4, "condition": 0.5}}
	var flight_info := {"landed": true, "on_runway": true, "diverted": false, "crashed": false}
	var damage := {"engine0": 1.0, "engine1": 1.0, "wing0": 1.0, "wing1": 1.0, "tail": 1.0, "hull": 1.0}
	var tips := []
	var penalties := []
	var r := payout(contracts, pax_report, cargo_report, flight_info, damage, tips, penalties, 0)
	# base 2000 * 0.6 cond * 1.0 delivered = 1200
	return r.total == 1200

static func _test_payout_empty_manifest() -> bool:
	var contracts := [
		{"id": 1, "type": "passengers", "kind": "tourists", "name": "Tourists", "count": 10, "payout": 2000, "risk": 1, "accepted": false},
	]
	var pax_report := {}
	var cargo_report := {}
	var flight_info := {"landed": true, "on_runway": true, "diverted": false, "crashed": false}
	var damage := {"engine0": 1.0, "engine1": 1.0, "wing0": 1.0, "wing1": 1.0, "tail": 1.0, "hull": 1.0}
	var tips := []
	var penalties := []
	var r := payout(contracts, pax_report, cargo_report, flight_info, damage, tips, penalties, 100)
	return r.total == 0 and r.new_bank == 100
