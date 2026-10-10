extends Node
## Connection layer: ENet host/join over direct IP. Round state lives in World.

signal joined                ## Client connected to a host.
signal join_failed
signal host_lost             ## Client lost the host.

const PORT := 7777
const MAX_CLIENTS := 7

var local_name := "Passenger"


func host(port := PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func join(ip: String, port := PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func is_online() -> bool:
	return not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


func _ready() -> void:
	multiplayer.connected_to_server.connect(func() -> void: joined.emit())
	multiplayer.connection_failed.connect(func() -> void:
		leave()
		join_failed.emit())
	multiplayer.server_disconnected.connect(func() -> void:
		leave()
		host_lost.emit())


## LAN addresses friends can type into "Join".
func lan_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172.") or a.begins_with("100."):
			out.append(a)
	return out
