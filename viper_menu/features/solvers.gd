extends Node

## Per-minigame solvers. Each one reads the game's own state:
##  - Chisel Gauntlet: minigame.round_instructions = segments to KEEP.
##  - Tunnel Hazard: TrainRaceNook.state (0 open = safe hiding spot, 1 closed = press).
##  - Stable Footing: the final pattern broadcasts the safe symbol (shown on the
##    big displays); every tile with another symbol is armed and drops 3s later.
##  - Inside Job: the host gives the syringe to the Nth search overall
##    (guaranteed_search_result), not to a particular container.
##  - Table Manners: the host runs the coach's timer; clients see his
##    "reading blend" animation parameter.
##  - The Filter: item types 0-3 burn, 4-7 recycle.

var app = null

const SYMBOL_NAMES := ["All", "Cross", "Square", "Circle"]
const SYMBOL_COLORS := [Color("#4deeea"), Color("#ffe700"), Color("#f000ff")]
const MEASURE := ["Item Spawn Marker", "Piston", "Player", "Camera"]
const GOLD := Color("#ffd23f")
const RED := Color("#ff3030")
const GREEN := Color("#40ff40")

# stable footing
var _sf_final := false
var _sf_final_t := 0.0
var _sf_safe := -1
var _sf_last_was := false
var _sf_deco_was := false
var _sf_hidden: Array = []

# chisel
var _glowing: Array = []

# inside job
var _light: OmniLight3D = null
var _fow_hidden: Array = []
var _env_saved: Dictionary = {}
var _ij_esp_saved = null

# table manners
var _tm_looking := false
var _tm_read_start := 0.0
var _tm_look_start := 0.0
var _tm_reads: Array = []
var _tm_looks: Array = []
var _tm_manual := false
var _tm_manual_t := 0.0
var _tm_auto := false
var _tm_mg: Node = null

# filter
var _f_t := 0.0
var _f_pressing := ""
var _f_press_t := 0.0
var _f_fired_this_hold := false
var _f_status := "idle"


func setup() -> void:
	process_priority = -100   # simulated inputs must land before the game reads them
	var c = app.cfg
	c.def("sol.chisel.on", true)
	c.def("sol.chisel.glow", true)
	c.def("sol.tunnel.on", true)
	c.def("sol.tunnel.invert", false)
	c.def("sol.stable.use_drops", true)
	c.def("sol.stable.hide", false)
	c.def("sol.stable.symbol", "All")
	c.def("sol.stable.dim", true)
	c.def("sol.ij.on", true)
	c.def("sol.ij.hide_rest", false)
	c.def("sol.ij.fullbright", false)
	c.def("sol.ij.range", 40.0)
	c.def("sol.ij.energy", 2.0)
	c.def("sol.ij.ambient", true)
	c.def("sol.tm.hud", true)
	c.def("sol.tm.look_lasts", 2.0)
	c.def("sol.tm.nudge", 0.0)
	c.def("sol.tm.red_at", 0.75)
	c.def("sol.filter.on", false)
	c.def("sol.filter.hold", true)
	c.def("sol.filter.repeat", true)
	c.def("sol.filter.swap", false)
	c.def("sol.filter.delay", 0.18)
	c.def("sol.filter.measure", "Player")
	c.def("sol.filter.radius", 3.0)
	c.def("sol.filter.burn_action", "action_1")
	c.def("sol.filter.recycle_action", "action_2")
	app.hk.register("filter_solve", "The Filter: auto-solve (hold)", app.hk.kb(KEY_G), "Solvers")
	app.hk.register("tm_up", "Table Manners: he looked up", app.hk.kb(KEY_L), "Solvers")
	app.hk.register("tm_away", "Table Manners: he looked away", app.hk.kb(KEY_K), "Solvers")
	app.hk.register("stable_cycle", "Stable Footing: cycle fallback symbol", app.hk.kb(KEY_V), "Solvers")
	app.hk.pressed.connect(_on_hotkey)
	app.hk.released.connect(func(id: String) -> void:
		if id == "filter_solve":
			_f_fired_this_hold = false
	)
	c.changed.connect(_on_cfg_changed)
	app.add_drawer(_draw)


func disable_all() -> void:
	for k in ["sol.chisel.on", "sol.tunnel.on", "sol.stable.use_drops", "sol.stable.hide", "sol.ij.on",
			"sol.ij.fullbright", "sol.tm.hud", "sol.filter.on"]:
		app.cfg.put(k, false)
	app.cfg.put("sol.stable.symbol", "All")
	_cleanup()


