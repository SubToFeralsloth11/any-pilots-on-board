extends Node
## Co-op ping system. Host-authoritative. Players send `ping` action with hit point; host broadcasts to all peers.
## Each peer shows a marker at the plane-local point with the pinging player's colour and label.
## Markers fade over ~6 s, max 3 per player, rate limited to ~0.5 s.

const PingsModule := preload("res://scripts/ui/pings.gd")

const REACH := 60.0
const COOLDOWN := 0.5
const FADE_TIME := 6.0
const MAX_PER_PLAYER := 3

var world: World
var _last_ping: Dictionary = {}  ## peer_id -> time
var _markers: Array[Dictionary] = []  ## {peer_id, pos, color, label, start_time, node}

func setup(p_world: World) -> void:
	world = p_world
	world.register_action("ping", _on_ping_request)


func populate() -> void:
	# Nothing to populate for pings
	pass
func _on_ping_request(peer_id: int, args: Array) -> void:
	if not world.is_server():
		return
	var now = Time.get_ticks_msec() * 0.001
	var last = _last_ping.get(peer_id, -100.0)
	if now - last < COOLDOWN:
		return
	
	var origin: Vector3 = args[0]
	var dir: Vector3 = args[1]
	var hit_pos: Vector3
	var label: String = "Look!"
	
	# Raycast from origin
	var space = world.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(origin, origin + dir * REACH)
	query.collision_mask = Layers.WORLD | Layers.PROP | Layers.NPC | Layers.PLAYER
	query.exclude = [world.plane.get_rid()] if world.plane else []
	var result = space.intersect_ray(query)
	
	if result:
		hit_pos = result.position
		var c = result.collider
		if c:
			if c is Player:
				label = "%s: Look!" % c.display_name
			elif c.has_method("get_prompt"):
				label = c.get_prompt()
			elif c.is_in_group("grabbable"):
				label = "Item"
			elif c is Airliner:
				label = "Hull"
	else:
		hit_pos = origin + dir * REACH
	
	# Convert to plane-local for the marker
	var local_pos = world.plane.to_local(hit_pos) if world.plane else hit_pos
	var color = Player.COLORS[peer_id % Player.COLORS.size()]
	
	# Broadcast to all peers
	for p in world._ready_peers:
		_rpc_show_ping.rpc_id(p, peer_id, local_pos, color, label)
	_rpc_show_ping(peer_id, local_pos, color, label)
	
	_last_ping[peer_id] = now


@rpc("authority", "call_remote", "reliable")
func _rpc_show_ping(peer_id: int, local_pos: Vector3, color: Color, label: String) -> void:
	# Enforce max per player
	var count = 0
	for m in _markers:
		if m.peer_id == peer_id:
			count += 1
	if count >= MAX_PER_PLAYER:
		# Remove oldest
		for i in range(_markers.size()):
			if _markers[i].peer_id == peer_id:
				if _markers[i].node:
					_markers[i].node.queue_free()
				_markers.remove_at(i)
				break
	
	var marker = _create_marker(local_pos, color, label, peer_id)
	world.plane.add_child(marker) if world.plane else world.add_child(marker)
	_markers.append({
		"peer_id": peer_id,
		"pos": local_pos,
		"color": color,
		"label": label,
		"start_time": Time.get_ticks_msec() * 0.001,
		"node": marker
	})
	
	# Play blip sound
	_play_blip(local_pos)


