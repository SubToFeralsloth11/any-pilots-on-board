extends FunToy
## Simple loose toys: "basketball", "golf_ball" and "checker" (extra {"side": 0 red / 1 black}).

const CHECKER_COLORS := [Color(0.85, 0.12, 0.14), Color(0.12, 0.12, 0.14)]
const CHECKER_R := 0.032
const CHECKER_H := 0.018


func _configure(extra: Dictionary) -> void:
	match kind:
		"basketball":
			display = "basketball"
			hint = "Throw it [LMB] through the hoop on the cargo-side bulkhead."
			mass = 0.6
			physics_material_override = FunLooks.phys(0.6, 0.75)
			var s := SphereShape3D.new()
			s.radius = 0.12
			add_shape(s)
			part(FunLooks.sphere(0.12, 20), FunLooks.mat(Color(0.95, 0.45, 0.12), 0.8), Vector3.ZERO)
			var seam := FunLooks.mat(FunLooks.INK)
			part(FunLooks.torus(0.118, 0.124), seam, Vector3.ZERO)
			part(FunLooks.torus(0.118, 0.124), seam, Vector3.ZERO, Vector3(PI / 2, 0, 0))
			part(FunLooks.torus(0.118, 0.124), seam, Vector3.ZERO, Vector3(0, 0, PI / 2))
		"golf_ball":
			display = "golf ball"
			hint = "Drop it [E] and whack it with the golf club. FORE!"
			mass = 0.05
			continuous_cd = true
			physics_material_override = FunLooks.phys(0.4, 0.65)
			var s := SphereShape3D.new()
			s.radius = 0.035
			add_shape(s)
			part(FunLooks.sphere(0.035, 14), FunLooks.mat(Color(0.98, 0.98, 0.96), 0.4), Vector3.ZERO)
			for i in 6:
				var d := Vector3.UP.rotated(Vector3.RIGHT, i * 1.1).rotated(Vector3.UP, i * 2.3) * 0.033
				part(FunLooks.sphere(0.006, 6), FunLooks.mat(Color(0.82, 0.82, 0.8)), d)
		"checker":
			var side := int(extra.get("side", 0))
			display = "red checker" if side == 0 else "black checker"
			hint = "Set it down on a square [E]. King me!"
			mass = 0.05
			physics_material_override = FunLooks.phys(0.5, 0.05)
			var s := CylinderShape3D.new()
			s.radius = CHECKER_R
			s.height = CHECKER_H
			add_shape(s)
			var c: Color = CHECKER_COLORS[side]
			part(FunLooks.cyl(CHECKER_R, CHECKER_R, CHECKER_H, 16), FunLooks.mat(c, 0.35), Vector3.ZERO)
			part(FunLooks.torus(CHECKER_R * 0.55, CHECKER_R * 0.75), FunLooks.mat(c.lightened(0.25), 0.35),
				Vector3(0, CHECKER_H / 2, 0), Vector3.ZERO, Vector3(1, 0.4, 1))
