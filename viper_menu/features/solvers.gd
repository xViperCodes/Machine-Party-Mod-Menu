extends Node

## Per-minigame solvers. Each one reads the game's own state:
##  - Chisel Gauntlet: minigame.round_instructions = segments to KEEP.
##  - Tunnel Hazard: TrainRaceNook.state (0 open = safe hiding spot, 1 closed = press).
##  - Stable Footing: the final pattern broadcasts the safe symbol (shown on the
##    big displays); every tile with another symbol is armed and drops 3s later.
##  - Inside Job: no container holds the syringe - the host hands it to the
##    Nth search overall (guaranteed_search_result). As host the mod picks a
##    container and steers that number so the syringe comes out of it.
##  - Table Manners: the host runs the coach's timer; clients see his
##    "reading blend" animation parameter.
##  - The Filter: BurnRecyclePlayer.items[active_item_index] is the item under
##    the press; its burnable flag says which lever. Auto-solve calls the same
##    burn_rpc / recycle_rpc the buttons call.

var app = null

const SYMBOL_NAMES := ["All", "Cross", "Square", "Circle"]
const SYMBOL_COLORS := [Color("#4deeea"), Color("#ffe700"), Color("#f000ff")]
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
var _ij_mg: Node = null
var _ij_pick: Node = null          # the container the syringe will come out of (host)
var _ij_orig := -1                 # the game's own pick, restored when rigging is off
var _ij_rigged := false
var _ij_started: Dictionary = {}   # container instance id -> time its search started
var _ij_conts: Array = []
var _ij_scan_t := 0.0

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
	c.def("sol.ij.rig", true)
	c.def("sol.ij.hide_rest", false)
	c.def("sol.ij.fullbright", false)
	c.def("sol.ij.range", 40.0)
	c.def("sol.ij.energy", 2.0)
	c.def("sol.ij.ambient", true)
	c.def("sol.tm.hud", true)
	c.def("sol.smoke.hud", true)
	c.def("sol.smoke.auto", false)
	c.def("sol.smoke.at", 0.85)
	c.def("sol.tm.look_lasts", 2.0)
	c.def("sol.tm.nudge", 0.0)
	c.def("sol.tm.red_at", 0.75)
	c.def("sol.filter.on", false)
	c.def("sol.filter.hold", true)
	c.def("sol.filter.repeat", true)
	c.def("sol.filter.delay", 0.18)
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
	for k in ["sol.chisel.on", "sol.tunnel.on", "sol.stable.use_drops", "sol.stable.hide", "sol.ij.on", "sol.ij.rig",
			"sol.ij.fullbright", "sol.tm.hud", "sol.filter.on", "sol.smoke.auto"]:
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
			_ij_rig(delta)
		"GreenPeaMinigame":
			_tm_tick()
		"SmokeBreakMinigame":
			_smoke_tick()
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
	var done := int(app.g.gv(mg, "containers_searched", 0))
	var found := bool(app.g.gv(mg, "hunting_phase", false)) or bool(app.g.gv(mg, "projector_started", false))
	var pick: Node = ij_pick()
	return {"host": true, "done": done, "found": found, "pick": pick,
		"rigged": bool(app.cfg.val("sol.ij.rig", true)) and pick != null}


func ij_pick() -> Node:
	return _ij_pick if app.g.valid(_ij_pick) and not bool(app.g.gv(_ij_pick, "searched", false)) else null


func _ij_containers(mg: Node) -> Array:
	if _ij_scan_t <= 0.0 or _ij_conts.is_empty():
		_ij_conts = app.g.find_cls(mg, ["KnifeAtTheOfficeSearchable"])
		_ij_scan_t = 1.0
	var out: Array = []
	for c in _ij_conts:
		if app.g.valid(c):
			out.append(c)
	return out


func _ij_free(mg: Node) -> Array:
	var out: Array = []
	for c in _ij_containers(mg):
		if not bool(app.g.gv(c, "searched", false)) and not bool(app.g.gv(c, "in_use", false)):
			out.append(c)
	return out


## Host: put the syringe in a different container (random, or the one nearest me).
func ij_reroll(nearest: bool = false) -> void:
	var st := syringe_state()
	if st.is_empty():
		app.note("syringe: not in Inside Job")
		return
	if not st.get("host", false):
		app.note("syringe: host only")
		return
	var free := _ij_free(app.g.minigame())
	if free.is_empty():
		app.note("syringe: no unsearched containers left")
		return
	var me: Node3D = app.g.my_char()
	if nearest and me != null:
		var best: Node = null
		var bd := INF
		for c in free:
			var d: float = (c as Node3D).global_position.distance_to(me.global_position)
			if d < bd:
				bd = d
				best = c
		_ij_pick = best
		app.note("syringe moved to the container nearest you (%.0f m)" % bd)
	else:
		_ij_pick = free.pick_random()
		app.note("syringe moved to another container")


