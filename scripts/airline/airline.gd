class_name Airline
extends Node
## Airline module: owns the round phase state machine (manifest -> boarding -> flight -> report),
## the contract offers, the bank and the flight number.
## Host is authoritative; clients receive state via RPC (and get_sync/apply_sync on join).
## The host persists bank and the NEXT flight number in CFG_PATH once per completed round.

signal phase_changed(phase: String)
signal contracts_changed()
signal bank_changed(new_bank: int)
signal flight_no_changed(new_no: int)

const PHASES := ["manifest", "boarding", "flight", "report"]
const BOARDING_TIMEOUT := 45.0  ## Seconds of boarding before the ramp closes on its own.
const SEAT_CAPACITY := 32
const CARGO_CAPACITY := 10
const CFG_PATH := "user://airline.cfg"
const Contracts := preload("res://scripts/airline/contracts.gd")

var world: World
var phase: String = "manifest"
var flight_no: int = 1
var bank: int = 0
var contracts: Array[Dictionary] = []
var boarding_timer: float = 0.0        ## Seconds left in boarding (all peers; clients count down locally).
var boarding_timeout := BOARDING_TIMEOUT  ## Host: boarding length for this round (dev harnesses may shorten it).
var tips: Array[Dictionary] = []       ## {peer: int, amount: int, reason: String}
var penalties: Array[Dictionary] = []  ## {amount: int, reason: String}


func setup(w: World) -> void:
	world = w
	world.register_action("manifest_toggle", func(peer: int, args: Array) -> void: toggle_contract(peer, int(args[0])))
	world.register_action("manifest_confirm", func(peer: int, _a: Array) -> void: confirm_manifest(peer))
	if w.is_server():
		_load_persisted()
		contracts = Contracts.generate(flight_no)


func populate() -> void:
	pass   # Passengers and cargo spawn on the boarding phase (their modules listen to phase_changed).


# --- Persistence (host) ----------------------------------------------------------------------

func _load_persisted() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) == OK:
		bank = int(cf.get_value("airline", "bank", 0))
		flight_no = maxi(1, int(cf.get_value("airline", "flight_no", 1)))


## Stores the balance and the number of the flight that comes next.
func _save_persisted(next_flight_no: int) -> void:
	var cf := ConfigFile.new()
	cf.set_value("airline", "bank", bank)
	cf.set_value("airline", "flight_no", next_flight_no)
	cf.save(CFG_PATH)


## Accepted contracts, optionally only one type ("passengers" / "cargo"). All peers.
func accepted(type: String = "") -> Array[Dictionary]:
	return contracts.filter(func(c: Dictionary) -> bool: return c.accepted and (type == "" or c.type == type))


## Seats (passengers) or hold slots (cargo) used by the accepted contracts of a type.
func load_of(type: String) -> int:
	var n := 0
	for c in accepted(type):
		n += int(c.count)
	return n


# --- Phase state machine (host) ----------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if phase != "boarding":
		return
	boarding_timer = maxf(0.0, boarding_timer - dt)
	if boarding_timer <= 0.0 and world.is_server():
		end_boarding()


## Host. Any player toggles a contract while the manifest is open (capacity permitting).
func toggle_contract(peer: int, contract_id: int) -> void:
	if phase != "manifest":
		return
	for c in contracts:
		if c.id != contract_id:
			continue
		if not c.accepted:
			var cap := SEAT_CAPACITY if c.type == "passengers" else CARGO_CAPACITY
			if load_of(c.type) + int(c.count) > cap:
				world.notify(peer, "Not enough %s for that one." % ("seats" if c.type == "passengers" else "room in the hold"))
				return
		c.accepted = not c.accepted
		break
	for p in world._ready_peers:
		_rpc_sync_contracts.rpc_id(p, contracts)
	contracts_changed.emit()


## Host. Start boarding (needs at least one passenger contract).
func confirm_manifest(peer: int) -> void:
	if phase != "manifest":
		return
	if accepted("passengers").is_empty():
		world.notify(peer, "Accept at least one passenger contract first.")
		return
	boarding_timer = boarding_timeout
	_set_phase("boarding")
	world.set_plane("ramp", true)


## Host. Closes the ramp and starts the flight phase. The Passengers module calls this once every
## passenger is seated; otherwise the boarding timer does when it runs out.
func end_boarding() -> void:
	if not world.is_server() or phase != "boarding":
		return
	boarding_timer = 0.0
	world.set_plane("ramp", false)
	_set_phase("flight")


## Host, from World._check_round_end. Computes the payout, banks it, persists the bank and the
## next flight number once, and moves every peer to the report phase. Returns the payout.
func finish_round() -> Dictionary:
	var payout := compute_payout()
	bank = int(payout.new_bank)
	_save_persisted(flight_no + 1)
	for p in world._ready_peers:
		_rpc_sync_bank.rpc_id(p, bank)
	bank_changed.emit(bank)
	_set_phase("report")
	return payout


func _set_phase(p: String) -> void:
	phase = p
	for peer in world._ready_peers:
		_rpc_sync_phase.rpc_id(peer, p, boarding_timer)
	phase_changed.emit(phase)


# --- Tips / penalties (host) -------------------------------------------------------------------

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


## Host. Payout for the round so far, from the passenger/cargo reports and the flight outcome.
func compute_payout() -> Dictionary:
	var pax_report: Dictionary = world.npcs.passenger_report() if world.npcs.has_method("passenger_report") else {}
	var cargo_report: Dictionary = world.cargo.cargo_report() if world.cargo.has_method("cargo_report") else {}
	var f := world.flight
	var landed := f.phase == FlightModel.Phase.LANDED
	var at_dest: bool = f.touchdown.get("at_destination", false)
	var flight_info := {"landed": landed, "on_runway": at_dest, "diverted": landed and not at_dest,
		"crashed": f.phase == FlightModel.Phase.CRASHED}
	return Scoring.payout(contracts, pax_report, cargo_report, flight_info, world.plane.damage, tips, penalties, bank)


# --- Sync to clients -------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _rpc_sync_phase(p: String, timer: float) -> void:
	phase = p
	boarding_timer = timer
	phase_changed.emit(phase)


@rpc("authority", "call_remote", "reliable")
func _rpc_sync_bank(b: int) -> void:
	bank = b
	bank_changed.emit(b)


@rpc("authority", "call_remote", "reliable")
func _rpc_sync_contracts(cs: Array) -> void:
	contracts.assign(cs)
	contracts_changed.emit()


func get_sync() -> Dictionary:
	return {"phase": phase, "flight_no": flight_no, "bank": bank, "contracts": contracts,
		"boarding_timer": boarding_timer, "tips": tips, "penalties": penalties}


func apply_sync(d: Dictionary) -> void:
	phase = d.get("phase", "manifest")
	flight_no = d.get("flight_no", 1)
	bank = d.get("bank", 0)
	contracts.assign(d.get("contracts", []))
	boarding_timer = d.get("boarding_timer", 0.0)
	tips.assign(d.get("tips", []))
	penalties.assign(d.get("penalties", []))
	phase_changed.emit(phase)
	contracts_changed.emit()
	bank_changed.emit(bank)
	flight_no_changed.emit(flight_no)
