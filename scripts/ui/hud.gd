extends CanvasLayer
## HUD: prompts, subtitles, toasts, flight panel, pause and results.

var world: World


func blocking_input() -> bool:
	return false
