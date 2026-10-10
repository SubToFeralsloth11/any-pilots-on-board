class_name Airline
extends Node
## Airline module: owns the round phase state machine and contract system.
## Host is authoritative; clients receive sync via RPC.

signal phase_changed(phase: String)
signal contracts_changed()
signal bank_changed(new_bank: int)
signal flight_no_changed(new_no: int)

const PHASES := ["manifest", "boarding", "flight", "report"]
const BOARDING_TIMEOUT := 45.0  # seconds
const SEAT_CAPACITY := 32
const CARGO_CAPACITY := 10

# --- Persistence ---
const CFG_PATH := "user://airline.cfg"

# --- State ---
var world: World
var phase: String = "manifest"
var flight_no: int = 1
var bank: int = 0
var contracts: Array[Dictionary] = []
var boarding_timer: float = 0.0
var tips: Array[Dictionary] = []     # {peer: int, amount: int, reason: String}
var penalties: Array[Dictionary] = [] # {amount: int, reason: String}

# --- Setup / populate ---
func setup(w: World) -> void:
	world = w
	_register_actions()
	if w.is_server():
		_load_persisted()
		_generate_contracts()
	else:
		# Clients wait for sync
		pass

func populate() -> void:
	if not world.is_server():
		return
	# Nothing to spawn at round start; passengers/cargo spawn during boarding phase.

# --- Persistence (host only) ---
func _load_persisted() -> void:
	var cf := ConfigFile.new()
	var err := cf.load(CFG_PATH)
	if err == OK:
		bank = int(cf.get_value("airline", "bank", 0))
		flight_no = int(cf.get_value("airline", "flight_no", 1))
		# Ensure flight_no increments per round
		flight_no += 1
	else:
		bank = 0
		flight_no = 1
	_save_persisted()
	# Notify clients of loaded values
	for p in world._ready_peers:
		if p != 1:
			_rpc_sync_phase.rpc_id(p, phase)
			_rpc_sync_flight_no.rpc_id(p, flight_no)
			_rpc_sync_bank.rpc_id(p, bank)
			_rpc_sync_contracts.rpc_id(p, contracts)

func _save_persisted() -> void:
	var cf := ConfigFile.new()
	cf.set_value("airline", "bank", bank)
	cf.set_value("airline", "flight_no", flight_no)
	cf.save(CFG_PATH)