func shutdown() -> void:
	_cleanup()


func _cleanup() -> void:
	_unglow()
	_unhide_tiles()
	_remove_fullbright()
	_release_filter()


func _on_cfg_changed(key: String, v) -> void:
	if key == "sol.ij.hide_rest":
		var k := "esp.g.KnifeAtTheOfficeSearchable.draw"
		if bool(v):
			_ij_esp_saved = app.cfg.val(k, true)
			app.cfg.put(k, false)
		elif _ij_esp_saved != null:
			app.cfg.put(k, _ij_esp_saved)
			_ij_esp_saved = null


func _on_hotkey(id: String) -> void:
	match id:
		"stable_cycle":
			var cur := SYMBOL_NAMES.find(str(app.cfg.val("sol.stable.symbol", "All")))
			var nxt: String = SYMBOL_NAMES[(cur + 1) % SYMBOL_NAMES.size()]
			app.cfg.put("sol.stable.symbol", nxt)
			app.note("Stable Footing symbol: " + nxt)
		"tm_up":
			_tm_manual = true
			_tm_manual_t = _now()
			_tm_set_looking(true)
		"tm_away":
			_tm_manual = false
			_tm_set_looking(false)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# --- per frame -------------------------------------------------------------------

func _process(delta: float) -> void:
	var mgc: String = app.g.minigame_cls()
	if mgc != "DiscoDodgeMinigame":
		_unhide_tiles()
		_sf_final = false
	if mgc != "ChiselGauntletMinigame":
		_unglow()
	if mgc != "KnifeAtTheOfficeMinigame":
		_remove_fullbright()
	if mgc != "BurnRecycleMinigame":
		_release_filter()
	match mgc:
		"DiscoDodgeMinigame":
			_stable_tick()
		"ChiselGauntletMinigame":
			_chisel_tick()
		"KnifeAtTheOfficeMinigame":
			_ij_tick()
		"GreenPeaMinigame":
			_tm_tick()
		"BurnRecycleMinigame":
			_filter_tick(delta)


# ==== Chisel Gauntlet ===============================================================

func chisel_instructions() -> Array:
	var r = app.g.gv(app.g.minigame(), "round_instructions", [])
	return r if r is Array else []


func chisel_is_carve(seg) -> bool:
	if not app.g.valid(seg) or not bool(app.g.gv(seg, "active", false)):
		return false
	var idx := int(app.g.gv(seg, "index", -1))
	var instr := chisel_instructions()
	return idx >= 0 and not instr.is_empty() and not instr.has(idx)


func my_segments() -> Array:
	var me: Node = app.g.my_char()
	var segs = app.g.gv(me, "interaction_handler.cube_segments", [])
	var out: Array = []
	if segs is Array:
		for s in segs:
			if app.g.valid(s) and app.g.cls(s) == "ChiselGauntletCubeSegment":
				out.append(s)
	return out


func _chisel_tick() -> void:
	if not bool(app.cfg.val("sol.chisel.on", true)) or not bool(app.cfg.val("sol.chisel.glow", true)):
		_unglow()
		return
	var now_glow: Array = []
	for s in my_segments():
		var m = app.g.gv(s, "actual_mesh", null)
		if not (m is GeometryInstance3D):
			continue
		if chisel_is_carve(s):
			m.set_instance_shader_parameter("strength", 0.45)
			now_glow.append(m)
	for m in _glowing:
		if is_instance_valid(m) and not now_glow.has(m):
			m.set_instance_shader_parameter("strength", 0.0)
	_glowing = now_glow


func _unglow() -> void:
	for m in _glowing:
		if is_instance_valid(m):
			m.set_instance_shader_parameter("strength", 0.0)
	_glowing.clear()


# ==== Stable Footing ================================================================

func _display_symbol(mg: Node) -> int:
	var arr = app.g.gv(mg, "display1_symbols", [])
	if arr is Array:
		for i in arr.size():
			if app.g.valid(arr[i]) and arr[i].visible:
				return i
	return -1


