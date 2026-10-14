extends Node

## The menu window, its tabs, and a small widget kit. Widgets bind straight to
## config keys, so features just read app.cfg.val(...) each frame.

var app = null

const TABS := ["Debug", "ESP", "Aimbot", "Solvers", "Players", "Minigames", "Session", "Server Browser", "Bots", "Misc", "Hotkeys", "Settings", "Info"]
## Which module methods fill each tab, in order.
const TAB_BUILDERS := {
	"Debug": [["debug", "build_ui"]],
	"ESP": [["esp", "build_ui"]],
	"Aimbot": [["aimbot", "build_ui"]],
	"Solvers": [["solvers", "build_ui"], ["duck", "build_ui"]],
	"Players": [["players", "build_ui"]],
	"Minigames": [["minigames", "build_ui"]],
	"Session": [["session", "build_ui"]],
	"Server Browser": [["browser", "build_ui"]],
	"Bots": [["bots", "build_ui"]],
	"Misc": [["misc", "build_ui"], ["duck", "build_misc_ui"]],
}

const ACCENT := Color("#3ddc84")
const ACCENT_DIM := Color("#1f6e43")
const BG := Color(0.065, 0.072, 0.082, 0.97)
const BG2 := Color(0.11, 0.12, 0.135, 1.0)
const BG3 := Color(0.16, 0.17, 0.19, 1.0)
const TEXT := Color(0.9, 0.92, 0.94)
const MUTED := Color(0.58, 0.62, 0.66)
const WARN := Color("#ffb347")
const BAD := Color("#ff5c5c")
const DEFAULT_SIZE := Vector2(880, 620)
const MIN_SIZE := Vector2(560, 440)
const EDGE := 6.0

var layer: CanvasLayer
var root: PanelContainer
var tab_col: VBoxContainer
var scroll: ScrollContainer
var page_holder: VBoxContainer
var status_label: Label
var pages: Dictionary = {}
var tab_buttons: Dictionary = {}
var current_tab := ""
var is_open := false
var theme: Theme

var _bound: Array = []      # [key, Callable refresh]
var _bound_by_key: Dictionary = {}
var _in_refresh := false
var _live: Array = []       # [Label, Callable text_fn]
var _live_t := 0.0
var _dragging := false
var _resizing := false
var _resize_from := Vector2.ZERO
var _resize_start := Vector2.ZERO
var _drag_off := Vector2.ZERO
var _cursor_saved := false
var _saved_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _saved_pause_can_activate = null
var _saved_game_focused = null


func setup() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	app.cfg.def("ui.freeze_input", true)
	app.cfg.def("ui.pos", Vector2(40, 30))
	app.cfg.def("ui.size", DEFAULT_SIZE)
	app.cfg.def("ui.auto_fit", true)
	app.cfg.def("ui.scale", 1.0)
	app.cfg.def("ui.tab", "Minigames")


