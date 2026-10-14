extends Node

## Misc: noclip, freecam, an expression console, teleport loose objects.

var app = null

# noclip
var _nc_char: Node3D = null
var _nc_layer := 0
var _nc_mask := 0
var _nc_had_physics := true

# freecam
var _fc_cam: Camera3D = null
var _fc_game_cam: Camera3D = null     # the camera the game wants; restored on exit
var _fc_yaw := 0.0
var _fc_pitch := 0.0
var _fc_dist := 5.0
var _fc_look := Vector2.ZERO          # mouse motion collected in _input
var _fc_frozen := false
var _fc_saved_focus = null
var _fc_mouse_saved := false
var _fc_saved_mouse := Input.MOUSE_MODE_VISIBLE
var _fc_mg: Node = null
var _fc_reseed_t := 0.0

# console
var _con_layer: CanvasLayer = null
var _con_panel: PanelContainer = null
var _con_log: RichTextLabel = null
var _con_input: LineEdit = null
var _history: PackedStringArray = PackedStringArray()
var _hist_i := -1


func setup() -> void:
	var c = app.cfg
	c.def("misc.noclip", false)
	c.def("misc.noclip_speed", 12.0)
	c.def("misc.console", false)
	c.def("misc.loose_target", -1)
	c.def("misc.freecam", false)
	c.def("misc.freecam_speed", 10.0)
	c.def("misc.freecam_sens", 1.0)
	c.def("misc.freecam_freeze", true)
	c.def("misc.freecam_mode", 0)
	c.def("misc.freecam_target", -1)
	app.hk.register("noclip_toggle", "Toggle noclip", app.hk.unbound(), "Misc")
	app.hk.register("freecam_toggle", "Toggle freecam", app.hk.kb(KEY_F6), "Misc")
	app.hk.register("console_toggle", "Toggle console", app.hk.kb(KEY_F8), "Misc")
	app.hk.pressed.connect(func(id: String) -> void:
		match id:
			"noclip_toggle":
				app.cfg.put("misc.noclip", not bool(app.cfg.val("misc.noclip", false)))
				app.note("noclip " + ("on" if app.cfg.val("misc.noclip", false) else "off"))
			"freecam_toggle":
				app.cfg.put("misc.freecam", not bool(app.cfg.val("misc.freecam", false)))
				app.note("freecam " + ("on" if app.cfg.val("misc.freecam", false) else "off"))
			"console_toggle":
				app.cfg.put("misc.console", not bool(app.cfg.val("misc.console", false)))
	)
	app.log_added.connect(func(line: String) -> void: _print(line, "#7fd8a6"))
	app.add_drawer(_draw_freecam)


func after_config() -> void:
	# Never start the game already flying because freecam was saved as on.
	app.cfg.put("misc.freecam", false)


func disable_all() -> void:
	app.cfg.put("misc.noclip", false)
	app.cfg.put("misc.freecam", false)
	_noclip_off()
	_freecam_off()


func shutdown() -> void:
	_noclip_off()
	_freecam_off()
	if _con_layer != null and is_instance_valid(_con_layer):
		_con_layer.queue_free()


# --- noclip ---------------------------------------------------------------------

