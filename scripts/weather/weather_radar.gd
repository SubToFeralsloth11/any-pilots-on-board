extends Control
## Pilot weather radar (heading-up, drawn in _draw): range rings, a sweeping beam, the
## destination bearing and every storm cell, coloured by threat to the current heading:
## red = on the flight path, yellow = close to it, green = clear of it. A flashing
## "TURBULENCE AHEAD" banner shows ~20 s before entering a cell. Visible only while the
## local player is piloting.

const RANGE := 9000.0             ## Metres at the outer ring.
const RINGS := 3
const M_TO_NM := 1.0 / 1852.0
const BG := Color(0.04, 0.06, 0.12)
const SCOPE := Color(0.01, 0.04, 0.03)
const BEZEL := Color(0.22, 0.25, 0.32)
const RING := Color(0.2, 0.55, 0.35, 0.6)
const DIM := Color(0.62, 0.72, 0.88)
const GREEN := Color(0.3, 0.95, 0.45)
const YELLOW := Color(1, 0.8, 0.15)
const RED := Color(1, 0.28, 0.22)
const NEAR_PATH := 1500.0         ## Extra lateral margin (m) that still counts as "close to the path".

var weather: Node
var _t := 0.0


func _ready() -> void:
	clip_contents = true
	visible = false


func _process(dt: float) -> void:
	_t += dt
	var w: World = weather.world
	visible = w.local_player != null and w.local_player.piloting and not w.round_over
	if visible:
		queue_redraw()


## Threat colour of a cell relative to the heading (fwd/right are unit ground vectors).
static func threat_color(rel: Vector2, radius: float) -> Color:
	var along := -rel.y
	var lateral := absf(rel.x)
	if along > -radius and lateral < radius:
		return RED
	if along > -radius and lateral < radius + NEAR_PATH:
		return YELLOW
	return GREEN


func _draw() -> void:
	var w: World = weather.world
	var f := w.flight
	var font := ThemeDB.fallback_font
	var s := StyleBoxFlat.new()
	s.bg_color = BG
	s.set_corner_radius_all(14)
	draw_style_box(s, Rect2(Vector2.ZERO, size))
	var c := Vector2(size.x * 0.5, 30 + (size.y - 58) * 0.5)
	var r := minf(size.x - 20, size.y - 58) * 0.5
	var k := r / RANGE
	draw_circle(c, r, SCOPE)
	# Heading-up frame: forward is screen up, right wing is screen right.
	var fwd := Vector2(-sin(f.yaw), -cos(f.yaw))   # (x, z) of the nose direction.
	var right := Vector2(cos(f.yaw), -sin(f.yaw))
	var here := Vector2(f.pos.x, f.pos.z)
	for cell in weather.cells:
		var d: Vector2 = Vector2((cell.pos as Vector3).x, (cell.pos as Vector3).z) - here
		var rel := Vector2(d.dot(right), -d.dot(fwd))
		var rad: float = cell.radius
		if rel.length() - rad > RANGE:
			continue
		var col := threat_color(rel, rad)
		var p := c + rel * k
		var strength: float = cell.strength
		draw_circle(p, rad * k, Color(col, 0.35))
		draw_circle(p, rad * k * lerpf(0.35, 0.6, strength), Color(col, 0.75))
		draw_circle(p, rad * k, col, false, 1.5)
	# Mask anything that spills over the scope edge.
	draw_arc(c, r + 20, 0, TAU, 64, BG, 40)
	s.draw_center = false
	s.border_color = BEZEL
	s.set_border_width_all(3)
	draw_style_box(s, Rect2(Vector2.ZERO, size))
	draw_string(font, Vector2(12, 20), "WX RADAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
	draw_string(font, Vector2(0, 20), "%d NM " % roundi(RANGE * M_TO_NM), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 10, 12, DIM)
	for i in range(1, RINGS + 1):
		draw_arc(c, r * i / RINGS, 0, TAU, 48, RING, 1.0)
	draw_line(c, c + Vector2(0, -r), Color(RING, 0.35), 1.0)
	# Sweep beam.
	var a := fmod(_t * 2.2, TAU)
	var sweep := Vector2(sin(a), -cos(a)) * r
	draw_line(c, c + sweep, Color(GREEN, 0.7), 2.0)
	for i in 6:
		var b := a - 0.06 * (i + 1)
		draw_line(c, c + Vector2(sin(b), -cos(b)) * r, Color(GREEN, 0.2 - i * 0.03), 2.0)
	# Destination bearing tick on the outer ring.
	var to_dest := Vector2(FlightModel.runway_threshold().x, FlightModel.runway_threshold().z) - here
	var dv := Vector2(to_dest.dot(right), -to_dest.dot(fwd)).normalized()
	draw_line(c + dv * (r - 8), c + dv * (r + 2), Color(0.4, 0.8, 1.0), 3.0)
	draw_string(font, c + dv * (r - 22) + Vector2(-14, 4), "DEST", HORIZONTAL_ALIGNMENT_CENTER, 28, 10, Color(0.4, 0.8, 1.0))
	# Our plane.
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(-6, 6), c + Vector2(6, 6)]), Color.WHITE)
	_banner(font)


func _banner(font: Font) -> void:
	var cur: float = weather.current
	var text := ""
	var col := YELLOW
	if cur > 0.2:
		text = "IN STORM %d%%" % roundi(cur * 100)
		col = RED
	elif int(weather.ahead) >= 0:
		text = "TURBULENCE AHEAD"
	if text == "":
		draw_string(font, Vector2(0, size.y - 12), "CLEAR", HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, GREEN)
		return
	var on := fmod(_t, 0.7) < 0.45
	var rect := Rect2(10, size.y - 28, size.x - 20, 20)
	draw_rect(rect, Color(col, 0.25 if on else 0.1))
	draw_rect(rect, col, false, 1.5)
	draw_string(font, Vector2(0, size.y - 13), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, col if on else col.darkened(0.3))