func build() -> void:
	theme = _make_theme()
	layer = CanvasLayer.new()
	layer.name = "ViperMenu"
	layer.layer = 120
	add_child(layer)

	root = PanelContainer.new()
	root.name = "Window"
	root.theme = theme
	root.custom_minimum_size = MIN_SIZE
	root.size = _base_size()
	root.position = app.cfg.val("ui.pos", Vector2(40, 30))
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	layer.add_child(root)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	root.add_child(outer)

	# Header (drag handle)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.gui_input.connect(_on_header_input)
	outer.add_child(header)
	var title := Label.new()
	title.text = "%s  %s" % [app.MOD_NAME.to_upper(), app.VERSION]
	title.add_theme_color_override("font_color", ACCENT)
	title.add_theme_font_size_override("font_size", 17)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", MUTED)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(status_label)
	var close := Button.new()
	close.text = "  X  "
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: set_open(false))
	header.add_child(close)

	outer.add_child(HSeparator.new())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	outer.add_child(body)

	tab_col = VBoxContainer.new()
	tab_col.custom_minimum_size = Vector2(118, 0)
	tab_col.add_theme_constant_override("separation", 3)
	body.add_child(tab_col)

	scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 14)
	scroll.add_child(margin)
	page_holder = VBoxContainer.new()
	page_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(page_holder)

	var group := ButtonGroup.new()
	for tab in TABS:
		var b := Button.new()
		b.text = tab
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(show_tab.bind(tab))
		tab_col.add_child(b)
		tab_buttons[tab] = b

		var page := VBoxContainer.new()
		page.name = tab
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 6)
		page.visible = false
		page_holder.add_child(page)
		pages[tab] = page
		_build_page(tab, page)

	var foot_row := HBoxContainer.new()
	outer.add_child(foot_row)
	var foot := Label.new()
	foot.add_theme_color_override("font_color", MUTED)
	foot.add_theme_font_size_override("font_size", 12)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.clip_text = true
	foot_row.add_child(foot)
	var grip := Control.new()
	grip.custom_minimum_size = Vector2(18, 18)
	grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	grip.tooltip_text = "Drag to resize"
	grip.gui_input.connect(_on_grip_input)
	grip.draw.connect(func() -> void:
		for i in 3:
			var o := 5.0 + i * 5.0
			grip.draw_line(Vector2(18, 18 - o), Vector2(18 - o, 18), ACCENT_DIM.lightened(0.3), 1.5, true)
	)
	foot_row.add_child(grip)
	add_live_label(foot, func() -> String:
		return "%s menu   %s unload   Esc close   right-click a key button to clear it" % [
			app.hk.bind_name(app.hk.bind_of("menu")), app.hk.bind_name(app.hk.bind_of("unload"))])

	var start_tab := str(app.cfg.val("ui.tab", "Minigames"))
	show_tab(start_tab if pages.has(start_tab) else "Minigames")
	app.cfg.reloaded.connect(refresh_bound)
	app.cfg.changed.connect(_on_cfg_changed)
	app.cfg.changed.connect(func(key: String, _v) -> void:
		if key == "ui.scale" or key == "ui.auto_fit":
			apply_layout()
	)
	app.cfg.reloaded.connect(apply_layout)
	get_viewport().size_changed.connect(apply_layout)
	apply_layout()


func _build_page(tab: String, page: VBoxContainer) -> void:
	match tab:
		"Hotkeys":
			_build_hotkeys(page)
			return
		"Settings":
			_build_settings(page)
			return
		"Info":
			_build_info(page)
			return
	for pair in TAB_BUILDERS.get(tab, []):
		var m = app.mod(pair[0])
		if m != null and m.has_method(pair[1]):
			m.call(pair[1], self, page)
		elif m == null:
			note(page, "Module '%s' failed to load - check modloader.log." % pair[0], BAD)


func show_tab(tab: String) -> void:
	if not pages.has(tab):
		return
	for t in pages.keys():
		pages[t].visible = (t == tab)
	for t in tab_buttons.keys():
		tab_buttons[t].set_pressed_no_signal(t == tab)
	current_tab = tab
	app.cfg.put("ui.tab", tab)
	scroll.scroll_vertical = 0


func page(tab: String) -> VBoxContainer:
	return pages.get(tab, null)


# --- open / close & cursor ------------------------------------------------------

func set_open(v: bool) -> void:
	if root == null or v == is_open:
		return
	is_open = v
	root.visible = v
	if v:
		apply_layout()
		_refresh_live(true)
		_take_cursor()
	else:
		var vp := get_viewport()
		if vp != null:
			vp.gui_release_focus()
		if app.hk.capturing != "":
			app.hk.cancel_capture()
		app.cfg.put("ui.pos", root.position)
		_give_cursor()