func _process(delta: float) -> void:
	_console_visibility()
	_tick_freecam(delta)
	if not bool(app.cfg.val("misc.noclip", false)):
		_noclip_off()
		return
	var me: Node3D = app.g.my_char()
	if me == null:
		_noclip_off()
		return
	if me != _nc_char:
		_noclip_off()
		_nc_char = me
		_nc_had_physics = me.is_physics_processing()
		if me is CollisionObject3D:
			_nc_layer = me.collision_layer
			_nc_mask = me.collision_mask
			me.collision_layer = 0
			me.collision_mask = 0
		me.set_physics_process(false)
	# Some minigames switch physics / collision back on at round start, which
	# made noclip fight gravity. Keep them off while noclip is on.
	if me.is_physics_processing():
		me.set_physics_process(false)
	if me is CollisionObject3D and (me.collision_layer != 0 or me.collision_mask != 0):
		me.collision_layer = 0
		me.collision_mask = 0
	if app.ui.is_open or (_con_input != null and _con_input.has_focus()):
		return
	if _fc_cam != null:
		# WASD belongs to the freecam while it's on.
		if me is CharacterBody3D:
			me.velocity = Vector3.ZERO
		return
	# W/S/A/D move flat along the ground relative to where the camera faces
	# (so a camera tilted down doesn't push you into the floor), Space goes
	# up, Shift goes down.
	var cam: Camera3D = app.g.camera()
	var basis: Basis = cam.global_transform.basis if cam != null else me.global_transform.basis
	var fwd := Vector3(-basis.z.x, 0.0, -basis.z.z)
	if fwd.length() < 0.15:
		# Camera looking straight down: "forward" is the top of the screen.
		fwd = Vector3(basis.y.x, 0.0, basis.y.z)
	fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3.FORWARD
	var right := Vector3(basis.x.x, 0.0, basis.x.z)
	right = right.normalized() if right.length() > 0.001 else fwd.cross(Vector3.UP).normalized()
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		dir += fwd
	if Input.is_physical_key_pressed(KEY_S):
		dir -= fwd
	if Input.is_physical_key_pressed(KEY_A):
		dir -= right
	if Input.is_physical_key_pressed(KEY_D):
		dir += right
	if Input.is_physical_key_pressed(KEY_SPACE):
		dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_SHIFT):
		dir -= Vector3.UP
	if dir.length() > 0.001:
		var speed := float(app.cfg.val("misc.noclip_speed", 12.0))
		me.global_position += dir.normalized() * speed * delta
	if me is CharacterBody3D:
		me.velocity = Vector3.ZERO


func _noclip_off() -> void:
	if _nc_char == null:
		return
	if is_instance_valid(_nc_char):
		if _nc_char is CollisionObject3D:
			_nc_char.collision_layer = _nc_layer
			_nc_char.collision_mask = _nc_mask
		_nc_char.set_physics_process(_nc_had_physics)
	_nc_char = null


# --- freecam ---------------------------------------------------------------------

func freecam_active() -> bool:
	return _fc_cam != null and is_instance_valid(_fc_cam)


## True while the menu or console has the keyboard/mouse.
func _fc_busy() -> bool:
	if app.ui.is_open:
		return true
	return _con_panel != null and is_instance_valid(_con_panel) and _con_panel.visible


