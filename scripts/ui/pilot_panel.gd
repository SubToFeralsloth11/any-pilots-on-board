extends Control
## The pilot's instrument cluster, drawn in _draw (one cheap node):
## airspeed tape | artificial horizon with heading strip | altimeter tape + vertical speed |
## engine/flaps/gear/throttle block | plane damage | runway navigation, plus stall and fire warnings.

const MS_TO_KT := 1.94384
const M_TO_FT := 3.28084
const GLIDE_SLOPE := 0.0524   ## tan(3 degrees)
const BG := Color(0.04, 0.06, 0.12, 0.88)
const BEZEL := Color(0.22, 0.25, 0.32)
const SKY := Color(0.25, 0.55, 0.98)
const EARTH := Color(0.6, 0.38, 0.18)
const DIM := Color(0.62, 0.72, 0.88)
const GOOD := Color(0.3, 0.95, 0.45)
const WARN := Color(1, 0.75, 0.15)
const BAD := Color(1, 0.3, 0.25)
const PARTS := [["engine0", "ENG L"], ["engine1", "ENG R"], ["wing0", "WING L"], ["wing1", "WING R"],
	["tail", "TAIL"], ["hull", "HULL"]]
const HINT := "W nose down · S nose up · A/D bank · Shift/Ctrl throttle · F flaps · G gear · E leave seat"

var world: World
var _t := 0.0


func _process(dt: float) -> void:
	_t += dt
	if visible:
		queue_redraw()


## Health 0..1 of a plane part (see Airliner.DAMAGE_PARTS); missing entries count as intact.
static func part_health(w: World, part: String) -> float:
	return float(w.plane.damage.get(part, 1.0))


static func health_color(h: float, t: float) -> Color:
	if h < 0.3:
		return BAD if fmod(t, 0.6) < 0.35 else Color(1, 0.6, 0.2)
	return BAD.lerp(WARN, h / 0.6) if h < 0.6 else WARN.lerp(GOOD, (h - 0.6) / 0.4)


func _draw() -> void:
	if world == null:
		return
	var f := world.flight
	var font := ThemeDB.fallback_font
	var s := StyleBoxFlat.new()
	s.bg_color = BG
	s.set_corner_radius_all(16)
	s.border_color = BEZEL
	s.set_border_width_all(4)
	draw_style_box(s, Rect2(Vector2.ZERO, size))
	var top := 14.0
	var h := size.y - 44.0
	_speed_tape(font, Rect2(14, top, 74, h), f)
	_horizon(font, Rect2(96, top, 200, h), f)
	_alt_tape(font, Rect2(304, top, 84, h), f)
	_vsi(font, Rect2(392, top, 26, h), f)
	_systems(font, Rect2(430, top, 170, h), f)
	_damage(font, Rect2(610, top, 170, h))
	_navigation(font, Rect2(790, top, size.x - 804, h), f)
	_warnings(font, f)
	draw_string(font, Vector2(0, size.y - 10), HINT, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, DIM)


func _instrument_bg(r: Rect2) -> void:
	draw_rect(r, Color(0.02, 0.03, 0.06))
	draw_rect(r, BEZEL, false, 2.0)


