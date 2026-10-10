extends Node
## Player preferences (autoload "Settings"), saved to user://settings.cfg and applied live.
## Readers: Player (mouse_sensitivity, invert_y, fov), scenery/lights (quality), HUD (show_fps).
## Change values through set_value() so they are applied, saved and announced via `changed`.

signal changed

const PATH := "user://settings.cfg"
const QUALITY_NAMES := ["Low", "Medium", "High"]
const RENDER_SCALE := [0.7, 0.85, 1.0]
const MSAA := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X]
const KEYS := ["mouse_sensitivity", "invert_y", "fov", "master_volume", "quality", "fullscreen", "show_fps"]

var mouse_sensitivity := 1.0   ## Multiplier on Player.MOUSE_SENS (0.2..3).
var invert_y := false
var fov := 80.0                ## Degrees (60..110).
var master_volume := 0.8       ## Linear 0..1.
var quality := 2               ## Index into QUALITY_NAMES.
var fullscreen := false
var show_fps := false


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for k: String in KEYS:
			set(k, cfg.get_value("settings", k, get(k)))
	quality = clampi(quality, 0, QUALITY_NAMES.size() - 1)
	apply()


func set_value(key: String, value: Variant) -> void:
	if not KEYS.has(key):
		push_error("Unknown setting: " + key)
		return
	set(key, value)
	apply()
	save()
	changed.emit()


func save() -> void:
	var cfg := ConfigFile.new()
	for k: String in KEYS:
		cfg.set_value("settings", k, get(k))
	cfg.save(PATH)


## True when expensive extras (real-time shadows, far scenery detail) should be on.
func high_detail() -> bool:
	return quality >= 2


func shadows() -> bool:
	return quality >= 1


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	var vp := get_viewport()
	vp.scaling_3d_scale = RENDER_SCALE[quality]
	vp.msaa_3d = MSAA[quality]
	if DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)