func _tick_freecam(delta: float) -> void:
	if not bool(app.cfg.val("misc.freecam", false)):
		_freecam_off()
		return
	if not freecam_active():
		_freecam_on()
	var vp := get_viewport()
	# If the game switched cameras (new minigame, cutscene...) remember that one
	# so it comes back when freecam ends, then take the view back.
	var cur: Camera3D = vp.get_camera_3d()
	var new_cam := false
	if cur != null and cur != _fc_cam:
		new_cam = cur != _fc_game_cam
		_fc_game_cam = cur
	if not _fc_cam.current:
		_fc_cam.current = true
	# New minigame: jump to its camera once it shows up (or after 1.5 s).
	var mg = app.g.minigame()
	if mg != _fc_mg:
		_fc_mg = mg
		_fc_reseed_t = 1.5
	if _fc_reseed_t > 0.0:
		_fc_reseed_t -= delta
		if new_cam or _fc_reseed_t <= 0.0:
			_fc_reseed_t = 0.0
			_fc_reseed()

	_fc_set_frozen(bool(app.cfg.val("misc.freecam_freeze", true)))

	var busy: bool = _fc_busy()
	if not busy:
		if not _fc_mouse_saved:
			_fc_mouse_saved = true
			_fc_saved_mouse = Input.mouse_mode
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var sens := 0.0025 * float(app.cfg.val("misc.freecam_sens", 1.0))
		_fc_yaw = wrapf(_fc_yaw - _fc_look.x * sens, -PI, PI)
		_fc_pitch = clampf(_fc_pitch - _fc_look.y * sens, -1.55, 1.55)
	_fc_look = Vector2.ZERO

	var basis := Basis.from_euler(Vector3(_fc_pitch, _fc_yaw, 0.0))
	var target: Node3D = null
	if int(app.cfg.val("misc.freecam_mode", 0)) == 1:
		var tid := int(app.cfg.val("misc.freecam_target", -1))
		target = app.g.char_of(tid if tid > 0 else app.g.my_id())
	if target != null:
		var focus: Vector3 = target.global_position + Vector3.UP * 1.2
		_fc_cam.global_transform = Transform3D(basis, focus + basis.z * _fc_dist)
		return

	var pos: Vector3 = _fc_cam.global_position
	if not busy:
		var dir := Vector3.ZERO
		# Same keys as noclip: W/S/A/D, Space up, Shift down. W flies where
		# you're looking; the mouse wheel sets the speed.
		if Input.is_physical_key_pressed(KEY_W):
			dir -= basis.z
		if Input.is_physical_key_pressed(KEY_S):
			dir += basis.z
		if Input.is_physical_key_pressed(KEY_A):
			dir -= basis.x
		if Input.is_physical_key_pressed(KEY_D):
			dir += basis.x
		if Input.is_physical_key_pressed(KEY_SPACE):
			dir += Vector3.UP
		if Input.is_physical_key_pressed(KEY_SHIFT):
			dir -= Vector3.UP
		if dir.length() > 0.001:
			var speed := float(app.cfg.val("misc.freecam_speed", 10.0))
			pos += dir.normalized() * speed * delta
	_fc_cam.global_transform = Transform3D(basis, pos)


func _input(event: InputEvent) -> void:
	if not freecam_active() or _fc_busy():
		return
	if event is InputEventMouseMotion:
		_fc_look += event.relative
	elif event is InputEventMouseButton and event.pressed:
		var up: bool = event.button_index == MOUSE_BUTTON_WHEEL_UP
		var down: bool = event.button_index == MOUSE_BUTTON_WHEEL_DOWN
		if not (up or down):
			return
		if int(app.cfg.val("misc.freecam_mode", 0)) == 1:
			_fc_dist = clampf(_fc_dist * (0.88 if up else 1.12), 1.5, 40.0)
		else:
			var s := float(app.cfg.val("misc.freecam_speed", 10.0))
			app.cfg.put("misc.freecam_speed", clampf(s * (1.15 if up else 0.87), 1.0, 80.0))


func _freecam_on() -> void:
	_fc_game_cam = app.g.camera()
	_fc_cam = Camera3D.new()
	_fc_cam.name = "ViperFreecam"
	add_child(_fc_cam)
	_fc_mg = app.g.minigame()
	_fc_reseed_t = 0.0
	_fc_mouse_saved = false
	_fc_look = Vector2.ZERO
	_fc_reseed()
	_fc_cam.current = true


## Start from wherever the game's camera is looking.
func _fc_reseed() -> void:
	var src: Camera3D = _fc_game_cam
	if src == null or not is_instance_valid(src) or not src.is_inside_tree():
		var me: Node3D = app.g.my_char()
		var at: Vector3 = me.global_position + Vector3(0, 2.0, 4.0) if me != null else Vector3(0, 3.0, 6.0)
		_fc_cam.global_position = at
		return
	_fc_cam.global_transform = src.global_transform
	_fc_cam.fov = src.fov
	_fc_cam.near = src.near
	_fc_cam.far = maxf(src.far, 500.0)
	_fc_cam.cull_mask = src.cull_mask
	_fc_cam.environment = src.environment
	_fc_cam.attributes = src.attributes
	var e: Vector3 = src.global_transform.basis.orthonormalized().get_euler()
	_fc_pitch = clampf(e.x, -1.55, 1.55)
	_fc_yaw = e.y