## Scrolling tape: `value` in the window centre, a tick every `step` labelled every `label_every`.
func _tape(font: Font, r: Rect2, value: float, px_per_unit: float, step: float, label_every: int,
		fmt: String, bands: Array) -> void:
	_instrument_bg(r)
	var mid := r.position.y + r.size.y * 0.5
	for b in bands:
		var y0 := clampf(mid - (float(b[1]) - value) * px_per_unit, r.position.y, r.end.y)
		var y1 := clampf(mid - (float(b[0]) - value) * px_per_unit, r.position.y, r.end.y)
		if y1 > y0:
			draw_rect(Rect2(r.end.x - 6, y0, 5, y1 - y0), b[2])
	var first := floorf((value - r.size.y * 0.5 / px_per_unit) / step) * step
	var v := first
	while v <= value + r.size.y * 0.5 / px_per_unit:
		var y := mid - (v - value) * px_per_unit
		if y > r.position.y + 4 and y < r.end.y - 4 and v >= 0.0:
			var major := int(roundf(v / step)) % label_every == 0
			draw_line(Vector2(r.end.x - (14 if major else 8), y), Vector2(r.end.x - 6, y), DIM, 1.5)
			if major:
				draw_string(font, Vector2(r.position.x + 4, y + 5), fmt % v, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
		v += step
	# Readout box.
	var box := Rect2(r.position.x - 2, mid - 15, r.size.x + 4, 30)
	draw_rect(box, Color.BLACK)
	draw_rect(box, Color.WHITE, false, 2.0)
	draw_string(font, Vector2(box.position.x, mid + 8), fmt % roundf(value), HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 20, Color.WHITE)


func _speed_tape(font: Font, r: Rect2, f: FlightModel) -> void:
	var kt := f.speed * MS_TO_KT
	var stall := f.stall_speed() * MS_TO_KT
	_tape(font, r, kt, 2.4, 5.0, 2, "%d", [[0.0, stall, BAD], [stall, stall + 10.0, WARN], [stall + 10.0, 400.0, GOOD]])
	draw_string(font, r.position + Vector2(0, -2), "KT", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, DIM)


func _alt_tape(font: Font, r: Rect2, f: FlightModel) -> void:
	var ft := f.altitude() * M_TO_FT
	_tape(font, r, ft, 0.12, 100.0, 5, "%d", [[0.0, 500.0, Color(1, 0.5, 0.2, 0.8)]])
	draw_string(font, r.position + Vector2(0, -2), "FT AGL", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, DIM)


func _vsi(font: Font, r: Rect2, f: FlightModel) -> void:
	_instrument_bg(r)
	var fpm := f.velocity.y * M_TO_FT * 60.0
	var mid := r.position.y + r.size.y * 0.5
	var k := clampf(fpm / 2000.0, -1.0, 1.0)
	var col := BAD if f.velocity.y < -FlightModel.MAX_SINK else (GOOD if fpm > 0.0 else WARN)
	var y := mid - k * (r.size.y * 0.5 - 4)
	draw_rect(Rect2(r.position.x + 5, minf(y, mid), r.size.x - 10, absf(y - mid)), col)
	draw_line(Vector2(r.position.x, mid), Vector2(r.end.x, mid), Color.WHITE, 1.5)
	var label_y := r.end.y - 6 if fpm > 0.0 else r.position.y + 16
	draw_string(font, Vector2(r.position.x - 4, label_y), "%+.1f" % (fpm / 1000.0), HORIZONTAL_ALIGNMENT_CENTER,
		r.size.x + 8, 11, Color.WHITE)
	draw_string(font, r.position + Vector2(-6, -2), "V/S", HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 12, 12, DIM)


## Artificial horizon with pitch ladder, bank arc, aircraft symbol and a heading strip.
func _horizon(font: Font, r: Rect2, f: FlightModel) -> void:
	var c := r.get_center() - Vector2(0, 12)
	var rad := minf(r.size.x, r.size.y - 30) * 0.5
	var circle := PackedVector2Array()
	for i in 48:
		circle.append(c + Vector2.from_angle(TAU * i / 48.0) * rad)
	draw_colored_polygon(circle, SKY)
	var along := Vector2.RIGHT.rotated(-f.roll)
	var down := Vector2.DOWN.rotated(-f.roll)
	var px_per_rad := rad / 0.4
	var o := c + down * f.pitch * px_per_rad
	var ground := PackedVector2Array([o - along * rad * 3, o + along * rad * 3,
		o + along * rad * 3 + down * rad * 4, o - along * rad * 3 + down * rad * 4])
	for poly in Geometry2D.intersect_polygons(ground, circle):
		draw_colored_polygon(poly, EARTH)
	draw_line(o - along * rad, o + along * rad, Color.WHITE, 2.0)
	for deg: float in [-20.0, -10.0, 10.0, 20.0]:
		var p := c + down * (f.pitch - deg_to_rad(deg)) * px_per_rad
		if p.distance_to(c) < rad - 14:
			var half := 26.0 if absf(deg) > 15.0 else 16.0
			draw_line(p - along * half, p + along * half, Color(1, 1, 1, 0.85), 2.0)
			draw_string(font, p + along * (half + 3) + Vector2(0, 5), "%d" % absf(deg), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	# Bank scale and pointer.
	for deg: float in [-45.0, -30.0, -20.0, -10.0, 0.0, 10.0, 20.0, 30.0, 45.0]:
		var a := deg_to_rad(deg) - PI / 2
		var len := 10.0 if int(deg) % 30 == 0 else 6.0
		draw_line(c + Vector2.from_angle(a) * (rad - 1), c + Vector2.from_angle(a) * (rad - 1 - len), Color.WHITE, 2.0)
	var pa := -PI / 2 - f.roll
	var tip := c + Vector2.from_angle(pa) * (rad - 12)
	var side := Vector2.from_angle(pa + PI / 2) * 6
	draw_colored_polygon(PackedVector2Array([tip, tip - Vector2.from_angle(pa) * 10 + side,
		tip - Vector2.from_angle(pa) * 10 - side]), WARN)
	draw_arc(c, rad, 0, TAU, 48, BEZEL, 4.0)
	var y := WARN
	draw_line(c + Vector2(-46, 0), c + Vector2(-16, 0), Color.BLACK, 8.0)
	draw_line(c + Vector2(16, 0), c + Vector2(46, 0), Color.BLACK, 8.0)
	draw_line(c + Vector2(-46, 0), c + Vector2(-16, 0), y, 5.0)
	draw_line(c + Vector2(16, 0), c + Vector2(46, 0), y, 5.0)
	draw_polyline(PackedVector2Array([c + Vector2(-16, 0), c + Vector2(0, 11), c + Vector2(16, 0)]), y, 5.0)
	draw_circle(c, 3, y)
	# Heading strip.
	var hs := Rect2(r.position.x, r.end.y - 22, r.size.x, 22)
	_instrument_bg(hs)
	var heading := fposmod(-rad_to_deg(f.yaw), 360.0)
	var px_per_deg := 2.4
	var d0 := int(floorf((heading - 45.0) / 5.0)) * 5
	for d in range(d0, d0 + 100, 5):
		var x := hs.get_center().x + (d - heading) * px_per_deg
		if x < hs.position.x + 6 or x > hs.end.x - 6:
			continue
		var major := d % 30 == 0
		draw_line(Vector2(x, hs.position.y), Vector2(x, hs.position.y + (8 if major else 4)), DIM, 1.5)
		if major:
			var n := posmod(d, 360)
			var lbl: String = {0: "N", 90: "E", 180: "S", 270: "W"}.get(n, "%d" % (n / 10))
			draw_string(font, Vector2(x - 12, hs.end.y - 2), lbl, HORIZONTAL_ALIGNMENT_CENTER, 24, 12, Color.WHITE)
	# Runway bug on the heading strip.
	var to := FlightModel.runway_threshold() - f.pos
	var bug := fposmod(-rad_to_deg(atan2(-to.x, -to.z)), 360.0)
	var bx := hs.get_center().x + wrapf(bug - heading, -180.0, 180.0) * px_per_deg
	bx = clampf(bx, hs.position.x + 4, hs.end.x - 4)
	draw_rect(Rect2(bx - 4, hs.position.y, 8, 6), Color(1, 0.3, 1))
	draw_line(Vector2(hs.get_center().x, hs.position.y - 4), Vector2(hs.get_center().x, hs.end.y), WARN, 2.0)


func _systems(font: Font, r: Rect2, f: FlightModel) -> void:
	# Throttle lever.
	var tr := Rect2(r.position.x + 4, r.position.y + 16, 24, r.size.y - 34)
	draw_string(font, Vector2(tr.position.x - 6, r.position.y + 10), "THR", HORIZONTAL_ALIGNMENT_CENTER, 36, 12, DIM)
	_instrument_bg(tr)
	var th := tr.size.y * f.throttle
	draw_rect(Rect2(tr.position.x + 3, tr.end.y - th, tr.size.x - 6, th), GOOD.lerp(WARN, f.throttle))
	draw_rect(Rect2(tr.position.x - 4, tr.end.y - th - 5, tr.size.x + 8, 10), Color(0.9, 0.9, 0.95))
	draw_string(font, Vector2(tr.position.x - 10, tr.end.y + 16), "%d%%" % roundi(f.throttle * 100),
		HORIZONTAL_ALIGNMENT_CENTER, 44, 13, Color.WHITE)
	# Engine power (N1-style) bars.
	var x := r.position.x + 44
	for i in 2:
		var power: float = f.engine_power[i]
		var on_fire: bool = world.plane.engine_fire[i]
		var er := Rect2(x + i * 22, tr.position.y, 14, tr.size.y)
		_instrument_bg(er)
		var eh := er.size.y * clampf(power * f.throttle, 0.0, 1.0)
		var col := BAD if on_fire and fmod(_t, 0.5) < 0.3 else Color(0.4, 0.8, 1.0)
		draw_rect(Rect2(er.position.x + 2, er.end.y - eh, er.size.x - 4, eh), col)
		draw_string(font, Vector2(er.position.x - 4, er.end.y + 16), "LR"[i], HORIZONTAL_ALIGNMENT_CENTER, 22, 12, DIM)
	draw_string(font, Vector2(x - 4, r.position.y + 10), "ENG", HORIZONTAL_ALIGNMENT_CENTER, 50, 12, DIM)
	# Flaps and gear.
	var bx := r.position.x + 100
	var flaps := f.flaps
	_annunciator(font, Rect2(bx, r.position.y + 4, 66, 50), "FLAPS", ["UP", "1", "FULL"][clampi(flaps, 0, 2)],
		GOOD if flaps > 0 else DIM, "[F]")
	_annunciator(font, Rect2(bx, r.position.y + 76, 66, 50), "GEAR", "DOWN" if f.gear_down else "UP",
		GOOD if f.gear_down else WARN, "[G]")
	if f.gear_down:
		for k in 3:
			draw_rect(Rect2(bx + 10 + k * 18, r.position.y + 150, 12, 12), GOOD)


func _annunciator(font: Font, r: Rect2, title: String, value: String, col: Color, key: String) -> void:
	draw_rect(r, Color(col, 0.18))
	draw_rect(r, col, false, 2.0)
	draw_string(font, r.position + Vector2(0, 16), title, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, DIM)
	draw_string(font, r.position + Vector2(0, 40), value, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 19, col)
	draw_string(font, r.position + Vector2(0, r.size.y + 15), key, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, DIM)


## Health bars for every damageable part, flashing when critical.
func _damage(font: Font, r: Rect2) -> void:
	draw_string(font, r.position + Vector2(0, 10), "AIRFRAME", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
	for i in PARTS.size():
		var y := r.position.y + 22 + i * 25
		var hp := part_health(world, PARTS[i][0])
		var col := health_color(hp, _t)
		draw_string(font, Vector2(r.position.x, y + 14), PARTS[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		var bar := Rect2(r.position.x + 56, y + 3, r.size.x - 100, 13)
		_instrument_bg(bar)
		draw_rect(Rect2(bar.position + Vector2(2, 2), Vector2((bar.size.x - 4) * hp, bar.size.y - 4)), col)
		var fire := i < 2 and bool(world.plane.engine_fire[i])
		var tag := "FIRE" if fire else "%d%%" % roundi(hp * 100)
		draw_string(font, Vector2(bar.end.x + 4, y + 14), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			BAD if fire and fmod(_t, 0.5) < 0.3 else col)


## Distance, turn arrow and glide-slope advice to the runway threshold.
func _navigation(font: Font, r: Rect2, f: FlightModel) -> void:
	var to := FlightModel.runway_threshold() - f.pos
	var dist := Vector2(to.x, to.z).length()
	var turn := wrapf(atan2(-to.x, -to.z) - f.yaw, -PI, PI)   # Positive = turn left.
	draw_string(font, r.position + Vector2(0, 10), "RUNWAY 36", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, DIM)
	var c := r.position + Vector2(r.size.x * 0.5, 66)
	draw_circle(c, 46, Color(0.08, 0.12, 0.22))
	draw_arc(c, 46, 0, TAU, 40, BEZEL, 3.0)
	var pts := PackedVector2Array()
	for p in [Vector2(0, -36), Vector2(20, -6), Vector2(7, -6), Vector2(7, 30), Vector2(-7, 30), Vector2(-7, -6), Vector2(-20, -6)]:
		pts.append(c + (p as Vector2).rotated(-turn))
	draw_colored_polygon(pts, WARN)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.4, 0.25, 0.0), 2.0)
	draw_string(font, Vector2(r.position.x, r.position.y + 134), "%.1f km" % (dist / 1000.0),
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20, Color.WHITE)
	var deg := roundi(absf(rad_to_deg(turn)))
	var hint := "STRAIGHT AHEAD" if deg < 4 else ("TURN %s %d°" % ["LEFT" if turn > 0.0 else "RIGHT", deg])
	draw_string(font, Vector2(r.position.x, r.position.y + 154), hint, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, WARN)
	if dist < 16000.0:
		var ideal := dist * GLIDE_SLOPE
		var glide := "GLIDE: ON SLOPE"
		var gcol := GOOD
		if f.pos.y > ideal + 60.0:
			glide = "GLIDE: TOO HIGH"
			gcol = WARN
		elif f.pos.y < ideal - 40.0:
			glide = "GLIDE: TOO LOW"
			gcol = BAD
		draw_string(font, Vector2(r.position.x, r.position.y + 172), glide, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, gcol)


## Flashing master-warning banners across the top of the cluster.
func _warnings(font: Font, f: FlightModel) -> void:
	var msgs: Array[String] = []
	if f.phase == FlightModel.Phase.FLYING:
		if f.stalled or f.speed < f.stall_speed() + 4.0:
			msgs.append("STALL")
		if f.altitude() < 150.0 and not f.gear_down:
			msgs.append("GEAR!")
		if f.altitude() < 300.0 and f.velocity.y < -FlightModel.MAX_SINK * 1.5:
			msgs.append("PULL UP")
	for i in 2:
		if world.plane.engine_fire[i]:
			msgs.append("FIRE " + ("L" if i == 0 else "R"))
	if msgs.is_empty() or fmod(_t, 0.7) > 0.45:
		return
	var text := "  ".join(msgs)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 30
	var box := Rect2(size.x * 0.5 - w * 0.5, -34, w, 30)
	draw_rect(box, BAD)
	draw_rect(box, Color.WHITE, false, 2.0)
	draw_string(font, box.position + Vector2(0, 23), text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 22, Color.WHITE)