## Host only. The game gives the syringe to whoever completes search number
## guaranteed_search_result. Keep that number out of reach until someone is
## searching the picked container, then set it to land on exactly that search
## (counting searches that started before it and will finish first).
func _ij_rig(delta: float) -> void:
	_ij_scan_t -= delta
	var mg: Node = app.g.minigame()
	if mg != _ij_mg:
		_ij_mg = mg
		_ij_pick = null
		_ij_orig = -1
		_ij_rigged = false
		_ij_started.clear()
		_ij_conts.clear()
	if mg == null or not app.g.is_host() or not ("guaranteed_search_result" in mg):
		return
	var target := int(mg.get("guaranteed_search_result"))
	if target < 0:
		return
	if _ij_orig < 0:
		_ij_orig = target
	var done := int(app.g.gv(mg, "containers_searched", 0))
	if not bool(app.cfg.val("sol.ij.rig", true)):
		if _ij_rigged:
			_ij_rigged = false
			mg.set("guaranteed_search_result", maxi(_ij_orig, done + 1))
		return
	if bool(app.g.gv(mg, "hunting_phase", false)) or bool(app.g.gv(mg, "projector_started", false)):
		return
	var conts := _ij_containers(mg)
	if conts.is_empty():
		return
	var now := Time.get_ticks_msec()
	for c in conts:
		var id: int = c.get_instance_id()
		if bool(app.g.gv(c, "in_use", false)):
			if not _ij_started.has(id):
				_ij_started[id] = now
		else:
			_ij_started.erase(id)
	if ij_pick() == null:
		var free := _ij_free(mg)
		if free.is_empty():
			return
		_ij_pick = free.pick_random()
	var pick := _ij_pick
	var want := done + 100000
	if bool(app.g.gv(pick, "in_use", false)):
		var mine: int = _ij_started.get(pick.get_instance_id(), now)
		var ahead := 0
		for c in conts:
			if c != pick and bool(app.g.gv(c, "in_use", false)) and int(_ij_started.get(c.get_instance_id(), now)) < mine:
				ahead += 1
		want = done + 1 + ahead
	if target != want:
		mg.set("guaranteed_search_result", want)
	_ij_rigged = true


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
	var rows: Array = []
	if not st.get("host", false):
		rows.append(["Syringe: only the host can see it (the host's game decides who gets it)", Color(1, 1, 1, 0.7)])
	elif st.get("found", false):
		rows.append(["Syringe has been found", Color(1, 1, 1, 0.7)])
	elif not st.get("rigged", false):
		rows.append(["Syringe: turn on \"Put the syringe in one container\" to see where it is", Color(1, 1, 1, 0.7)])
	else:
		var pick: Node3D = st["pick"]
		var me: Node3D = app.g.my_char()
		var dist := "" if me == null else "  (%.0f m)" % pick.global_position.distance_to(me.global_position)
		rows.append(["Syringe is in the marked container" + dist, GOLD])
	app.mod("overlay").hud_center(c, 70.0, rows, 18)
	if not st.get("rigged", false) or st.get("found", false):
		return
	var p: Vector3 = (st["pick"] as Node3D).global_position + Vector3.UP * 0.6
	if cam.is_position_behind(p):
		return
	var sp := cam.unproject_position(p)
	c.draw_circle(sp, 10.0, GOLD)
	c.draw_arc(sp, 18.0, 0.0, TAU, 32, GOLD, 3.0)
	app.mod("overlay").text_center(c, sp + Vector2(0, -24), "SYRINGE", GOLD, 18)


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


# ==== Smoke Break ======================================================================
## Your drag fills while you hold the button; past 100% you choke (locked out
## for choke_timeout seconds). These numbers only exist on your own machine -
## other players' copies only see their smoke / cough particles.

func smoke_state() -> Dictionary:
	var me: Node = app.g.my_char()
	if me == null or app.g.cls(me) != "SmokeBreakPlayer":
		return {}
	return {
		"drag": float(app.g.gv(me, "drag_progress", 0.0)),
		"choke": float(app.g.gv(me, "choke_timer", 0.0)),
		"choke_max": float(app.g.gv(me, "choke_timeout", 3.0)),
		"left": float(app.g.gv(me, "cigarette_left", 1.0)),
		"inhaling": bool(app.g.gv(me, "inhaling", false)),
		"active": bool(app.g.gv(me, "active", false)) and not bool(app.g.gv(me, "finished", false)),
	}