func _take_cursor() -> void:
	_saved_mouse_mode = Input.mouse_mode
	var cm: Node = app.g.al("CursorManager")
	if cm != null:
		app.g.sv(cm, "active_after_lock", app.g.gv(cm, "active", true))
		if cm.has_method("is_visible"):
			app.g.sv(cm, "visible_after_lock", cm.is_visible())
		app.g.sv(cm, "image_after_lock", app.g.gv(cm, "cursor_image_name", &"point"))
		app.g.sv(cm, "mouse_mode_after_lock", Input.mouse_mode)
		app.g.call_safe(cm, "set_locked", [false, false])
		app.g.call_safe(cm, "set_active", [true])
		app.g.call_safe(cm, "set_cursor", [true, false])
		app.g.call_safe(cm, "set_cursor_image", [&"point"])
		app.g.call_safe(cm, "set_locked", [true])
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_cursor_saved = true

	# Keep Esc from opening the game's pause menu while ours is open.
	var pm: Node = app.g.al("PauseMenu")
	if pm != null and ("can_activate" in pm):
		_saved_pause_can_activate = pm.get("can_activate")
		app.g.call_safe(pm, "set_can_activate", [false])
	# Most player scripts skip input while the game is unfocused.
	if bool(app.cfg.val("ui.freeze_input", true)):
		var gm: Node = app.g.al("GameManager")
		if gm != null and ("game_focused" in gm):
			_saved_game_focused = gm.get("game_focused")
			gm.set("game_focused", false)


func _give_cursor() -> void:
	if not _cursor_saved:
		return
	_cursor_saved = false
	var gm: Node = app.g.al("GameManager")
	if _saved_game_focused != null and gm != null:
		gm.set("game_focused", _saved_game_focused)
	_saved_game_focused = null
	var pm: Node = app.g.al("PauseMenu")
	if pm != null and _saved_pause_can_activate != null:
		# Deferred: if Esc closed us, the game's pause menu would otherwise see
		# the same Esc press this frame and open.
		app.g.call_safe.call_deferred(pm, "set_can_activate", [_saved_pause_can_activate])
	_saved_pause_can_activate = null
	var cm: Node = app.g.al("CursorManager")
	if cm != null:
		app.g.call_safe(cm, "set_locked", [false])
	else:
		Input.mouse_mode = _saved_mouse_mode
	# Same signal the game's own dev panel uses; minigames re-capture the mouse.
	if pm != null and pm.has_signal("unpaused"):
		pm.emit_signal("unpaused")


func shutdown() -> void:
	set_open(false)


func _process(delta: float) -> void:
	if not is_open:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_live_t += delta
	if _live_t >= 0.25:
		_live_t = 0.0
		_refresh_live(false)


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if app.hk.capturing == "":
			set_open(false)
			get_viewport().set_input_as_handled()


func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_off = root.get_global_mouse_position() - root.position
		if not event.pressed:
			app.cfg.put("ui.pos", root.position)
	elif event is InputEventMouseMotion and _dragging:
		root.position = _clamp_pos(root.get_global_mouse_position() - _drag_off)


func _on_grip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_resizing = event.pressed
		_resize_from = root.get_global_mouse_position()
		_resize_start = root.size
		if not event.pressed:
			app.cfg.put("ui.size", root.size)
			apply_layout()
	elif event is InputEventMouseMotion and _resizing:
		var sc: float = root.scale.x if root.scale.x > 0.0 else 1.0
		var want: Vector2 = _resize_start + (root.get_global_mouse_position() - _resize_from) / sc
		var vp := _vp_size()
		var max_size := Vector2(maxf(MIN_SIZE.x, (vp.x - root.position.x - EDGE) / sc), maxf(MIN_SIZE.y, (vp.y - root.position.y - EDGE) / sc))
		root.size = want.clamp(MIN_SIZE, max_size)


## The menu was designed at 1080p. When the game's UI space is smaller (it
## lays out at 960x540 and stretches), scale down so it looks the same size.
func res_factor() -> float:
	return clampf(_vp_size().y / 830.0, 0.5, 1.0)


func _vp_size() -> Vector2:
	var vp := get_viewport()
	return vp.get_visible_rect().size if vp != null else Vector2(1920, 1080)


func _base_size() -> Vector2:
	var sz = app.cfg.val("ui.size", DEFAULT_SIZE)
	if not (sz is Vector2):
		sz = DEFAULT_SIZE
	return sz.max(MIN_SIZE)


