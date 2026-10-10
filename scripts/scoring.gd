class_name Scoring
## End-of-round result from the flight outcome and the chaos stats.


static func result(f: FlightModel, s: Dictionary) -> Dictionary:
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
		"sink": td.get("sink", 0.0), "score": maxi(score, 0), "chaos": chaos, "stats": s.duplicate()}
