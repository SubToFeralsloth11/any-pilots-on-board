extends RefCounted
## Deterministic storm cells along the route (pure math, unit tested).
## A cell is a Dictionary {pos: Vector3 (ground centre, y = 0), radius: float, strength: float 0..1,
## top: float (cloud top altitude)}. Storms reach from the ground up to `top`, so altitude only
## matters if you climb over them.

const COUNT_MIN := 3
const COUNT_MAX := 5
const ROUTE_FROM := 0.2           ## Cells sit between these fractions of the route.
const ROUTE_TO := 0.85
const RADIUS_MIN := 900.0
const RADIUS_MAX := 1700.0
const STRENGTH_MIN := 0.45
const STRENGTH_MAX := 1.0
const LATERAL := Vector2(0.8, 2.2)   ## Off-track cells sit this many radii beside the route.
const CORE := 0.25                ## Fraction of the radius at full strength.
const TOP_MIN := 2400.0
const TOP_MAX := 3200.0
const TOP_FADE := 400.0           ## Intensity fades out over this band around the cloud top.


## Same seed and endpoints -> same cells on every peer. At least one cell sits on the route.
static func generate(seed_value: int, origin: Vector3, dest: Vector3) -> Array[Dictionary]:
	var cells: Array[Dictionary] = []
	var a := Vector2(origin.x, origin.z)
	var b := Vector2(dest.x, dest.z)
	var length := a.distance_to(b)
	if length < 1.0:
		return cells
	var dir := (b - a) / length
	var side := Vector2(-dir.y, dir.x)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := rng.randi_range(COUNT_MIN, COUNT_MAX)
	var on_track := rng.randi_range(0, n - 1)
	for i in n:
		var t := lerpf(ROUTE_FROM, ROUTE_TO, (i + 0.5) / n) + rng.randf_range(-0.04, 0.04)
		var radius := rng.randf_range(RADIUS_MIN, RADIUS_MAX)
		var lateral := rng.randf_range(-0.25, 0.25) * radius if i == on_track \
			else rng.randf_range(LATERAL.x, LATERAL.y) * radius * (1.0 if rng.randf() < 0.5 else -1.0)
		var p := a + dir * length * t + side * lateral
		cells.append({"pos": Vector3(p.x, 0.0, p.y), "radius": radius,
			"strength": rng.randf_range(STRENGTH_MIN, STRENGTH_MAX), "top": rng.randf_range(TOP_MIN, TOP_MAX)})
	return cells


## Intensity 0..1 of one cell at a world position: full in the core, smooth falloff to 0 at the rim.
static func cell_intensity(c: Dictionary, p: Vector3) -> float:
	var cp: Vector3 = c.pos
	var d := Vector2(p.x - cp.x, p.z - cp.z).length() / float(c.radius)
	if d >= 1.0:
		return 0.0
	var top: float = c.top
	var vertical := 1.0 - smoothstep(top - TOP_FADE, top + TOP_FADE * 0.5, p.y)
	return float(c.strength) * (1.0 - smoothstep(CORE, 1.0, d)) * vertical


## Strongest cell intensity at a world position (0 in calm air).
static func intensity(cells: Array[Dictionary], p: Vector3) -> float:
	var best := 0.0
	for c in cells:
		best = maxf(best, cell_intensity(c, p))
	return best


## Index of the strongest cell at `p`, or -1 in calm air.
static func strongest(cells: Array[Dictionary], p: Vector3) -> int:
	var best := 0.0
	var idx := -1
	for i in cells.size():
		var v := cell_intensity(cells[i], p)
		if v > best:
			best = v
			idx = i
	return idx


## Index of the cell the plane will fly into within `horizon` seconds on its current
## velocity (intensity above `threshold`), or -1. Sampled once per second.
static func cell_ahead(cells: Array[Dictionary], p: Vector3, velocity: Vector3, horizon: float,
		threshold: float) -> int:
	for s in range(1, int(horizon) + 1):
		var q := p + velocity * float(s)
		var i := strongest(cells, q)
		if i >= 0 and cell_intensity(cells[i], q) >= threshold:
			return i
	return -1