## Size and scale the window so all of it is on screen. The game lays its UI
## out at a small base resolution (960x540) and stretches it, so the menu has
## to fit that space, not your monitor's.
func apply_layout() -> void:
	if root == null:
		return
	var vp := _vp_size()
	var base := _base_size()
	var sc := clampf(float(app.cfg.val("ui.scale", 1.0)), 0.4, 2.0) * res_factor()
	if bool(app.cfg.val("ui.auto_fit", true)):
		var fit := minf((vp.x - EDGE * 2.0) / base.x, (vp.y - EDGE * 2.0) / base.y)
		if fit < sc:
			# Shrink the window toward its minimum first, then scale the rest.
			var room := (vp - Vector2(EDGE, EDGE) * 2.0) / sc
			base = base.min(room).max(MIN_SIZE)
			fit = minf((vp.x - EDGE * 2.0) / base.x, (vp.y - EDGE * 2.0) / base.y)
			sc = minf(sc, fit)
	sc = maxf(sc, 0.3)
	root.scale = Vector2(sc, sc)
	root.size = base
	root.position = _clamp_pos(root.position)


## Keep the whole (scaled) window inside the screen.
func _clamp_pos(p) -> Vector2:
	var pos: Vector2 = p if p is Vector2 else Vector2(40, 30)
	if root == null:
		return pos
	var vp := _vp_size()
	var shown: Vector2 = root.size * root.scale
	pos.x = clampf(pos.x, 0.0, maxf(vp.x - shown.x, 0.0))
	pos.y = clampf(pos.y, 0.0, maxf(vp.y - shown.y, 0.0))
	return pos


func reset_window() -> void:
	app.cfg.put("ui.size", DEFAULT_SIZE)
	app.cfg.put("ui.scale", 1.0)
	app.cfg.put("ui.auto_fit", true)
	root.position = Vector2(40, 30)
	apply_layout()
	app.cfg.put("ui.pos", root.position)


# --- bound refresh / live labels ------------------------------------------------

func refresh_bound() -> void:
	_prune()
	for e in _bound:
		if is_instance_valid(e[2]) and e[1].is_valid():
			e[1].call()


## Register a widget refresher. Entries die with their widget (ESP rebuilds
## its object list, so widgets come and go).
func _bind(key: String, refresh: Callable, widget: Object) -> void:
	var e := [key, refresh, widget]
	_bound.append(e)
	if not _bound_by_key.has(key):
		_bound_by_key[key] = []
	_bound_by_key[key].append(e)


func _prune() -> void:
	var keep: Array = []
	for e in _bound:
		if is_instance_valid(e[2]):
			keep.append(e)
	_bound = keep
	for k in _bound_by_key.keys():
		var lst: Array = []
		for e in _bound_by_key[k]:
			if is_instance_valid(e[2]):
				lst.append(e)
		if lst.is_empty():
			_bound_by_key.erase(k)
		else:
			_bound_by_key[k] = lst


## Keep widgets in sync when a value changes from a hotkey or another module.
func _on_cfg_changed(key: String, _v) -> void:
	if _in_refresh or not _bound_by_key.has(key):
		return
	_in_refresh = true
	var stale := false
	for e in _bound_by_key[key]:
		if not is_instance_valid(e[2]):
			stale = true
			continue
		if e[1].is_valid():
			e[1].call()
	_in_refresh = false
	if stale:
		_prune()


func add_live_label(label: Label, text_fn: Callable) -> void:
	_live.append([label, text_fn])
	if text_fn.is_valid():
		label.text = str(text_fn.call())


func _refresh_live(force: bool) -> void:
	for pair in _live:
		var l = pair[0]
		var fn: Callable = pair[1]
		if not is_instance_valid(l) or not fn.is_valid():
			continue
		if not force and not l.is_visible_in_tree():
			continue
		l.text = str(fn.call())


# --- widget kit -------------------------------------------------------------------