func _stable_tick() -> void:
	var mg: Node = app.g.minigame()
	var last = app.g.gv(mg, "speaker_show_symbol_last", null)
	var deco = app.g.gv(mg, "speaker_show_symbol", null)
	var lp: bool = app.g.valid(last) and last.playing
	var dp: bool = app.g.valid(deco) and deco.playing
	if lp and not _sf_last_was:
		_sf_final = true
		_sf_final_t = _now()
		_sf_safe = _display_symbol(mg)
	if dp and not _sf_deco_was:
		_sf_final = false
	_sf_last_was = lp
	_sf_deco_was = dp
	if _sf_final and _now() - _sf_final_t > 9.0:
		_sf_final = false
	if _sf_final and _sf_safe < 0:
		_sf_safe = _display_symbol(mg)

	var hide: bool = _sf_final and bool(app.cfg.val("sol.stable.use_drops", true)) and bool(app.cfg.val("sol.stable.hide", false))
	if not hide:
		_unhide_tiles()
		return
	for t in tiles():
		if tile_drops(t) and t.visible:
			t.visible = false
			_sf_hidden.append(t)


func _unhide_tiles() -> void:
	for t in _sf_hidden:
		if is_instance_valid(t):
			t.visible = true
	_sf_hidden.clear()


func tiles() -> Array:
	var arr = app.g.gv(app.g.minigame(), "tile_nodes", [])
	if arr is Array and not arr.is_empty():
		return arr
	return app.g.find_cls(app.g.minigame(), ["DiscoDodgeTile"])


## True if this tile is going to fall in the current pattern.
func tile_drops(t) -> bool:
	if not app.g.valid(t):
		return false
	if bool(app.g.gv(t, "is_tile_removed_from_play", false)):
		return false
	if bool(app.g.gv(t, "armed", false)):
		return true
	if not _sf_final or _sf_safe < 0 or not bool(app.cfg.val("sol.stable.use_drops", true)):
		return false
	return int(app.g.gv(t, "symbol_index", -1)) != _sf_safe


func _draw_stable(c: Control, cam: Camera3D) -> void:
	var mg: Node = app.g.minigame()
	var ts := float(app.g.gv(mg, "tile_size", 4.0))
	var use_drops := bool(app.cfg.val("sol.stable.use_drops", true))
	var sym := SYMBOL_NAMES.find(str(app.cfg.val("sol.stable.symbol", "All"))) - 1
	var dim := bool(app.cfg.val("sol.stable.dim", true))
	var final_mode := _sf_final and use_drops and _sf_safe >= 0
	if not final_mode and sym < 0:
		return
	for t in tiles():
		if not app.g.valid(t) or not t.is_visible_in_tree():
			continue
		if bool(app.g.gv(t, "is_tile_removed_from_play", false)):
			continue
		var col: Color
		if final_mode:
			col = Color(RED, 0.38) if tile_drops(t) else Color(GREEN, 0.30)
		else:
			var si := int(app.g.gv(t, "symbol_index", -1))
			if si == sym:
				col = Color(SYMBOL_COLORS[sym], 0.38)
			elif dim:
				col = Color(0, 0, 0, 0.55)
			else:
				continue
		_fill_tile(c, cam, t.global_position, ts * 0.48, col)
	if final_mode:
		var vp := c.get_viewport_rect().size
		var nm: String = SYMBOL_NAMES[_sf_safe + 1] if _sf_safe + 1 < SYMBOL_NAMES.size() else "?"
		app.mod("overlay").hud_center(c, 70.0, [["SAFE SYMBOL: " + nm.to_upper(), GREEN]], 20)