## Auto-exhale: let go for you just before the drag would make you choke.
func _smoke_tick() -> void:
	if not bool(app.cfg.val("sol.smoke.auto", false)):
		return
	var me: Node = app.g.my_char()
	var st := smoke_state()
	if st.is_empty() or not st["active"] or not st["inhaling"]:
		return
	if st["drag"] >= float(app.cfg.val("sol.smoke.at", 0.85)):
		# Same state change the game makes when you release the button.
		me.set("inhaling", false)
		me.set("exhaling", true)
		var anim = me.get("anim_handler")
		if app.g.valid(anim) and anim.has_method("start_exhaling_cigarette"):
			app.g._rpc(anim, "start_exhaling_cigarette", [])


func _draw_smoke(c: Control) -> void:
	var st := smoke_state()
	if st.is_empty():
		return
	var ov = app.mod("overlay")
	var vp := c.get_viewport_rect().size
	var w := float(ov._sz(360))
	var h := float(ov._sz(22))
	var x := (vp.x - w) * 0.5
	var y := vp.y * 0.78
	var drag: float = clampf(st["drag"], 0.0, 1.0)
	var col := GREEN
	if drag > 0.85:
		col = RED
	elif drag > 0.6:
		col = GOLD
	var label := "DRAG %d%%" % int(round(st["drag"] * 100.0))
	if st["choke"] > 0.0:
		col = RED
		drag = st["choke"] / maxf(st["choke_max"], 0.01)
		label = "CHOKING  %.1fs" % st["choke"]
	c.draw_rect(Rect2(x - 4, y - 4, w + 8, h + 8), Color(0, 0, 0, 0.6))
	c.draw_rect(Rect2(x, y, w * drag, h), col)
	c.draw_rect(Rect2(x + w * 0.999, y - 2, 2, h + 4), Color(1, 1, 1, 0.8))
	ov.text_center(c, Vector2(vp.x * 0.5, y - float(ov._sz(10))), label, Color.WHITE, 18)
	var auto: String = "   |   auto-exhale at %d%%" % int(float(app.cfg.val("sol.smoke.at", 0.85)) * 100.0) if bool(app.cfg.val("sol.smoke.auto", false)) else ""
	ov.text_center(c, Vector2(vp.x * 0.5, y + h + float(ov._sz(22))), "cigarette left %d%%%s" % [int(st["left"] * 100.0), auto], Color(1, 1, 1, 0.75), 14)


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
	if "burnable" in n:
		return "burn" if bool(n.get("burnable")) else "recycle"
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
	var me: Node = app.g.my_char()
	if me != null and app.g.cls(me) == "BurnRecyclePlayer":
		return me
	return app.g.first_cls(app.g.minigame(), "BurnRecyclePlayer") if me == null else me


## The item sitting under my press: BurnRecyclePlayer.items[active_item_index].
## Returns [kind, item node or null, why-not text].
func current_item() -> Array:
	var me := _my_filter_player()
	if me == null:
		return ["", null, "no player found"]
	var items = me.get("items")
	if not (items is Dictionary):
		return ["", null, "this isn't The Filter's player"]
	var idx := int(app.g.gv(me, "active_item_index", 3))
	var it = items.get(idx, null)
	if not app.g.valid(it):
		return ["", null, "waiting for the next item"]
	var k := kind_of(it)
	return [k, it, "" if k != "" else "unknown item"]


func _filter_tick(delta: float) -> void:
	if not bool(app.cfg.val("sol.filter.on", false)) or app.ui.is_open:
		_f_status = "off"
		return
	if app.g.minigame_cls() != "BurnRecycleMinigame":
		_f_status = "not in The Filter"
		return
	var need_hold := bool(app.cfg.val("sol.filter.hold", true))
	var held: bool = app.hk.held("filter_solve")
	if need_hold and not held:
		_f_fired_this_hold = false
		_f_status = "waiting for %s" % app.hk.bind_name(app.hk.bind_of("filter_solve"))
		return
	if not bool(app.cfg.val("sol.filter.repeat", true)) and _f_fired_this_hold:
		return
	_f_t += delta
	if _f_t < float(app.cfg.val("sol.filter.delay", 0.18)):
		return
	var me := _my_filter_player()
	if me == null:
		_f_status = "no player found"
		return
	if not bool(app.g.gv(me, "active", false)):
		_f_status = "waiting for the round"
		return
	if bool(app.g.gv(me, "is_dead", false)):
		_f_status = "you're out"
		return
	if float(app.g.gv(me, "penalty_timer", 0.0)) > 0.0:
		_f_status = "penalty"
		return
	var r := current_item()
	if r[0] == "":
		_f_status = str(r[2])
		return
	_f_t = 0.0
	var burn: bool = r[0] == "burn"
	# Same call the game makes when you press the burn / recycle button.
	app.g._rpc(me, "burn_rpc" if burn else "recycle_rpc", [])
	_f_fired_this_hold = true
	_f_status = "sent %s" % ("BURN" if burn else "RECYCLE")