func header(parent: Control, text: String) -> Label:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	parent.add_child(gap)
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_color_override("font_color", ACCENT)
	l.add_theme_font_size_override("font_size", 15)
	parent.add_child(l)
	var sep := HSeparator.new()
	parent.add_child(sep)
	return l


func note(parent: Control, text: String, color: Color = MUTED) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 12)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(200, 0)
	parent.add_child(l)
	return l


func live(parent: Control, text_fn: Callable, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(200, 0)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	add_live_label(l, text_fn)
	return l


func row(parent: Control, label_text: String, tip: String = "") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = label_text
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	h.add_child(l)
	parent.add_child(h)
	return h


func check(parent: Control, label_text: String, key: String, tip: String = "", on_change: Callable = Callable()) -> CheckButton:
	var h := row(parent, label_text, tip)
	var c := CheckButton.new()
	c.focus_mode = Control.FOCUS_NONE
	c.tooltip_text = tip
	c.button_pressed = bool(app.cfg.val(key, false))
	c.toggled.connect(func(v: bool) -> void:
		app.cfg.put(key, v)
		if on_change.is_valid():
			on_change.call(v)
	)
	h.add_child(c)
	_bind(key, func() -> void: c.set_pressed_no_signal(bool(app.cfg.val(key, false))), c)
	return c


func slider(parent: Control, label_text: String, key: String, mn: float, mx: float, step: float, tip: String = "", fmt: String = "%.2f") -> HSlider:
	var h := row(parent, label_text, tip)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(190, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.tooltip_text = tip
	var vl := Label.new()
	vl.custom_minimum_size = Vector2(58, 0)
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var is_int: bool = typeof(app.cfg.defaults.get(key, 0.0)) == TYPE_INT
	s.value = float(app.cfg.val(key, mn))
	vl.text = _fmt(fmt, s.value, is_int)
	s.value_changed.connect(func(v: float) -> void:
		app.cfg.put(key, int(round(v)) if is_int else v)
		vl.text = _fmt(fmt, v, is_int)
	)
	h.add_child(s)
	h.add_child(vl)
	_bind(key, func() -> void:
		s.set_value_no_signal(float(app.cfg.val(key, mn)))
		vl.text = _fmt(fmt, s.value, is_int)
	, s)
	return s


func _fmt(fmt: String, v: float, is_int: bool) -> String:
	if is_int:
		return str(int(round(v)))
	return fmt % v


func spin(parent: Control, label_text: String, key: String, mn: int, mx: int, tip: String = "") -> SpinBox:
	var h := row(parent, label_text, tip)
	var s := SpinBox.new()
	s.min_value = mn
	s.max_value = mx
	s.step = 1
	s.value = int(app.cfg.val(key, mn))
	s.tooltip_text = tip
	s.value_changed.connect(func(v: float) -> void: app.cfg.put(key, int(v)))
	h.add_child(s)
	_bind(key, func() -> void: s.set_value_no_signal(int(app.cfg.val(key, mn))), s)
	return s


## items: Array of Strings; the chosen string is stored in the config key.
func option(parent: Control, label_text: String, key: String, items: Array, tip: String = "", on_change: Callable = Callable()) -> OptionButton:
	var h := row(parent, label_text, tip)
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.tooltip_text = tip
	ob.custom_minimum_size = Vector2(170, 0)
	for it in items:
		ob.add_item(str(it))
	var sync := func() -> void:
		var cur := str(app.cfg.val(key, ""))
		var idx := items.find(cur)
		ob.select(idx if idx >= 0 else 0)
	sync.call()
	ob.item_selected.connect(func(i: int) -> void:
		app.cfg.put(key, str(items[i]))
		if on_change.is_valid():
			on_change.call(str(items[i]))
	)
	h.add_child(ob)
	_bind(key, sync, ob)
	return ob


## Option list whose entries are rebuilt from items_fn() each time it opens.
## items_fn returns [[value, text], ...]; the value is stored in the key.
func option_dynamic(parent: Control, label_text: String, key: String, items_fn: Callable, tip: String = "") -> OptionButton:
	var h := row(parent, label_text, tip)
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.custom_minimum_size = Vector2(190, 0)
	ob.tooltip_text = tip
	var values: Array = []
	var rebuild := func() -> void:
		values.clear()
		ob.clear()
		var items: Array = items_fn.call()
		var cur = app.cfg.val(key, null)
		var sel := -1
		for i in items.size():
			values.append(items[i][0])
			ob.add_item(str(items[i][1]))
			if str(items[i][0]) == str(cur):
				sel = i
		if sel >= 0:
			ob.select(sel)
		elif items.size() > 0:
			ob.select(-1)
			ob.text = "(choose)"
	rebuild.call()
	ob.pressed.connect(rebuild)
	ob.item_selected.connect(func(i: int) -> void:
		if i >= 0 and i < values.size():
			app.cfg.put(key, values[i])
	)
	h.add_child(ob)
	# On outside changes just re-select; the list itself is rebuilt when opened.
	_bind(key, func() -> void:
		var cur = app.cfg.val(key, null)
		for i in values.size():
			if str(values[i]) == str(cur):
				if ob.selected != i:
					ob.select(i)
				return
	, ob)
	return ob


func color(parent: Control, label_text: String, key: String, tip: String = "") -> ColorPickerButton:
	var h := row(parent, label_text, tip)
	var c := ColorPickerButton.new()
	c.custom_minimum_size = Vector2(54, 24)
	c.edit_alpha = true
	c.focus_mode = Control.FOCUS_NONE
	c.color = app.cfg.val(key, Color.WHITE)
	c.color_changed.connect(func(v: Color) -> void: app.cfg.put(key, v))
	h.add_child(c)
	_bind(key, func() -> void:
		var want: Color = app.cfg.val(key, Color.WHITE)
		if c.color != want:
			c.color = want
	, c)
	return c


func text_input(parent: Control, label_text: String, key: String, placeholder: String = "", tip: String = "") -> LineEdit:
	var h := row(parent, label_text, tip)
	var e := LineEdit.new()
	e.custom_minimum_size = Vector2(200, 0)
	e.placeholder_text = placeholder
	e.text = str(app.cfg.val(key, ""))
	e.text_changed.connect(func(t: String) -> void: app.cfg.put(key, t))
	e.text_submitted.connect(func(_t: String) -> void: e.release_focus())
	h.add_child(e)
	_bind(key, func() -> void:
		var want := str(app.cfg.val(key, ""))
		if e.text != want:
			e.text = want
	, e)
	return e


func tri(parent: Control, label_text: String, key: String, value_fn: Callable = Callable(), tip: String = "") -> OptionButton:
	var h := row(parent, label_text, tip)
	if value_fn.is_valid():
		var vl := Label.new()
		vl.custom_minimum_size = Vector2(70, 0)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vl.add_theme_color_override("font_color", MUTED)
		h.add_child(vl)
		add_live_label(vl, value_fn)
	var items := ["Leave", "Force On", "Force Off"]
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.custom_minimum_size = Vector2(120, 0)
	for it in items:
		ob.add_item(it)
	var sync := func() -> void:
		var idx := items.find(str(app.cfg.val(key, "Leave")))
		ob.select(maxi(idx, 0))
	sync.call()
	ob.item_selected.connect(func(i: int) -> void: app.cfg.put(key, items[i]))
	h.add_child(ob)
	_bind(key, sync, ob)
	return ob


func keybind(parent: Control, id: String) -> Button:
	var label_text: String = app.hk.actions.get(id, {}).get("label", id)
	var h := row(parent, label_text, "Click, then press a key or mouse button. Esc cancels. Right-click clears.")
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 0)
	var sync := func() -> void: b.text = app.hk.bind_name(app.hk.bind_of(id))
	sync.call()
	b.pressed.connect(func() -> void:
		b.text = "press a key..."
		app.hk.start_capture(id, sync)
	)
	b.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT and app.hk.capturing == "":
			app.hk.set_bind(id, app.hk.unbound())
			sync.call()
	)
	h.add_child(b)
	_bind("bind." + id, sync, b)
	return b