# --- Contract generation (host, deterministic per flight_no) ---
func _generate_contracts() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = flight_no
	
	# Passenger kinds: tourists, business, family, party, nervous, vip
	var pax_kinds: Array[Dictionary] = [
		{"kind": "tourists", "name": "Package Tourists", "blurb": "Easy going. Just want a cheap ride.", "base_payout": 200, "risk": 1, "max_count": 32},
		{"kind": "business", "name": "Business Travellers", "blurb": "Demand coffee and punctuality. Big tips if happy.", "base_payout": 350, "risk": 2, "max_count": 12},
		{"kind": "family", "name": "Family Holiday", "blurb": "Kids run the aisle. Parents tip well for peace.", "base_payout": 300, "risk": 2, "max_count": 16},
		{"kind": "party", "name": "Hen/Stag Party", "blurb": "Rowdy. Stand up, sing, open bins. Hard to control.", "base_payout": 400, "risk": 3, "max_count": 10},
		{"kind": "nervous", "name": "Nervous Flyers", "blurb": "Panic on turbulence. Scream, hide in lav. Need calm.", "base_payout": 350, "risk": 3, "max_count": 8},
		{"kind": "vip", "name": "VIP + Entourage", "blurb": "One VIP, very picky. Huge payout. Any unmet need angers them.", "base_payout": 1000, "risk": 3, "max_count": 4},
	]
	
	# Cargo kinds: luggage, mail, fragile, chickens, crocodile, explosive, mystery
	var cargo_kinds: Array[Dictionary] = [
		{"kind": "luggage", "name": "Standard Luggage", "blurb": "Safe. Just suitcases.", "base_payout": 150, "risk": 1, "max_units": 10},
		{"kind": "mail", "name": "Postal Sacks", "blurb": "Light mail bags. Quick load.", "base_payout": 180, "risk": 1, "max_units": 10},
		{"kind": "fragile", "name": "Antique Vases", "blurb": "Break on hard impacts. Handle with gloves.", "base_payout": 500, "risk": 2, "max_units": 4},
		{"kind": "chickens", "name": "Live Chickens", "blurb": "Coop on pallets. They escape and flap everywhere.", "base_payout": 300, "risk": 2, "max_units": 6},
		{"kind": "crocodile", "name": "Crocodile Crate", "blurb": "Croc breaks out under rough handling. Bites.", "base_payout": 600, "risk": 3, "max_units": 1},
		{"kind": "explosive", "name": "Hazardous Barrels", "blurb": "Explode on hard hits or fire. Run away.", "base_payout": 800, "risk": 3, "max_units": 2},
		{"kind": "mystery", "name": "Mystery Crate", "blurb": "Glowing. Random weird effect. Curiosity killed the cat.", "base_payout": 500, "risk": 2, "max_units": 1},
	]
	
	contracts = []
	var id_counter := 1
	
	# Mix ~6 contracts: 3-4 passenger, 2-3 cargo
	var num_pax := rng.randi_range(3, 4)
	var num_cargo := rng.randi_range(2, 3)
	
	var pax_shuffled := pax_kinds.duplicate()
	pax_shuffled.shuffle()
	var cargo_shuffled := cargo_kinds.duplicate()
	cargo_shuffled.shuffle()
	
	# At least one easy passenger option (tourists)
	var easy_added := false
	for i in range(num_pax):
		var k: Dictionary = pax_shuffled[i % pax_shuffled.size()]
		var count := rng.randi_range(max(4, int(k.max_count / 3)), k.max_count)
		if not easy_added and k.kind == "tourists":
			easy_added = true
			count = max(count, 8)  # Ensure a decent easy option
		var payout: int = k.base_payout * count
		var risk: int = k.risk
		if k.kind == "vip":
			count = 1  # Only 1 VIP per contract
			payout = k.base_payout
		contracts.append({
			"id": id_counter,
			"type": "passengers",
			"kind": k.kind,
			"name": k.name,
			"blurb": k.blurb,
			"count": count,
			"payout": payout,
			"risk": risk,
			"accepted": false
		})
		id_counter += 1
	
	for i in range(num_cargo):
		var k: Dictionary = cargo_shuffled[i % cargo_shuffled.size()]
		var units := rng.randi_range(max(1, int(k.max_units / 2)), k.max_units)
		var payout: int = k.base_payout * units
		var risk: int = k.risk
		contracts.append({
			"id": id_counter,
			"type": "cargo",
			"kind": k.kind,
			"name": k.name,
			"blurb": k.blurb,
			"count": units,
			"payout": payout,
			"risk": risk,
			"accepted": false
		})
		id_counter += 1
	
	# Shuffle final order for presentation
	contracts.shuffle()
	
	for p in world._ready_peers:
		if p != 1:
			_rpc_sync_contracts.rpc_id(p, contracts)
	contracts_changed.emit()

# --- Phase state machine ---
func _physics_process(dt: float) -> void:
	if not world.is_server():
		return
	
	if phase == "boarding":
		boarding_timer -= dt
		if boarding_timer <= 0.0:
			_boarding_timeout()
	
	# TODO: transition from flight to report happens in World._check_round_end

# --- Manifest toggle (any player) ---
func toggle_contract(contract_id: int) -> void:
	if phase != "manifest":
		return
	for c in contracts:
		if c.id == contract_id:
			c.accepted = not c.accepted
			break
	for p in world._ready_peers:
		if p != 1:
			_rpc_sync_contracts.rpc_id(p, contracts)
	contracts_changed.emit()

# --- Manifest confirm / Start boarding (any player, requires >=1 passenger contract) ---
func confirm_manifest(peer: int) -> void:
	if phase != "manifest":
		return
	if accepted("passengers").is_empty():
		world.notify(peer, "Accept at least one passenger contract first.")
		return
	_start_boarding()


## Opens the ramp; the Passengers and Cargo modules spawn the accepted contracts on phase_changed.
func _start_boarding() -> void:
	phase = "boarding"
	boarding_timer = BOARDING_TIMEOUT
	for p in world._ready_peers:
		if p != 1:
			_rpc_sync_phase.rpc_id(p, phase)
	phase_changed.emit(phase)
	world.set_plane("ramp", true)