func _release_filter() -> void:
	pass


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
			if bool(app.g.gv(n, "searched", false)):
				return {"text": "searched", "color": Color(0.6, 0.6, 0.6), "flag": false}
			var st := syringe_state()
			if st.get("rigged", false) and not st.get("found", false) and st["pick"] == n:
				return {"text": "SYRINGE", "color": GOLD, "flag": true}
			return {"text": "", "color": null, "flag": false}
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
		"SmokeBreakMinigame":
			if bool(app.cfg.val("sol.smoke.hud", true)):
				_draw_smoke(c)
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
	ui.note(page, "The game doesn't hide the syringe in a container - the host hands it to whoever finishes the Nth search. As host, the mod picks one container and makes sure the syringe comes out of that one, so the ESP shows exactly where it is. Clients can't see it: their game never knows.")
	ui.check(page, "Put the syringe in one container (host only)", "sol.ij.rig")
	ui.check(page, "Highlight it", "sol.ij.on")
	ui.check(page, "Hide the rest", "sol.ij.hide_rest", "Turns off the normal container ESP so only the syringe highlight shows.")
	ui.buttons(page, [
		["Move it to the container nearest me", ij_reroll.bind(true)],
		["Move it somewhere random", ij_reroll.bind(false)],
	])
	ui.live(page, func() -> String:
		var st := syringe_state()
		if st.is_empty():
			return "Not in Inside Job."
		if not st.get("host", false):
			return "You're not the host - only the host's game decides who gets the syringe."
		if st.get("found", false):
			return "The syringe has been found."
		if not st.get("rigged", false):
			return "Off - the game's own random search number is in charge."
		var me: Node3D = app.g.my_char()
		var pick: Node3D = st["pick"]
		return "Syringe container picked%s - %d searched so far." % ["" if me == null else " (%.0f m from you)" % pick.global_position.distance_to(me.global_position), int(st["done"])], ui.MUTED)
	ui.check(page, "Fullbright", "sol.ij.fullbright", "Lights up the dark office and removes your fog of war.")
	ui.slider(page, "Light range", "sol.ij.range", 5.0, 120.0, 1.0, "", "%.0f m")
	ui.slider(page, "Light energy", "sol.ij.energy", 0.2, 8.0, 0.1)
	ui.check(page, "Brighten ambient light too", "sol.ij.ambient")

	ui.header(page, "Smoke Break")
	ui.check(page, "Drag / choke meter", "sol.smoke.hud", "A bar under your character: how full your drag is (you choke past 100%) and the choke countdown.")
	ui.check(page, "Auto-exhale before choking", "sol.smoke.auto", "Lets go of the drag for you when it reaches the level below. Hold the button to inhale as usual.")
	ui.slider(page, "Exhale at", "sol.smoke.at", 0.5, 0.98, 0.01, "", "%.2f")
	ui.note(page, "The drag and choke numbers only exist on your own game, so other players just show CHOKING / inhaling in the ESP.")

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
	ui.check(page, "Auto-solve", "sol.filter.on", "Reads the item under your press and pulls the right lever for you (the same call the game makes for your button).")
	ui.keybind(page, "filter_solve")
	ui.check(page, "Hold key to run", "sol.filter.hold", "Off: runs on its own for the whole round.")
	ui.check(page, "Repeat while held", "sol.filter.repeat", "Off: one item per key press.")
	ui.slider(page, "Delay between items", "sol.filter.delay", 0.05, 1.0, 0.01, "Lower is faster.", "%.2f s")
	ui.live(page, func() -> String:
		if app.g.minigame_cls() != "BurnRecycleMinigame":
			return "Not in The Filter."
		var r := current_item()
		var now: String = str(r[0]).to_upper() if r[0] != "" else str(r[2])
		return "Under the press: %s   |   %s" % [now, _f_status], ui.MUTED)