func button(parent: Control, text: String, cb: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func buttons(parent: Control, specs: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	parent.add_child(h)
	for s in specs:
		var b := button(h, str(s[0]), s[1], str(s[2]) if s.size() > 2 else "")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return h


## Collapsible block. Returns the inner container.
func section(parent: Control, title: String, open: bool = false) -> VBoxContainer:
	var b := Button.new()
	b.text = ("v  " if open else ">  ") + title
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.add_theme_color_override("font_color", TEXT)
	parent.add_child(b)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 18)
	m.visible = open
	parent.add_child(m)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 5)
	m.add_child(inner)
	b.pressed.connect(func() -> void:
		m.visible = not m.visible
		b.text = ("v  " if m.visible else ">  ") + title
	)
	return inner


func clear(container: Node) -> void:
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()


# --- built-in tabs ------------------------------------------------------------------

func _build_hotkeys(p: VBoxContainer) -> void:
	note(p, "Click a binding, then press any key or mouse button (Mouse 1-5, Alt, Shift, Ctrl, F-keys, numpad all work). Esc cancels. Right-click a binding to clear it.")
	var groups: Dictionary = {}
	for id in app.hk.order:
		var grp: String = app.hk.actions[id].get("group", "General")
		if not groups.has(grp):
			groups[grp] = []
		groups[grp].append(id)
	for grp in groups.keys():
		header(p, grp)
		for id in groups[grp]:
			keybind(p, id)