func _boarding_timeout() -> void:
	world.set_plane("ramp", false)
	phase = "flight"
	for p in world._ready_peers:
		if p != 1:
			_rpc_sync_phase.rpc_id(p, phase)
	phase_changed.emit(phase)

# --- API for other modules (all peers) ---
func accepted(type: String = "") -> Array[Dictionary]:
	if type == "":
		return contracts.filter(func(c: Dictionary) -> bool: return c.accepted)
	return contracts.filter(func(c: Dictionary) -> bool: return c.accepted and c.type == type)

# --- Tips / Penalties (host only) ---
func add_tip(peer_or_0: int, amount: int, reason: String) -> void:
	if not world.is_server():
		return
	tips.append({"peer": peer_or_0, "amount": amount, "reason": reason})
	if peer_or_0 > 0:
		world.add_player_stat(peer_or_0, "tips_received", float(amount))

func add_penalty(amount: int, reason: String) -> void:
	if not world.is_server():
		return
	penalties.append({"amount": amount, "reason": reason})

# --- Payout (host only, called from World._check_round_end) ---
func compute_payout() -> Dictionary:
	if not world.is_server():
		return {}
	
	# Get reports from other modules
	var pax_report: Dictionary = {}
	var cargo_report: Dictionary = {}
	if world.npcs.has_method("passenger_report"):
		pax_report = world.npcs.passenger_report()
	if world.cargo.has_method("cargo_report"):
		cargo_report = world.cargo.cargo_report()
	
	var flight_info: Dictionary = {
		"landed": world.flight.phase == FlightModel.Phase.LANDED,
		"on_runway": world.flight.touchdown.get("at_destination", false),
		"diverted": world.flight.phase == FlightModel.Phase.LANDED and not world.flight.touchdown.get("at_destination", false),
		"crashed": world.flight.phase == FlightModel.Phase.CRASHED,
	}
	var damage: Dictionary = world.plane.damage.duplicate()
	
	return Scoring.payout(contracts, pax_report, cargo_report, flight_info, damage, tips, penalties, bank)

# --- Sync to clients ---
@rpc("authority", "call_remote", "reliable")
func _rpc_sync_phase(p: String) -> void:
	phase = p
	phase_changed.emit(phase)

@rpc("authority", "call_remote", "reliable")
func _rpc_sync_flight_no(n: int) -> void:
	flight_no = n
	flight_no_changed.emit(n)

@rpc("authority", "call_remote", "reliable")
func _rpc_sync_bank(b: int) -> void:
	bank = b
	bank_changed.emit(b)

@rpc("authority", "call_remote", "reliable")
func _rpc_sync_contracts(cs: Array) -> void:
	contracts = cs
	contracts_changed.emit()

# --- Late-join sync ---
func get_sync() -> Dictionary:
	return {
		"phase": phase,
		"flight_no": flight_no,
		"bank": bank,
		"contracts": contracts,
		"boarding_timer": boarding_timer,
		"tips": tips,
		"penalties": penalties,
	}

func apply_sync(d: Dictionary) -> void:
	phase = d.get("phase", "manifest")
	flight_no = d.get("flight_no", 1)
	bank = d.get("bank", 0)
	contracts = d.get("contracts", [])
	boarding_timer = d.get("boarding_timer", 0.0)
	tips = d.get("tips", [])
	penalties = d.get("penalties", [])
	phase_changed.emit(phase)
	contracts_changed.emit()
	bank_changed.emit(bank)
	flight_no_changed.emit(flight_no)

# --- Host actions ---
func _register_actions() -> void:
	world.register_action("manifest_toggle", _act_manifest_toggle)
	world.register_action("manifest_confirm", _act_manifest_confirm)

func _act_manifest_toggle(peer: int, args: Array) -> void:
	var cid := int(args[0])
	toggle_contract(cid)

func _act_manifest_confirm(peer: int, _args: Array) -> void:
	confirm_manifest(peer)

# Called from World._check_round_end after result is computed
func _on_round_end(result: Dictionary) -> void:
	# Save updated bank and flight_no
	_save_persisted()
	# Sync final values
	for p in world._ready_peers:
		if p != 1:
			_rpc_sync_bank.rpc_id(p, bank)
			_rpc_sync_flight_no.rpc_id(p, flight_no)