extends RefCounted
## Pure contract offers for the Airline: deterministic from the flight number, so the host's
## offer list is reproducible and unit-testable without a World.
## A contract: {id, type: "passengers"|"cargo", kind, name, blurb, count, payout, risk (1..3), accepted}.

const PAX_KINDS: Array[Dictionary] = [
	{"kind": "tourists", "name": "Package Tourists", "blurb": "Easy going. Just want a cheap ride.", "base_payout": 200, "risk": 1, "max_count": 32},
	{"kind": "business", "name": "Business Travellers", "blurb": "Demand coffee and punctuality. Big tips if happy.", "base_payout": 350, "risk": 2, "max_count": 12},
	{"kind": "family", "name": "Family Holiday", "blurb": "Kids run the aisle. Parents tip well for peace.", "base_payout": 300, "risk": 2, "max_count": 16},
	{"kind": "party", "name": "Hen/Stag Party", "blurb": "Rowdy. Stand up, sing, open bins. Hard to control.", "base_payout": 400, "risk": 3, "max_count": 10},
	{"kind": "nervous", "name": "Nervous Flyers", "blurb": "Panic on turbulence. Scream, hide in lav. Need calm.", "base_payout": 350, "risk": 3, "max_count": 8},
	{"kind": "vip", "name": "VIP", "blurb": "One VIP, very picky. Huge payout. Any unmet need angers them.", "base_payout": 1000, "risk": 3, "max_count": 1},
]
const CARGO_KINDS: Array[Dictionary] = [
	{"kind": "luggage", "name": "Standard Luggage", "blurb": "Safe. Just suitcases.", "base_payout": 150, "risk": 1, "max_units": 10},
	{"kind": "mail", "name": "Postal Sacks", "blurb": "Light mail bags. Quick load.", "base_payout": 180, "risk": 1, "max_units": 10},
	{"kind": "fragile", "name": "Antique Vases", "blurb": "Break on hard impacts. Handle with gloves.", "base_payout": 500, "risk": 2, "max_units": 4},
	{"kind": "chickens", "name": "Live Chickens", "blurb": "Coop on pallets. They escape and flap everywhere.", "base_payout": 300, "risk": 2, "max_units": 6},
	{"kind": "crocodile", "name": "Crocodile Crate", "blurb": "Croc breaks out under rough handling. Bites.", "base_payout": 600, "risk": 3, "max_units": 1},
	{"kind": "explosive", "name": "Hazardous Barrels", "blurb": "Explode on hard hits or fire. Run away.", "base_payout": 800, "risk": 3, "max_units": 2},
	{"kind": "mystery", "name": "Mystery Crate", "blurb": "Glowing. Random weird effect. Curiosity killed the cat.", "base_payout": 500, "risk": 2, "max_units": 1},
]


## The same flight number always offers the same contracts in the same order: 3-4 passenger
## contracts (always including tourists as the easy option) and 2-3 cargo contracts, ids 1..n.
static func generate(flight_no: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("DP-%d" % flight_no)
	var out: Array[Dictionary] = []
	var pax := _shuffled(PAX_KINDS.slice(1), rng)
	pax.push_front(PAX_KINDS[0])
	for i in rng.randi_range(3, 4):
		var k: Dictionary = pax[i]
		var count := rng.randi_range(maxi(1, int(k.max_count) / 3), int(k.max_count))
		if k.kind == "tourists":
			count = maxi(count, 8)
		out.append(_contract(k, "passengers", count, rng))
	var cargo := _shuffled(CARGO_KINDS, rng)
	for i in rng.randi_range(2, 3):
		var k: Dictionary = cargo[i]
		out.append(_contract(k, "cargo", rng.randi_range(maxi(1, int(k.max_units) / 2), int(k.max_units)), rng))
	out = _shuffled(out, rng)
	for i in out.size():
		out[i].id = i + 1
	return out


static func _contract(k: Dictionary, type: String, count: int, rng: RandomNumberGenerator) -> Dictionary:
	# +-15% haggle so the same kind is worth a little more or less from flight to flight.
	var payout := int(round(int(k.base_payout) * count * rng.randf_range(0.85, 1.15) / 10.0)) * 10
	return {"id": 0, "type": type, "kind": k.kind, "name": k.name, "blurb": k.blurb, "count": count,
		"payout": payout, "risk": k.risk, "accepted": false}


## Fisher-Yates with the given generator (Array.shuffle() uses the global, unseeded one).
static func _shuffled(items: Array, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var a: Array[Dictionary] = []
	a.assign(items)
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := a[i]
		a[i] = a[j]
		a[j] = t
	return a