func _fill_tile(c: Control, cam: Camera3D, p: Vector3, half: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for o in [Vector3(-half, 0.15, -half), Vector3(half, 0.15, -half), Vector3(half, 0.15, half), Vector3(-half, 0.15, half)]:
		var w: Vector3 = p + o
		if cam.is_position_behind(w):
			return
		pts.append(cam.unproject_position(w))
	c.draw_colored_polygon(pts, col)


# ==== Tunnel Hazard ===================================================================

func _draw_tunnel(c: Control, cam: Camera3D) -> void:
	var invert := bool(app.cfg.val("sol.tunnel.invert", false))
	var esp = app.mod("esp")
	for n in app.g.find_cls(app.g.minigame(), ["TrainRaceNook"]):
		var safe := int(app.g.gv(n, "state", 0)) == 0
		if invert:
			safe = not safe
		var col := GREEN if safe else RED
		if esp != null:
			esp._draw_box(c, cam, n, 0.0, col)
		var p: Vector3 = n.global_position + Vector3.UP * 1.0
		if cam.is_position_behind(p):
			continue
		var sp := cam.unproject_position(p)
		c.draw_circle(sp, 9.0, col)
		app.mod("overlay").text_center(c, sp + Vector2(0, -14), "SAFE" if safe else "PRESS", col, 16)


# ==== Inside Job ======================================================================

func syringe_state() -> Dictionary:
	var mg: Node = app.g.minigame()
	if mg == null or app.g.minigame_cls() != "KnifeAtTheOfficeMinigame":
		return {}
	if not app.g.is_host():
		return {"host": false}
	var target := int(app.g.gv(mg, "guaranteed_search_result", -1))
	var done := int(app.g.gv(mg, "containers_searched", 0))
	var found := bool(app.g.gv(mg, "hunting_phase", false)) or bool(app.g.gv(mg, "projector_started", false))
	return {"host": true, "target": target, "done": done, "left": target - done, "found": found}


func nudge_syringe(d: int) -> void:
	var st := syringe_state()
	if not st.get("host", false):
		app.note("syringe: host only")
		return
	var mg: Node = app.g.minigame()
	var nv := maxi(int(st["done"]) + 1, int(st["target"]) + d)
	mg.set("guaranteed_search_result", nv)
	app.note("syringe now on search #%d" % nv)


func syringe_to_next() -> void:
	var st := syringe_state()
	if not st.get("host", false):
		app.note("syringe: host only")
		return
	app.g.minigame().set("guaranteed_search_result", int(st["done"]) + 1)
	app.note("the next search (anyone's) gets the syringe - be first")


func _ij_tick() -> void:
	if bool(app.cfg.val("sol.ij.fullbright", false)):
		_apply_fullbright()
	else:
		_remove_fullbright()


func _apply_fullbright() -> void:
	var cam: Camera3D = app.g.camera()
	if cam != null:
		if _light == null or not is_instance_valid(_light):
			_light = OmniLight3D.new()
			_light.name = "ViperFullbright"
			_light.shadow_enabled = false
			_light.omni_attenuation = 0.5
		if _light.get_parent() != cam:
			if _light.get_parent() != null:
				_light.get_parent().remove_child(_light)
			cam.add_child(_light)
		_light.omni_range = float(app.cfg.val("sol.ij.range", 40.0))
		_light.light_energy = float(app.cfg.val("sol.ij.energy", 2.0))
	var me: Node = app.g.my_char()
	if me != null:
		var fow: Node = app.g.first_cls(me, "KnifeAtTheOfficeFogOfWar")
		var mesh = app.g.gv(fow, "mesh", null)
		if mesh is Node3D and mesh.visible:
			mesh.visible = false
			_fow_hidden.append(mesh)
	if bool(app.cfg.val("sol.ij.ambient", true)):
		var env = app.g.gv(app.g.minigame(), "light_handler.world_environment.environment", null)
		if env is Environment:
			if not _env_saved.has("env"):
				_env_saved = {"env": env, "color": env.ambient_light_color, "energy": env.ambient_light_energy}
			env.ambient_light_color = Color(0.85, 0.85, 0.85)
			env.ambient_light_energy = maxf(1.0, float(app.cfg.val("sol.ij.energy", 2.0)) * 0.5)


func _remove_fullbright() -> void:
	if _light != null and is_instance_valid(_light):
		_light.queue_free()
	_light = null
	for m in _fow_hidden:
		if is_instance_valid(m):
			m.visible = true
	_fow_hidden.clear()
	if _env_saved.has("env") and is_instance_valid(_env_saved["env"]):
		_env_saved["env"].ambient_light_color = _env_saved["color"]
		_env_saved["env"].ambient_light_energy = _env_saved["energy"]
	_env_saved = {}


func _draw_ij(c: Control, cam: Camera3D) -> void:
	var st := syringe_state()
	if st.is_empty():
		return
	var vp := c.get_viewport_rect().size
	var rows: Array = []
	if not st.get("host", false):
		rows.append(["Syringe: host only (the host decides who gets it)", Color(1, 1, 1, 0.7)])
	elif st.get("found", false):
		rows.append(["Syringe has been found", Color(1, 1, 1, 0.7)])
	else:
		var left := int(st["left"])
		rows.append(["Syringe: search #%d   (%d done)" % [int(st["target"]), int(st["done"])], Color.WHITE])
		if left <= 1:
			rows.append(["NEXT SEARCH GETS IT", GOLD])
		else:
			rows.append(["%d searches to go" % left, Color.WHITE])
	app.mod("overlay").hud_center(c, 70.0, rows, 18)
	if not st.get("host", false) or st.get("found", false) or int(st.get("left", 99)) > 1:
		return
	for n in app.g.find_cls(app.g.minigame(), ["KnifeAtTheOfficeSearchable"]):
		if bool(app.g.gv(n, "searched", false)) or bool(app.g.gv(n, "in_use", false)):
			continue
		var p: Vector3 = n.global_position + Vector3.UP * 0.6
		if cam.is_position_behind(p):
			continue
		var sp := cam.unproject_position(p)
		c.draw_circle(sp, 8.0, GOLD)
		app.mod("overlay").text_center(c, sp + Vector2(0, -12), "SYRINGE", GOLD, 14)


# ==== Table Manners ===================================================================

func _coach() -> Node:
	return app.g.first_cls(app.g.minigame(), "GreenPeaCoach")


func _coach_handler() -> Node:
	return app.g.first_cls(app.g.minigame(), "GreenPeaCoachHandler")


func _tm_set_looking(v: bool) -> void:
	if v == _tm_looking:
		return
	var now := _now()
	if v:
		if _tm_read_start > 0.0:
			_tm_reads.append(now - _tm_read_start)
		_tm_look_start = now
	else:
		if _tm_look_start > 0.0:
			_tm_looks.append(now - _tm_look_start)
		_tm_read_start = now
	_tm_looking = v
	if _tm_reads.size() > 20:
		_tm_reads.pop_front()
	if _tm_looks.size() > 20:
		_tm_looks.pop_front()


func _tm_tick() -> void:
	var mg: Node = app.g.minigame()
	if mg != _tm_mg:
		_tm_mg = mg
		_tm_reads.clear()
		_tm_looks.clear()
		_tm_looking = false
		_tm_read_start = _now()
		_tm_manual = false
	var coach := _coach()
	var tree = app.g.gv(coach, "anim_tree_coach", null)
	_tm_auto = false
	if tree is AnimationTree:
		var blend = tree.get("parameters/reading blend/blend_amount")
		if blend != null:
			_tm_auto = true
			var executing: bool = not tree.active
			_tm_set_looking(executing or float(blend) > 0.5)
	if not _tm_auto and _tm_manual:
		if _now() - _tm_manual_t > float(app.cfg.val("sol.tm.look_lasts", 2.0)):
			_tm_manual = false
			_tm_set_looking(false)


## {looking, safe_left (sec until he may look, -1 unknown), exact}
func coach_prediction() -> Dictionary:
	var h := _coach_handler()
	var nudge := float(app.cfg.val("sol.tm.nudge", 0.0))
	if app.g.is_host() and h != null and app.g.valid(h.get("timer")):
		var reading := bool(h.get("reading"))
		var executing := bool(h.get("executing"))
		if executing or not reading:
			return {"looking": true, "safe_left": 0.0, "exact": true}
		var tl: float = h.get("timer").time_left
		return {"looking": false, "safe_left": tl + nudge, "exact": true}
	if _tm_looking:
		return {"looking": true, "safe_left": 0.0, "exact": false}
	var min_read := float(app.g.gv(h, "min_read_time", 3.0))
	if _tm_reads.size() >= 3:
		var m: float = _tm_reads.min()
		min_read = minf(min_read, m)
	return {"looking": false, "safe_left": (min_read + nudge) - (_now() - _tm_read_start), "exact": false}


func _draw_tm(c: Control) -> void:
	if not bool(app.cfg.val("sol.tm.hud", true)):
		return
	var p := coach_prediction()
	var vp := c.get_viewport_rect().size
	var red_at := float(app.cfg.val("sol.tm.red_at", 0.75))
	var rows: Array = []
	if p["looking"]:
		rows.append(["COACH IS LOOKING - DON'T EAT", RED])
	else:
		var sl := float(p["safe_left"])
		var col := RED if sl <= red_at else GREEN
		var how := "exact" if p["exact"] else ("learned" if _tm_reads.size() >= 3 else "earliest")
		rows.append(["Coach reading - safe for %.1fs (%s)" % [maxf(sl, 0.0), how], col])
		if p["exact"]:
			rows.append(["20% of checks are fake-outs", Color(1, 1, 1, 0.6)])
	if not _tm_auto:
		rows.append(["Manual mode: %s = looked up, %s = looked away" % [
			app.hk.bind_name(app.hk.bind_of("tm_up")), app.hk.bind_name(app.hk.bind_of("tm_away"))], Color(1, 1, 1, 0.6)])
	app.mod("overlay").hud_center(c, 70.0, rows, 18)


# ==== The Filter ========================================================================

## "burn", "recycle" or "" for an item node / item type value.
func kind_of_value(v) -> String:
	if v is int or v is float:
		var i := int(v)
		if i >= 0 and i <= 3:
			return "burn"
		if i >= 4 and i <= 7:
			return "recycle"
	if v is String or v is StringName:
		var s := str(v).to_lower()
		if s.begins_with("burn"):
			return "burn"
		if s.begins_with("recycle"):
			return "recycle"
	return ""


func kind_of(n) -> String:
	if not app.g.valid(n):
		return ""
	for p in ["type", "item_type", "_type", "current_type", "launch_type", "kind"]:
		if p in n:
			var k := kind_of_value(n.get(p))
			if k != "":
				return k
	var s = n.get_script()
	if s != null:
		for prop in s.get_script_property_list():
			var pn := str(prop.get("name", ""))
			if pn.to_lower().contains("type") and int(prop.get("type", 0)) == TYPE_INT:
				var k2 := kind_of_value(n.get(pn))
				if k2 != "":
					return k2
	return ""


func _my_filter_player() -> Node:
	return app.g.my_char()


## Best guess for the item in front of me. Returns [kind, how].
func current_item() -> Array:
	var me := _my_filter_player()
	if me == null:
		return ["", "no player found"]
	# 1) a queue-like array on the player whose first entry is an item type
	var s = me.get_script()
	if s != null:
		for prop in s.get_script_property_list():
			var pn := str(prop.get("name", ""))
			var low := pn.to_lower()
			if not (low.contains("queue") or low.contains("item")):
				continue
			var v = me.get(pn)
			if v is Array and not v.is_empty():
				var front = v[0]
				var k := kind_of(front) if front is Object else kind_of_value(front)
				if k != "":
					return [k, "player.%s[0]" % pn]
	# 2) nearest typed item to the reference point
	var ref := _ref_point(me)
	var radius := float(app.cfg.val("sol.filter.radius", 3.0))
	var best := ""
	var best_d := INF
	for n in app.g.descendants(app.g.minigame()):
		if not (n is Node3D) or n == me:
			continue
		var k := kind_of(n)
		if k == "":
			continue
		if not n.is_visible_in_tree():
			continue
		var d: float = n.global_position.distance_to(ref)
		if d <= radius and d < best_d:
			best_d = d
			best = k
	if best != "":
		return [best, "nearest item (%.1fm)" % best_d]
	return ["", "no item within %.1fm of %s" % [radius, str(app.cfg.val("sol.filter.measure", "Player"))]]


func _ref_point(me: Node3D) -> Vector3:
	match str(app.cfg.val("sol.filter.measure", "Player")):
		"Camera":
			var cam: Camera3D = app.g.camera()
			if cam != null:
				return cam.global_position
		"Piston":
			var presses = app.g.gv(app.g.minigame(), "presses", [])
			var best: Vector3 = me.global_position
			var bd := INF
			if presses is Array:
				for p in presses:
					if app.g.valid(p):
						var d: float = p.global_position.distance_to(me.global_position)
						if d < bd:
							bd = d
							best = p.global_position
			return best
		"Item Spawn Marker":
			for n in app.g.descendants(me):
				if n is Node3D and (str(n.name).to_lower().contains("spawn") or str(n.name).to_lower().contains("marker")):
					return n.global_position
	return me.global_position


func _filter_tick(delta: float) -> void:
	if _f_pressing != "":
		_f_press_t += delta
		if _f_press_t >= 0.06:
			_release_filter()
	if not bool(app.cfg.val("sol.filter.on", false)) or app.ui.is_open:
		_f_status = "off"
		return
	var need_hold := bool(app.cfg.val("sol.filter.hold", true))
	var held: bool = app.hk.held("filter_solve")
	if need_hold and not held:
		_f_status = "waiting for %s" % app.hk.bind_name(app.hk.bind_of("filter_solve"))
		return
	if not bool(app.cfg.val("sol.filter.repeat", true)) and _f_fired_this_hold:
		return
	_f_t += delta
	if _f_t < float(app.cfg.val("sol.filter.delay", 0.18)) or _f_pressing != "":
		return
	_f_t = 0.0
	var r := current_item()
	_f_status = "%s via %s" % [r[0].to_upper() if r[0] != "" else "nothing", r[1]]
	if r[0] == "":
		return
	var burn: bool = r[0] == "burn"
	if bool(app.cfg.val("sol.filter.swap", false)):
		burn = not burn
	var action := str(app.cfg.val("sol.filter.burn_action" if burn else "sol.filter.recycle_action", "action_1"))
	if InputMap.has_action(action):
		Input.action_press(action)
		_f_pressing = action
		_f_press_t = 0.0
		_f_fired_this_hold = true


func _release_filter() -> void:
	if _f_pressing != "" and InputMap.has_action(_f_pressing):
		Input.action_release(_f_pressing)
	_f_pressing = ""


# ==== ESP tokens =========================================================================

func esp_token(tok: String, n: Node) -> Dictionary:
	match tok:
		"@carve":
			var cv := chisel_is_carve(n)
			return {"text": "CARVE" if cv else "keep", "color": Color("#ff8040") if cv else null, "flag": cv}
		"@burn":
			var k := kind_of(n)
			if k == "burn":
				return {"text": "BURN", "color": Color("#ff6a2a"), "flag": true}
			if k == "recycle":
				return {"text": "RECYCLE", "color": Color("#40ff90"), "flag": false}
			return {"text": "?", "color": null, "flag": false}
		"@coach":
			var p := coach_prediction()
			return {"text": "LOOKING" if p["looking"] else "reading", "color": RED if p["looking"] else GREEN, "flag": p["looking"]}
		"@syringe":
			var st := syringe_state()
			if bool(app.g.gv(n, "searched", false)):
				return {"text": "searched", "color": Color(0.6, 0.6, 0.6), "flag": false}
			if not st.get("host", false):
				return {"text": "", "color": null, "flag": false}
			if st.get("found", false):
				return {"text": "", "color": null, "flag": false}
			if int(st["left"]) <= 1:
				return {"text": "SYRINGE - next search", "color": GOLD, "flag": true}
			return {"text": "%d to go" % int(st["left"]), "color": null, "flag": false}
	return {"text": "?", "color": null, "flag": false}


# ==== drawing ==============================================================================

func _draw(c: Control) -> void:
	var cam: Camera3D = app.g.camera()
	if cam == null:
		return
	match app.g.minigame_cls():
		"DiscoDodgeMinigame":
			_draw_stable(c, cam)
		"TrainRaceMinigame":
			if bool(app.cfg.val("sol.tunnel.on", true)):
				_draw_tunnel(c, cam)
		"KnifeAtTheOfficeMinigame":
			if bool(app.cfg.val("sol.ij.on", true)):
				_draw_ij(c, cam)
		"GreenPeaMinigame":
			_draw_tm(c)
		"ChiselGauntletMinigame":
			if bool(app.cfg.val("sol.chisel.on", true)):
				_draw_chisel(c, cam)


func _draw_chisel(c: Control, cam: Camera3D) -> void:
	var count := 0
	for s in my_segments():
		if not chisel_is_carve(s):
			continue
		count += 1
		var p: Vector3 = s.global_position
		if cam.is_position_behind(p):
			continue
		var sp := cam.unproject_position(p)
		c.draw_circle(sp, 7.0, Color("#ff8040"))
		c.draw_arc(sp, 10.0, 0.0, TAU, 24, Color.BLACK, 2.0, true)
	if not chisel_instructions().is_empty():
		var vp := c.get_viewport_rect().size
		app.mod("overlay").hud_center(c, 70.0, [["Carve %d more segment%s" % [count, "" if count == 1 else "s"], Color("#ff8040") if count > 0 else GREEN]], 18)


# ==== UI ===================================================================================

func build_ui(ui, page) -> void:
	ui.header(page, "Chisel Gauntlet")
	ui.check(page, "Show only the segments to carve", "sol.chisel.on",
		"Marks the segments that aren't in the shape you have to keep.")
	ui.check(page, "Glow the segments to carve", "sol.chisel.glow", "Uses the game's own hover highlight on your cube.")

	ui.header(page, "Tunnel Hazard")
	ui.check(page, "Color the nooks (green safe, red press)", "sol.tunnel.on")
	ui.check(page, "Invert", "sol.tunnel.invert", "Swap the colors if they ever look backwards.")

	ui.header(page, "Stable Footing")
	ui.check(page, "Use the round's dropping tiles", "sol.stable.use_drops",
		"When the final symbol is shown, marks exactly which tiles fall (every tile without the safe symbol).")
	ui.check(page, "Hide dropping tiles", "sol.stable.hide", "Only the safe tiles stay on screen during the final pattern.")
	ui.option(page, "Fallback symbol", "sol.stable.symbol", SYMBOL_NAMES,
		"Highlights tiles with this symbol during the decoy flashes.")
	ui.check(page, "Dim others", "sol.stable.dim")
	ui.keybind(page, "stable_cycle")

	ui.header(page, "Inside Job")
	ui.note(page, "The syringe isn't hidden in one container: the host hands it to whoever completes the Nth search overall. As host you see N and how many searches are left; when the next search is the winner every unsearched container lights up.")
	ui.check(page, "Highlight the syringe (host only)", "sol.ij.on")
	ui.check(page, "Hide the rest", "sol.ij.hide_rest", "Turns off the normal container ESP so only the syringe highlight shows.")
	ui.buttons(page, [
		["Index nudge -1", nudge_syringe.bind(-1), "Moves the syringe one search earlier."],
		["Index nudge +1", nudge_syringe.bind(1), "Moves it one search later."],
		["Give it to the next search", syringe_to_next, "Whoever finishes the next search gets it - make sure it's you."],
	])
	ui.live(page, func() -> String:
		var st := syringe_state()
		if st.is_empty():
			return "Not in Inside Job."
		if not st.get("host", false):
			return "You're not the host - only the host knows the number."
		return "Search #%d gets it - %d done, %d to go." % [int(st["target"]), int(st["done"]), int(st["left"])], ui.MUTED)
	ui.check(page, "Fullbright", "sol.ij.fullbright", "Lights up the dark office and removes your fog of war.")
	ui.slider(page, "Light range", "sol.ij.range", 5.0, 120.0, 1.0, "", "%.0f m")
	ui.slider(page, "Light energy", "sol.ij.energy", 0.2, 8.0, 0.1)
	ui.check(page, "Brighten ambient light too", "sol.ij.ambient")

	ui.header(page, "Table Manners")
	ui.check(page, "Coach countdown HUD", "sol.tm.hud",
		"Host: reads the coach's real timer. Client: watches his animation and his read-time range. Turns red before he can look.")
	ui.slider(page, "Look lasts", "sol.tm.look_lasts", 0.5, 6.0, 0.1, "Manual mode: how long a look-up lasts if you don't press 'looked away'.", "%.1f s")
	ui.slider(page, "Nudge", "sol.tm.nudge", -2.0, 2.0, 0.05, "Shifts the prediction earlier (-) or later (+).", "%.2f s")
	ui.slider(page, "Turn red at", "sol.tm.red_at", 0.0, 3.0, 0.05, "Seconds of safety left when the HUD turns red.", "%.2f s")
	ui.keybind(page, "tm_up")
	ui.keybind(page, "tm_away")
	ui.live(page, func() -> String:
		if _tm_reads.is_empty():
			return "Learned: nothing yet."
		var mx: float = _tm_reads.max()
		var mn: float = _tm_reads.min()
		return "Learned from %d looks: reads last %.1f-%.1fs." % [_tm_reads.size(), mn, mx], ui.MUTED)

	ui.header(page, "The Filter")
	ui.note(page, "The Filter's player script wasn't in the files you sent, so this finds the item in front of you by reading item types (0-3 burn, 4-7 recycle). The status line shows what it found - send me BurnRecyclePlayer to make it exact.", ui.WARN)
	ui.check(page, "Auto-solve", "sol.filter.on", "Sends burn or recycle for every item on the belt.")
	ui.keybind(page, "filter_solve")
	ui.check(page, "Hold key to run", "sol.filter.hold")
	ui.check(page, "Repeat while held", "sol.filter.repeat")
	ui.check(page, "Swap buttons", "sol.filter.swap", "Use if it burns what should be recycled.")
	ui.slider(page, "Input delay", "sol.filter.delay", 0.05, 1.0, 0.01, "Time between inputs.", "%.2f s")
	ui.option(page, "Measure from", "sol.filter.measure", MEASURE)
	ui.slider(page, "Search radius", "sol.filter.radius", 0.5, 15.0, 0.25, "", "%.2f m")
	ui.text_input(page, "Burn input action", "sol.filter.burn_action", "action_1")
	ui.text_input(page, "Recycle input action", "sol.filter.recycle_action", "action_2")
	ui.live(page, func() -> String: return "Status: " + _f_status, ui.MUTED)