func _freecam_off() -> void:
	_fc_set_frozen(false)
	if _fc_cam == null:
		return
	if is_instance_valid(_fc_cam):
		_fc_cam.current = false
		_fc_cam.queue_free()
	_fc_cam = null
	if _fc_game_cam != null and is_instance_valid(_fc_game_cam) and _fc_game_cam.is_inside_tree():
		_fc_game_cam.current = true
	_fc_game_cam = null
	_fc_mg = null
	if _fc_mouse_saved and not _fc_busy():
		Input.mouse_mode = _fc_saved_mouse
	_fc_mouse_saved = false


## Freeze my character by telling the game it lost focus (every minigame player
## skips input then). Shares the saved value with the menu so neither one
## restores the other's "unfocused" state by mistake.
func _fc_set_frozen(on: bool) -> void:
	var gm: Node = app.g.al("GameManager")
	if gm == null or not ("game_focused" in gm):
		return
	var menu_holds: bool = app.ui.is_open and app.ui.get("_saved_game_focused") != null
	if on and not _fc_frozen:
		_fc_frozen = true
		_fc_saved_focus = app.ui.get("_saved_game_focused") if menu_holds else gm.get("game_focused")
	elif not on and _fc_frozen:
		_fc_frozen = false
		if _fc_saved_focus != null:
			if menu_holds:
				app.ui.set("_saved_game_focused", _fc_saved_focus)
			else:
				gm.set("game_focused", _fc_saved_focus)
		_fc_saved_focus = null
	if _fc_frozen and gm.get("game_focused") != false:
		gm.set("game_focused", false)


func _draw_freecam(c: Control) -> void:
	if not freecam_active() or app.ui.is_open:
		return
	var ov = app.mod("overlay")
	if ov == null:
		return
	var mode := "follow" if int(app.cfg.val("misc.freecam_mode", 0)) == 1 else "%.0f m/s" % float(app.cfg.val("misc.freecam_speed", 10.0))
	var key: String = app.hk.bind_name(app.hk.bind_of("freecam_toggle"))
	ov.hud_center(c, c.get_viewport_rect().size.y - ov._sz(40), [["FREECAM  %s  -  %s to exit" % [mode, key], Color("#3ddc84")]], 14)


# --- console ---------------------------------------------------------------------

func _console_visibility() -> void:
	var want := bool(app.cfg.val("misc.console", false))
	if want and _con_layer == null:
		_build_console()
	if _con_panel != null:
		if _con_panel.visible != want:
			_con_panel.visible = want
			if want:
				_con_input.grab_focus()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				_con_input.release_focus()


func _build_console() -> void:
	_con_layer = CanvasLayer.new()
	_con_layer.layer = 121
	_con_layer.name = "ViperConsole"
	add_child(_con_layer)
	_con_panel = PanelContainer.new()
	_con_panel.theme = app.ui.theme
	_con_panel.anchor_left = 0.0
	_con_panel.anchor_right = 1.0
	_con_panel.anchor_top = 1.0
	_con_panel.anchor_bottom = 1.0
	_con_panel.offset_left = 14
	_con_panel.offset_right = -14
	var vp_h: float = get_viewport().get_visible_rect().size.y
	_con_panel.offset_top = -clampf(vp_h * 0.42, 150.0, 330.0)
	_con_panel.offset_bottom = -8
	_con_layer.add_child(_con_panel)
	var v := VBoxContainer.new()
	_con_panel.add_child(v)
	_con_log = RichTextLabel.new()
	_con_log.bbcode_enabled = true
	_con_log.scroll_following = true
	_con_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_con_log.custom_minimum_size = Vector2(0, 80)
	_con_log.selection_enabled = true
	v.add_child(_con_log)
	_con_input = LineEdit.new()
	_con_input.placeholder_text = "command or GDScript expression - 'help' for commands"
	_con_input.text_submitted.connect(_on_submit)
	_con_input.gui_input.connect(_on_input_key)
	v.add_child(_con_input)
	for l in app.log_lines():
		_print(l, "#7fd8a6")
	_print("Viper console. Type 'help'. Anything else is evaluated as an expression (names: app, g, game, mg, me, cam, tree).", "#aaaaaa")


