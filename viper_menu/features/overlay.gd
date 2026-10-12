extends Node

## Corner overlay: watermark, FPS, resolution.

var app = null
var font: Font


func setup() -> void:
	app.cfg.def("overlay.watermark", true)
	app.cfg.def("overlay.fps", false)
	app.cfg.def("overlay.res", false)
	font = ThemeDB.fallback_font
	app.add_drawer(_draw_overlay)


func _draw_overlay(c: Control) -> void:
	var lines: Array = []
	if app.cfg.val("overlay.watermark", true):
		lines.append([app.MOD_NAME + " " + app.VERSION, Color("#3ddc84")])
	if app.cfg.val("overlay.fps", false):
		lines.append(["FPS %d" % Engine.get_frames_per_second(), Color.WHITE])
	if app.cfg.val("overlay.res", false):
		var ws := DisplayServer.window_get_size()
		var vs := c.get_viewport_rect().size
		lines.append(["%dx%d (view %dx%d)" % [ws.x, ws.y, int(vs.x), int(vs.y)], Color.WHITE])
	var y := 4.0 + _sz(15)
	for l in lines:
		text(c, Vector2(8, y), str(l[0]), l[1], 15)
		y += _sz(15) + 3.0


## Text sizes are written for 1080p; scale them to the game's UI resolution.
func _sz(size: int) -> int:
	var f := 1.0
	if app.ui != null and app.ui.has_method("res_factor"):
		f = app.ui.res_factor()
	return maxi(8, int(round(size * f)))


## Shared helper: outlined text so it reads on any background.
func text(c: Control, pos: Vector2, s: String, col: Color, size: int = 14, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var fs := _sz(size)
	c.draw_string_outline(font, pos, s, align, width, fs, maxi(2, fs / 4), Color(0, 0, 0, 0.85 * col.a))
	c.draw_string(font, pos, s, align, width, fs, col)


func text_center(c: Control, pos: Vector2, s: String, col: Color, size: int = 14) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, _sz(size)).x
	text(c, Vector2(pos.x - w * 0.5, pos.y), s, col, size)


## A small HUD box (used by solvers / duck hunt) anchored under the watermark.
func hud_box(c: Control, pos: Vector2, rows: Array, size: int = 16) -> void:
	if rows.is_empty():
		return
	var fs := _sz(size)
	var w := 0.0
	for r in rows:
		w = maxf(w, font.get_string_size(str(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var h := rows.size() * (fs + 6) + 10
	c.draw_rect(Rect2(pos - Vector2(8, fs + 4), Vector2(w + 16, h)), Color(0, 0, 0, 0.55))
	var y := pos.y
	for r in rows:
		text(c, Vector2(pos.x, y), str(r[0]), r[1], size)
		y += fs + 6


## HUD box horizontally centred on the screen at height y.
func hud_center(c: Control, y: float, rows: Array, size: int = 16) -> void:
	var fs := _sz(size)
	var w := 0.0
	for r in rows:
		w = maxf(w, font.get_string_size(str(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	hud_box(c, Vector2((c.get_viewport_rect().size.x - w) * 0.5, y), rows, size)