func _build_settings(p: VBoxContainer) -> void:
	header(p, "Config")
	buttons(p, [
		["Save config", _on_save_pressed],
		["Load config", _on_load_pressed],
		["Reset", _on_reset_pressed],
	])
	live(p, func() -> String: return "File: " + ProjectSettings.globalize_path(app.cfg.path), MUTED)

	header(p, "Overlay")
	check(p, "Draw FPS", "overlay.fps")
	check(p, "Draw resolution", "overlay.res")
	check(p, "Draw watermark", "overlay.watermark")

	header(p, "Menu")
	keybind(p, "menu")
	check(p, "Fit menu to screen", "ui.auto_fit",
		"Shrinks the menu so all of it stays on screen at the game's resolution.")
	slider(p, "Menu scale", "ui.scale", 0.5, 1.5, 0.05, "Bigger or smaller menu. With Fit on, it never grows past the screen.", "%.2fx")
	buttons(p, [["Reset window size and position", reset_window]])
	check(p, "Freeze my game input while the menu is open", "ui.freeze_input",
		"Stops your character from reacting to clicks and mouse movement while you use the menu.")

	header(p, "Safety")
	var b := button(p, "Disable all cheats", func() -> void: app.panic(),
		"Turns off ESP, aimbot, solvers, godmode, noclip and every other gameplay toggle.")
	b.add_theme_color_override("font_color", WARN)
	var u := button(p, "Unload mod now", func() -> void: app.unload(), "Same as the Unload hotkey.")
	u.add_theme_color_override("font_color", BAD)


func _on_save_pressed() -> void:
	app.cfg.save_file()


func _on_load_pressed() -> void:
	if app.cfg.load_file():
		app.note("settings loaded")
	else:
		app.note("no saved config found")


func _on_reset_pressed() -> void:
	app.cfg.reset()