func _on_input_key(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed:
		return
	if ev.keycode == KEY_UP and not _history.is_empty():
		_hist_i = clampi(_hist_i - 1 if _hist_i >= 0 else _history.size() - 1, 0, _history.size() - 1)
		_con_input.text = _history[_hist_i]
		_con_input.caret_column = _con_input.text.length()
		_con_input.accept_event()
	elif ev.keycode == KEY_DOWN and not _history.is_empty():
		_hist_i = mini(_hist_i + 1, _history.size())
		_con_input.text = _history[_hist_i] if _hist_i < _history.size() else ""
		_con_input.accept_event()
	elif ev.keycode == KEY_ESCAPE:
		app.cfg.put("misc.console", false)
		_con_input.accept_event()


func _print(line: String, color: String = "#ffffff") -> void:
	if _con_log == null or not is_instance_valid(_con_log):
		return
	_con_log.append_text("[color=%s]%s[/color]\n" % [color, line.replace("[", "[lb]")])


func _on_submit(text: String) -> void:
	text = text.strip_edges()
	_con_input.text = ""
	_hist_i = -1
	if text.is_empty():
		return
	_history.append(text)
	_print("> " + text, "#ffffff")
	var parts := text.split(" ", false)
	var cmd := parts[0].to_lower()
	var args := parts.slice(1)
	match cmd:
		"help":
			_print("help, clear, mods, players, tp <x> <y> <z>, tpto <name>, bring <name>, pos, host, unload, panic")
			_print("freecam, shove <name>, freeze <name>, smite <name>, kick <name>, score <name> <points>, skip, skip game, restart, end, end now")
			_print("servers, join <room id>, roomid, public, private")
			_print("anything else is a GDScript expression, e.g.  me.global_position  or  mg.round_instructions")
		"clear":
			_con_log.clear()
		"mods":
			for m in app.loader.mod_list():
				_print(" - " + str(m))
		"players":
			for id in app.g.player_ids():
				_print(" %d  %s%s" % [id, app.g.player_name(id), "  (you)" if id == app.g.my_id() else ""])
		"pos":
			var me: Node3D = app.g.my_char()
			_print(str(me.global_position) if me else "no character")
		"tp":
			var me: Node3D = app.g.my_char()
			if me and args.size() >= 3:
				app.g.teleport(me, Vector3(float(args[0]), float(args[1]), float(args[2])))
			else:
				_print("usage: tp <x> <y> <z>  (needs a character)")
		"tpto", "bring":
			var id := _find_player(" ".join(args))
			if id < 0:
				_print("no player matching '%s'" % " ".join(args))
			elif cmd == "tpto":
				app.mod("players").tp_me_to(id)
			else:
				app.mod("players").tp_to_me(id)
		"host":
			_print("host" if app.g.is_host() else "client")
		"freecam":
			app.cfg.put("misc.freecam", not bool(app.cfg.val("misc.freecam", false)))
			_print("freecam " + ("on" if app.cfg.val("misc.freecam", false) else "off"))
		"kick":
			var id := _find_player(" ".join(args))
			if id < 0 or id == app.g.my_id():
				_print("no player matching '%s'" % " ".join(args))
			else:
				app.mod("players").kick(id)
		"servers":
			var br = app.mod("browser")
			br.refresh()
			await get_tree().create_timer(2.5).timeout
			for r in br.results():
				_print(" %d  %s  %d/%d%s" % [r["id"], r["name"], r["players"], r["max"], "" if r["compatible"] else "  (other version)"])
			_print(br._status)
		"join":
			app.mod("browser").join_by_code(" ".join(args))
		"roomid":
			app.mod("browser").copy_room_id()
		"public":
			app.mod("browser").publish()
		"private":
			app.mod("browser").unpublish()
		"shove", "freeze", "smite":
			var id := _find_player(" ".join(args))
			if id < 0:
				_print("no player matching '%s'" % " ".join(args))
			elif cmd == "shove":
				app.mod("players").shove(id)
			elif cmd == "freeze":
				app.mod("players").toggle_freeze(id)
			else:
				app.mod("players").smite(id)
		"score":
			if args.size() < 2 or not args[args.size() - 1].is_valid_int():
				_print("usage: score <name> <points>")
			else:
				var id := _find_player(" ".join(args.slice(0, args.size() - 1)))
				if id < 0:
					_print("no player matching that name")
				else:
					app.mod("session").set_score(id, int(args[args.size() - 1]))
		"skip":
			app.mod("session").skip(args.size() > 0 and args[0].to_lower() in ["game", "minigame", "all"])
		"restart":
			app.mod("session").restart()
		"end":
			app.mod("session").end_session(args.size() > 0 and args[0].to_lower() == "now")
		"unload":
			app.unload()
		"panic":
			app.panic()
		_:
			_eval(text)


func _find_player(q: String) -> int:
	q = q.to_lower()
	for id in app.g.player_ids():
		if app.g.player_name(id).to_lower().contains(q) or str(id) == q:
			return id
	return -1


func _eval(text: String) -> void:
	var e := Expression.new()
	var names := ["app", "g", "game", "mg", "me", "cam", "tree"]
	if e.parse(text, names) != OK:
		_print("parse error: " + e.get_error_text(), "#ff6666")
		return
	var res = e.execute([app, app.g, app.g.game(), app.g.minigame(), app.g.my_char(), app.g.camera(), get_tree()], self, false)
	if e.has_execute_failed():
		_print("error: " + e.get_error_text(), "#ff6666")
	else:
		_print(str(res), "#ffe08a")


# --- UI --------------------------------------------------------------------------

func build_ui(ui, page) -> void:
	ui.header(page, "Movement")
	ui.check(page, "Noclip (beta)", "misc.noclip",
		"Fly through walls: W forward, S back, A left, D right, Space up, Shift down. Turns your character's collision and physics off while on.")
	ui.slider(page, "Noclip speed", "misc.noclip_speed", 2.0, 60.0, 0.5, "", "%.1f m/s")
	ui.keybind(page, "noclip_toggle")

	ui.header(page, "Freecam")
	ui.check(page, "Freecam", "misc.freecam",
		"Detached camera. Mouse to look, W forward, S back, A left, D right, Space up, Shift down, mouse wheel changes speed (or distance in follow mode). Only your screen changes - nobody else sees it.")
	ui.option_dynamic(page, "Mode", "misc.freecam_mode", func() -> Array: return [[0, "Free fly"], [1, "Follow player"]])
	ui.option_dynamic(page, "Follow", "misc.freecam_target", _targets)
	ui.slider(page, "Fly speed", "misc.freecam_speed", 1.0, 80.0, 0.5, "", "%.1f m/s")
	ui.slider(page, "Mouse sensitivity", "misc.freecam_sens", 0.2, 3.0, 0.05, "", "%.2fx")
	ui.check(page, "Freeze my character while flying", "misc.freecam_freeze",
		"Your character ignores input while the freecam is on, so WASD only moves the camera.")
	ui.keybind(page, "freecam_toggle")

	ui.header(page, "Console")
	ui.check(page, "Enable console (beta)", "misc.console",
		"Shows the mod log and evaluates commands / GDScript expressions against the live game.")
	ui.keybind(page, "console_toggle")

	ui.header(page, "Teleport loose objects")
	ui.option_dynamic(page, "To player", "misc.loose_target", _targets)
	ui.buttons(page, [["Teleport loose objects", func() -> void:
		var t := int(app.cfg.val("misc.loose_target", -1))
		app.mod("players").tp_entities_to(t if t > 0 else app.g.my_id())]])
	ui.note(page, "Moves mines, gun parts, junk cubes, crates, containers, the roomba and other physics objects. Objects the host owns only stay moved when you're the host.")


func _targets() -> Array:
	var out: Array = [[-1, "Me"]]
	for id in app.g.player_ids():
		if id != app.g.my_id():
			out.append([id, app.g.player_name(id)])
	return out