func _create_marker(local_pos: Vector3, color: Color, label: String, peer_id: int) -> Node3D:
	var root = Node3D.new()
	root.global_position = world.plane.to_global(local_pos) if world.plane else local_pos
	
	# Pulse ring (billboarded) - using cylinder as ring
	var ring = MeshInstance3D.new()
	var ring_mesh = CylinderMesh.new()
	ring_mesh.top_radius = 0.35
	ring_mesh.bottom_radius = 0.35
	ring_mesh.height = 0.02
	ring_mesh.inner_radius = 0.15
	ring_mesh.radial_segments = 32
	ring.mesh = ring_mesh
	var ring_mat = StandardMaterial3D.new()
	ring_mat.albedo_color = color
	ring_mat.emission_enabled = true
	ring_mat.emission = color
	ring_mat.emission_energy_multiplier = 2.0
	ring_mat.render_mode = 1  # RENDER_MODE_UNSHADED
	ring_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ring.material_override = ring_mat
	root.add_child(ring)
	
	# Central dot
	var dot = MeshInstance3D.new()
	dot.mesh = SphereMesh.new()
	dot.mesh.radius = 0.08
	dot.mesh.radial_segments = 12
	dot.mesh.rings = 6
	var dot_mat = StandardMaterial3D.new()
	dot_mat.albedo_color = color
	dot_mat.emission_enabled = true
	dot_mat.emission = color
	dot_mat.emission_energy_multiplier = 3.0
	dot_mat.render_mode = 1  # RENDER_MODE_UNSHADED
	dot_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dot.material_override = dot_mat
	root.add_child(dot)
	
	# Label (no depth test so visible through walls)
	var lbl = Label3D.new()
	lbl.text = "%s: %s" % [world.names.get(peer_id, "Player %d" % peer_id), label]
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position.y = 0.6
	lbl.font_size = 42
	lbl.outline_size = 8
	lbl.pixel_size = 0.005
	# Use default theme font
	root.add_child(lbl)
	
	# Animation script
	var anim = _PingAnim.new()
	anim.root = root
	anim.color = color
	anim.label = lbl
	anim.ring = ring
	anim.dot = dot
	anim.start = Time.get_ticks_msec() * 0.001
	root.add_child(anim)
	anim.set_process(true)
	
	return root


func _play_blip(pos: Vector3) -> void:
	# Procedural short blip
	var sample_rate = 48000
	var duration = 0.08
	var samples = int(sample_rate * duration)
	var data = PackedFloat32Array()
	data.resize(samples * 2)  # stereo
	var freq = 1200.0
	for i in range(samples):
		var t = i / sample_rate
		var env = exp(-t * 40.0)
		var val = sin(t * freq * TAU) * env * 0.3
		data[i * 2] = val
		data[i * 2 + 1] = val
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = data
	var player = AudioStreamPlayer3D.new()
	player.stream = wav
	player.global_position = pos
	player.volume_db = -6.0
	player.max_distance = 30.0
	player.attenuation_filter_cutoff_hz = 5000.0
	world.add_child(player)
	player.play()
	player.finished.connect(player.queue_free.bind())


func _process(dt: float) -> void:
	var now = Time.get_ticks_msec() * 0.001
	var i = _markers.size() - 1
	while i >= 0:
		var m = _markers[i]
		var age = now - m.start_time
		if age > FADE_TIME or not m.node or not m.node.is_inside_tree():
			if m.node and m.node.is_inside_tree():
				m.node.queue_free()
			_markers.remove_at(i)
		i -= 1


class _PingAnim extends Node:
	var root: Node3D
	var color: Color
	var label: Label3D
	var ring: MeshInstance3D
	var dot: MeshInstance3D
	var start: float
	
	func _process(dt: float) -> void:
		var age = Time.get_ticks_msec() * 0.001 - start
		if age > FADE_TIME:
			root.queue_free()
			return
		var alpha = 1.0 - pow(age / FADE_TIME, 1.5)
		var pulse = 1.0 + sin(age * 8.0) * 0.15 * alpha
		
		# Ring expands and fades (CylinderMesh)
		if ring and ring.mesh:
			var rm: CylinderMesh = ring.mesh
			rm.inner_radius = lerpf(0.15, 0.6, age / FADE_TIME)
			rm.top_radius = lerpf(0.35, 1.0, age / FADE_TIME)
			rm.bottom_radius = lerpf(0.35, 1.0, age / FADE_TIME)
			var mat: StandardMaterial3D = ring.material_override
			if mat:
				mat.albedo_color = Color(color.r, color.g, color.b, alpha)
				mat.emission_energy_multiplier = 2.0 * alpha
		
		# Dot pulses
		if dot and dot.mesh:
			var sm: SphereMesh = dot.mesh
			sm.radius = 0.08 * pulse
			var mat: StandardMaterial3D = dot.material_override
			if mat:
				mat.albedo_color = Color(color.r, color.g, color.b, alpha)
				mat.emission_energy_multiplier = 3.0 * alpha
		
		# Label fade
		if label:
			label.self_modulate = Color(1, 1, 1, alpha)