func _build_info(p: VBoxContainer) -> void:
	header(p, app.MOD_NAME)
	live(p, func() -> String:
		return "Developed by %s\nVersion %s\nLoader v%s (API %s)" % [
			app.AUTHOR, app.VERSION,
			str(app.loader.loader_version()) if app.loader.has_method("loader_version") else "?",
			str(app.loader.api_version()) if app.loader.has_method("api_version") else "?"])
	buttons(p, [
		["GitHub", func() -> void: _open_url(app.GITHUB_URL)],
		["YouTube", func() -> void: _open_url(app.YOUTUBE_URL)],
	])
	header(p, "Credits")
	note(p, "xViperCodes - Viper Menu\nObsidian420 - inspiration and a lot of the cheat / solver ideas\nKrunk-theduck - MachinePartyModLoader\nJ_axon and Krunk - MachineParty+ (the server browser and public lobbies are adapted from it, MIT License)", TEXT)
	live(p, func() -> String:
		var br = app.mod("browser")
		if br != null and br.has_8p():
			return "8 Player mod (Binary1936/machine-party-8p) detected - lobbies here can hold up to %d players." % br.player_cap()
		return "8 Player mod: not installed. Viper Menu works alongside Binary1936's machine-party-8p if you install it.", MUTED)
	header(p, "Session")
	live(p, func() -> String:
		var mg: String = app.g.minigame_cls()
		return "Role: %s   |   My id: %d   |   Online: %s\nScene: %s\nMinigame: %s" % [
			"host" if app.g.is_host() else "client", app.g.my_id(), "yes" if app.g.online() else "no",
			app.g.cls(app.g.scene()) if app.g.scene() else "-", mg if mg != "" else "-"])
	header(p, "Loaded mods")
	live(p, func() -> String: return "\n".join(app.loader.mod_list()) if app.loader.has_method("mod_list") else "-", MUTED)


func _open_url(url: String) -> void:
	if url.is_empty():
		app.note("no link set - edit GITHUB_URL / YOUTUBE_URL at the top of main.gd")
		return
	OS.shell_open(url)


# --- theme ---------------------------------------------------------------------------

func _box(bg: Color, radius: int = 4, border: Color = Color(0, 0, 0, 0), bw: int = 0, pad: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	var panel := _box(BG, 8, ACCENT_DIM, 1, 12)
	panel.content_margin_top = 10
	panel.content_margin_bottom = 10
	t.set_stylebox("panel", "PanelContainer", panel)

	for cls_name in ["Button", "OptionButton", "ColorPickerButton"]:
		t.set_stylebox("normal", cls_name, _box(BG2))
		t.set_stylebox("hover", cls_name, _box(BG3))
		t.set_stylebox("pressed", cls_name, _box(ACCENT_DIM))
		t.set_stylebox("hover_pressed", cls_name, _box(ACCENT_DIM))
		t.set_stylebox("disabled", cls_name, _box(Color(0.09, 0.1, 0.11)))
		t.set_stylebox("focus", cls_name, StyleBoxEmpty.new())
		t.set_color("font_color", cls_name, TEXT)
		t.set_color("font_hover_color", cls_name, Color.WHITE)
		t.set_color("font_pressed_color", cls_name, Color.WHITE)
		t.set_color("font_hover_pressed_color", cls_name, Color.WHITE)
		t.set_color("font_disabled_color", cls_name, MUTED)

	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("normal", "LineEdit", _box(BG2, 4, BG3, 1))
	t.set_stylebox("focus", "LineEdit", _box(BG2, 4, ACCENT, 1))
	t.set_stylebox("panel", "ItemList", _box(BG2, 4, BG3, 1))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", TEXT)
	t.set_stylebox("selected", "ItemList", _box(ACCENT_DIM))
	t.set_stylebox("selected_focus", "ItemList", _box(ACCENT_DIM))
	t.set_stylebox("separator", "HSeparator", _line_style())
	t.set_constant("separation", "HSeparator", 6)

	var popup := _box(BG, 4, ACCENT_DIM, 1)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _box(ACCENT_DIM))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)

	var grab := _box(ACCENT, 6)
	t.set_stylebox("slider", "HSlider", _box(BG3, 3, Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("grabber_area", "HSlider", _box(ACCENT_DIM, 3, Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT, 3, Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", _box(ACCENT.lightened(0.2), 6))
	t.set_stylebox("scroll", "VScrollBar", _box(BG2, 6, Color(0, 0, 0, 0), 0, 2))
	return t


func _line_style() -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = BG3
	s.thickness = 1
	return s
