extends Node3D
## Scenery in world coordinates (ground y = 0). World moves this node past the plane.


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = ProceduralSkyMaterial.new()
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.4, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60000, 60000)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.55, 0.25)
	pm.material = m
	ground.mesh = pm
	add_child(ground)
