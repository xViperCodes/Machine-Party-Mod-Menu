extends Node

## ESP. Every scripted 3D object in the current minigame is discovered
## automatically and grouped by script class, so new minigames show up without
## an update. Each group has its own draw settings. Curated presets switch on
## the useful groups for each known minigame and pick a live value to show.

var app = null
var font: Font

## Minigame script class -> preset. "toggle" ids are the switches in the UI.
const PRESETS := {
	"ExplodingCollarRace": {"toggle": "minefield", "groups": {
		"ExplodingCollarRaceMine": {"label": "Mine", "color": "#ff4040", "dot": 5.0, "showval": true, "val": "pinging"},
		"ExplodingCollarRaceHarvester": {"label": "Harvester", "color": "#ff9a30", "box": true, "showval": true, "val": "@speed"},
	}},
	"KnifeAtTheOfficeMinigame": {"toggle": "insidejob", "groups": {
		"KnifeAtTheOfficeSearchable": {"label": "Container", "color": "#40c8ff", "box": true, "showval": true, "val": "@syringe", "when": "searched", "when_v": "False"},
		"KnifeAtTheOfficePlayer": {"label": "Player", "color": "#ffffff", "showval": true, "val": "is_infected"},
	}},
	"ManufactureGun": {"toggle": "firearm", "groups": {
		"ManufactureGunItem": {"label": "Part", "color": "#ffd23f", "dot": 4.0, "showval": true, "val": "@variation"},
		"ManufactureGunWorkstation": {"label": "Workstation", "color": "#40ff90", "box": true, "showval": true, "val": "current_item_sequence_index"},
	}},
	"DiscoDodgeMinigame": {"toggle": "stable", "groups": {
		"DiscoDodgeTile": {"label": "Tile", "color": "#b070ff", "dot": 3.0, "name": false, "dist": false, "showval": true, "val": "@symbol", "max": 120.0},
	}},
	"TrainRaceMinigame": {"toggle": "tunnel", "groups": {
		"TrainRaceNook": {"label": "Nook", "color": "#40ff40", "box": true, "showval": true, "val": "@nook"},
	}},
	"JunkPlatformMinigame": {"toggle": "debris", "groups": {
		"JunkPlatformPlatform": {"label": "Platform", "color": "#ffcc00", "box": true, "showval": true, "val": "@timeleft"},
		"JunkPlatformCompactor": {"label": "Compactor", "color": "#ff4040", "box": true},
		"JunkCubeRigidbody": {"label": "Cube", "color": "#c8c8c8", "dot": 3.0, "name": false, "showval": true, "val": "thrown"},
	}},
	"SpineBreakerMinigame": {"toggle": "spine", "groups": {
		"SpineBreakerDevice": {"label": "Device", "color": "#ff40a0", "box": true, "showval": true, "val": "@device", "line": "Bottom"},
	}},
	"DvdRoombaMinigame": {"toggle": "rebound", "groups": {
		"DvdRoombaRoomba": {"label": "Roomba", "color": "#ff3030", "box": true, "showval": true, "val": "@speed", "line": "Bottom"},
		"DvdRoombaDoor": {"label": "Door", "color": "#40c8ff", "box": true},
		"hatch": {"label": "Hatch", "color": "#40ffd0", "box": true},
	}},
	"ForkliftCertifiedMinigame": {"toggle": "forklift", "groups": {
		"ForkliftCertifiedCrate": {"label": "Crate", "color": "#ffb040", "box": true, "when": "@delivered", "when_v": "False"},
		"ForkilftCertifiedDeliveryArea": {"label": "Delivery", "color": "#40ff40", "showval": true, "val": "@delivery"},
		"ForkliftCertifiedVehicle": {"label": "Forklift", "color": "#40c8ff", "box": true},
	}},
	"BurnRecycleMinigame": {"toggle": "filter", "groups": {
		"BurnRecycleLaunchedItem": {"label": "Item", "color": "#ffffff", "dot": 4.0, "showval": true, "val": "@burn"},
	}},
	"ChiselGauntletMinigame": {"toggle": "chisel", "groups": {
		"ChiselGauntletCubeSegment": {"label": "Segment", "color": "#ff8040", "dot": 5.0, "name": false, "dist": false, "showval": true, "val": "@carve", "when": "@carve", "when_v": "True"},
	}},
	"GreenPeaMinigame": {"toggle": "table", "groups": {
		"GreenPeaCoach": {"label": "Coach", "color": "#ff4040", "box": true, "showval": true, "val": "@coach"},
		"GreenPeaPlayer": {"label": "Player", "color": "#40ff90", "showval": true, "val": "is_dead"},
	}},
	"EscalatorPitMinigame": {"toggle": "wrongway_smoke", "groups": {
		"EscalatorPitPlayer": {"label": "Player", "color": "#40c8ff", "box": true, "showval": true, "val": "total_speed"},
	}},
	"SmokeBreakMinigame": {"toggle": "wrongway_smoke", "groups": {
		"SmokeBreakPlayer": {"label": "Player", "color": "#d0d0d0", "box": true, "showval": true, "val": "@choke"},
	}},
}

const TOGGLES := [
	["minefield", "Minefield - mines and the harvester"],
	["insidejob", "Inside Job - the containers (the solver marks the syringe)"],
	["firearm", "Firearm Factory - gun parts with their variation, and the workstations"],
	["stable", "Stable Footing - the tiles"],
	["tunnel", "Tunnel Hazard - the nooks"],
	["debris", "Debris Platforms - platforms with their time left, the compactor and the cubes"],
	["spine", "Spine Breaker - the device"],
	["rebound", "Lethal Rebound - the roomba with its speed, the doors and hatches"],
	["forklift", "Forklift Certified - crates not yet delivered, the delivery area and the forklifts"],
	["filter", "The Filter - every item with whether it burns or recycles"],
	["chisel", "Chisel Gauntlet - the segments to carve"],
	["table", "Table Manners - the coach and players"],
	["wrongway_smoke", "Wrong Way and Smoke Break - the players with their speed / choke timer"],
]

## Script classes that are plumbing, not things worth drawing.
const IGNORE := [
	"PlayerNameLabel", "SpeakerController3D", "SpeakerController", "ShakerComponent3D",
	"CustomizationAssigner", "CustomizationAssignerLegs", "CharacterBlink", "BlinkerBranchObj",
	"BlinkerBranchObj_", "TickBlink", "Searchable_Visuals", "Searchable_Visuals_Drawer",
	"KnifeAtTheOfficeSearchableSpeaker", "KnifeAtTheOfficeFogOfWar", "ExplodingCollarRaceBloodTrail",
	"ManagedEffect", "ManagedDecal", "RigidbodyProp", "FlickerLight", "WallLight", "LocationIndicator",
	"DvdRoombaSparks", "ProjectorVisuals", "Script",
]

const LINE_MODES := ["None", "Top", "Center", "Bottom"]
const WHEN_VALUES := ["True", "False"]
const SYMBOLS := ["Cross", "Square", "Circle"]
const VARIATIONS := ["None", "One", "Two", "Three", "Four", "Five"]

## Tokens computed from game state (see _token). Shown in the Value / Only When lists.
const TOKENS := {
	"ExplodingCollarRaceHarvester": ["@speed"],
	"KnifeAtTheOfficeSearchable": ["@syringe"],
	"ManufactureGunItem": ["@variation"],
	"DiscoDodgeTile": ["@symbol", "@drops"],
	"TrainRaceNook": ["@nook"],
	"JunkPlatformPlatform": ["@timeleft"],
	"SpineBreakerDevice": ["@device"],
	"DvdRoombaRoomba": ["@speed"],
	"ForkilftCertifiedDeliveryArea": ["@delivery"],
	"ForkliftCertifiedCrate": ["@delivered"],
	"BurnRecycleLaunchedItem": ["@burn"],
	"ChiselGauntletCubeSegment": ["@carve"],
	"GreenPeaCoach": ["@coach"],
	"SmokeBreakPlayer": ["@choke"],
}

var groups: Dictionary = {}       # cls -> Array[Node] (live)
var group_order: Array = []
var _scan_t := 0.0
var _mg_cls := ""
var _aabb_cache: Dictionary = {}  # instance_id -> AABB (local)
var _objects_box: VBoxContainer = null
var _ui = null
var _ui_sig := ""
var _registered: Dictionary = {}


func setup() -> void:
	font = ThemeDB.fallback_font
	app.cfg.def("esp.on", false)
	app.cfg.def("esp.other", true)
	app.cfg.def("esp.ignore_self", true)
	app.cfg.def("esp.text_size", 13)
	for t in TOGGLES:
		app.cfg.def("esp.p." + t[0], true)
	app.hk.register("esp_toggle", "Toggle ESP", app.hk.kb(KEY_PAGEDOWN), "ESP")
	app.hk.pressed.connect(func(id: String) -> void:
		if id == "esp_toggle":
			app.cfg.put("esp.on", not bool(app.cfg.val("esp.on", false)))
			app.note("ESP " + ("on" if app.cfg.val("esp.on", false) else "off"))
	)
	app.add_drawer(_draw)


func disable_all() -> void:
	app.cfg.put("esp.on", false)


# --- group settings ---------------------------------------------------------------

func _gk(c: String, field: String) -> String:
	return "esp.g.%s.%s" % [c, field]


func _ensure_group(c: String) -> void:
	if _registered.has(c):
		return
	_registered[c] = true
	var p: Dictionary = _preset_group(c)
	var curated := not p.is_empty()
	app.cfg.def(_gk(c, "draw"), curated)
	app.cfg.def(_gk(c, "name"), bool(p.get("name", true)))
	app.cfg.def(_gk(c, "dist"), bool(p.get("dist", true)))
	app.cfg.def(_gk(c, "box"), bool(p.get("box", false)))
	app.cfg.def(_gk(c, "line"), str(p.get("line", "None")))
	app.cfg.def(_gk(c, "max"), float(p.get("max", 250.0)))
	app.cfg.def(_gk(c, "dot"), float(p.get("dot", 4.0)))
	app.cfg.def(_gk(c, "boxh"), float(p.get("boxh", 0.0)))
	app.cfg.def(_gk(c, "color"), Color.html(str(p.get("color", "#ffffff"))))
	app.cfg.def(_gk(c, "showval"), bool(p.get("showval", false)))
	app.cfg.def(_gk(c, "val"), str(p.get("val", "")))
	app.cfg.def(_gk(c, "when"), str(p.get("when", "")))
	app.cfg.def(_gk(c, "when_v"), str(p.get("when_v", "True")))


func _preset_group(c: String) -> Dictionary:
	for mg in PRESETS.keys():
		var gs: Dictionary = PRESETS[mg]["groups"]
		if gs.has(c):
			return gs[c]
	return {}


func _label_of(c: String) -> String:
	var p := _preset_group(c)
	return str(p.get("label", c))


## Is drawing allowed for the current minigame (its preset switch, or "other")?
func _minigame_enabled() -> bool:
	if PRESETS.has(_mg_cls):
		return bool(app.cfg.val("esp.p." + str(PRESETS[_mg_cls]["toggle"]), true))
	return bool(app.cfg.val("esp.other", true))


# --- discovery -----------------------------------------------------------------------

func _process(delta: float) -> void:
	var mg: Node = app.g.minigame()
	var c: String = app.g.cls(mg)
	if c != _mg_cls:
		_mg_cls = c
		groups.clear()
		group_order.clear()
		_aabb_cache.clear()
		_speed_track.clear()
		_scan_t = 99.0
	_scan_t += delta
	if _scan_t >= 0.6:
		_scan_t = 0.0
		_scan(mg)
	if _objects_box != null and app.ui.is_open and app.ui.current_tab == "ESP":
		var sig := _mg_cls + "|" + ",".join(group_order)
		if sig != _ui_sig:
			_ui_sig = sig
			_rebuild_objects_ui()


func _scan(root: Node) -> void:
	var found: Dictionary = {}
	if root != null:
		for n in app.g.descendants(root):
			if not (n is Node3D):
				continue
			if n.get_script() == null:
				continue
			var c: String = app.g.cls(n)
			if c == "" or IGNORE.has(c) or c == _mg_cls:
				continue
			if not found.has(c):
				found[c] = []
			found[c].append(n)
	groups = found
	var keys: Array = found.keys()
	keys.sort_custom(func(a, b) -> bool:
		var pa := not _preset_group(a).is_empty()
		var pb := not _preset_group(b).is_empty()
		if pa != pb:
			return pa
		return str(a) < str(b))
	group_order = keys
	for k in keys:
		_ensure_group(k)


# --- values ------------------------------------------------------------------------------

## Returns {"text": String, "color": Color or null, "flag": bool}
func _token(tok: String, n: Node) -> Dictionary:
	var G = app.g
	var sv = app.mod("solvers")
	match tok:
		"@nook":
			var st := int(G.gv(n, "state", 0))
			var safe := st == 0
			if sv != null and bool(app.cfg.val("sol.tunnel.invert", false)):
				safe = not safe
			return {"text": "SAFE" if safe else "PRESS", "color": Color("#40ff40") if safe else Color("#ff3030"), "flag": safe}
		"@symbol":
			var si := int(G.gv(n, "symbol_index", -1))
			return {"text": SYMBOLS[si] if si >= 0 and si < 3 else "?", "color": null, "flag": si >= 0}
		"@drops":
			var d: bool = sv != null and sv.tile_drops(n)
			return {"text": "DROPS" if d else "safe", "color": Color("#ff3030") if d else Color("#40ff40"), "flag": d}
		"@variation":
			var v := int(G.gv(n, "variation", 0))
			return {"text": VARIATIONS[v] if v >= 0 and v < VARIATIONS.size() else str(v), "color": null, "flag": v != 0}
		"@timeleft":
			# The collapse timer and junk count only run on the host; clients
			# get the lit damage circles and the blinking alarm.
			var timer = G.gv(n, "timer", null)
			if G.is_host():
				var junk := int(G.gv(n, "junk_on_platform", 0))
				var after := int(G.gv(n, "collapse_after", 5))
				if G.valid(timer) and not timer.is_stopped():
					return {"text": "COLLAPSE %.1fs" % timer.time_left, "color": Color("#ff3030"), "flag": true}
				return {"text": "%d/%d junk" % [junk, after + 1], "color": Color("#ff9a30") if junk >= after else null, "flag": junk >= after}
			var lit := 0
			var arr = G.gv(n, "lit_array", [])
			if arr is Array:
				for b in arr:
					if b:
						lit += 1
				if lit == arr.size():
					lit = 0
			var danger := bool(G.gv(n, "blinking", false))
			return {"text": ("DANGER  load %d" % lit) if danger else ("load %d" % lit), "color": Color("#ff3030") if danger else null, "flag": danger}
		"@speed":
			# Clients only receive positions, so velocity reads 0 there;
			# fall back to speed measured from movement between frames.
			var sp := 0.0
			if n is CharacterBody3D:
				sp = n.velocity.length()
			if sp < 0.01:
				sp = _measured_speed(n)
			return {"text": "%.1f m/s" % sp, "color": null, "flag": sp > 0.1}
		"@delivered":
			var inside := bool(G.gv(n, "in_delivery_area", false))
			if not inside and n is PhysicsBody3D:
				for a in G.find_cls(app.g.minigame(), ["ForkilftCertifiedDeliveryArea"]):
					if a is Area3D and a.monitoring and a.overlaps_body(n):
						inside = true
						break
			return {"text": "delivered" if inside else "not delivered", "color": null, "flag": inside}
		"@device":
			var st_name := str(G.gv(n, "state_machine.current_state.name", "?"))
			var tgt = G.gv(n, "target", null)
			var tname := ""
			if G.valid(tgt):
				tname = " -> " + G.player_name(int(G.gv(tgt, "player_presence.network_id", -1)))
			return {"text": st_name + tname, "color": null, "flag": bool(G.gv(n, "active", false))}
		"@delivery":
			var cnt := int(G.gv(n, "crates_in_area.size", 0))
			if not G.is_host():
				var lbl = G.gv(n, "counter_label", null)
				if G.valid(lbl) and str(lbl.text).is_valid_int():
					cnt = int(lbl.text)
			var owner_id := int(G.gv(n, "belongs_to_id", -2))
			var who: String = G.player_name(owner_id) if owner_id > 0 else "nobody"
			return {"text": "%d crates (%s)" % [cnt, who], "color": null, "flag": cnt > 0}
		"@choke":
			if n == G.my_char():
				var ct := float(G.gv(n, "choke_timer", 0.0))
				var drag := float(G.gv(n, "drag_progress", 0.0))
				if ct > 0.0:
					return {"text": "CHOKING %.1fs" % ct, "color": Color("#ff3030"), "flag": true}
				return {"text": "drag %d%%" % int(round(drag * 100.0)), "color": Color("#ffd23f") if drag > 0.6 else null, "flag": drag > 0.85}
			# Other players: only their particles and cigarette glow are synced.
			if float(G.gv(n, "choke_emitter.amount_ratio", 0.0)) > 0.01:
				return {"text": "CHOKING", "color": Color("#ff3030"), "flag": true}
			if float(G.gv(n, "cigarette_light.light_energy", 0.0)) > 0.05:
				return {"text": "inhaling", "color": Color("#ffd23f"), "flag": false}
			if float(G.gv(n, "smoke_emitter.amount_ratio", 0.0)) > 0.5:
				return {"text": "exhaling", "color": null, "flag": false}
			return {"text": "", "color": null, "flag": false}
		"@carve", "@burn", "@coach", "@syringe":
			if sv != null and sv.has_method("esp_token"):
				return sv.esp_token(tok, n)
			return {"text": "?", "color": null, "flag": false}
	return {"text": "?", "color": null, "flag": false}


var _speed_track: Dictionary = {}   # instance id -> [pos, time, smoothed speed]


func _measured_speed(n: Node3D) -> float:
	var id := n.get_instance_id()
	var now := Time.get_ticks_msec() / 1000.0
	var p := n.global_position
	if not _speed_track.has(id):
		_speed_track[id] = [p, now, 0.0]
		return 0.0
	var e: Array = _speed_track[id]
	var dt: float = now - float(e[1])
	if dt < 0.05:
		return float(e[2])
	var inst: float = p.distance_to(e[0]) / dt
	var sm: float = lerpf(float(e[2]), inst, 0.5)
	_speed_track[id] = [p, now, sm]
	return sm


func value_of(path: String, n: Node) -> Dictionary:
	if path.begins_with("@"):
		return _token(path, n)
	var v = app.g.gv(n, path, null)
	return {"text": app.g.fmt_value(v), "color": null, "flag": bool(v) if (v is bool or v is int or v is float) else v != null}


# --- drawing -----------------------------------------------------------------------------

func _draw(c: Control) -> void:
	if not bool(app.cfg.val("esp.on", false)):
		return
	if not _minigame_enabled():
		return
	var cam: Camera3D = app.g.camera()
	if cam == null:
		return
	var vp_size := c.get_viewport_rect().size
	var ts := int(app.cfg.val("esp.text_size", 13))
	var ignore_self := bool(app.cfg.val("esp.ignore_self", true))
	var me: Node = app.g.my_char() if ignore_self else null
	var cam_pos := cam.global_position
	for cl in group_order:
		if not bool(app.cfg.val(_gk(cl, "draw"), false)):
			continue
		var nodes: Array = groups.get(cl, [])
		var col: Color = app.cfg.val(_gk(cl, "color"), Color.WHITE)
		var max_d := float(app.cfg.val(_gk(cl, "max"), 250.0))
		var show_name := bool(app.cfg.val(_gk(cl, "name"), true))
		var show_dist := bool(app.cfg.val(_gk(cl, "dist"), true))
		var show_box := bool(app.cfg.val(_gk(cl, "box"), false))
		var line_mode := str(app.cfg.val(_gk(cl, "line"), "None"))
		var dot := float(app.cfg.val(_gk(cl, "dot"), 4.0))
		var boxh := float(app.cfg.val(_gk(cl, "boxh"), 0.0))
		var showval := bool(app.cfg.val(_gk(cl, "showval"), false))
		var val_path := str(app.cfg.val(_gk(cl, "val"), ""))
		var when := str(app.cfg.val(_gk(cl, "when"), ""))
		var when_true := str(app.cfg.val(_gk(cl, "when_v"), "True")) == "True"
		var label := _label_of(cl)
		for n in nodes:
			if not is_instance_valid(n) or not n.is_inside_tree():
				continue
			if me != null and (n == me or me.is_ancestor_of(n)):
				continue
			if not n.is_visible_in_tree() and cl != "ChiselGauntletCubeSegment":
				continue
			var pos: Vector3 = n.global_position
			var dist := cam_pos.distance_to(pos)
			if dist > max_d:
				continue
			if when != "":
				if value_of(when, n)["flag"] != when_true:
					continue
			var draw_col := col
			var val_text := ""
			if showval and val_path != "":
				var vr := value_of(val_path, n)
				val_text = str(vr["text"])
				if vr["color"] != null:
					draw_col = vr["color"]
			var behind := cam.is_position_behind(pos)
			var sp := cam.unproject_position(pos)
			if line_mode != "None" and not behind:
				var from := Vector2(vp_size.x * 0.5, 0.0)
				if line_mode == "Center":
					from.y = vp_size.y * 0.5
				elif line_mode == "Bottom":
					from.y = vp_size.y
				c.draw_line(from, sp, Color(draw_col, 0.7), 1.5, true)
			if behind:
				continue
			if show_box:
				_draw_box(c, cam, n, boxh, draw_col)
			if dot > 0.0:
				c.draw_circle(sp, dot, draw_col)
			var y := sp.y + maxf(dot, 3.0) + ts
			var title := ""
			if show_name:
				title = label
				var pres = app.g.gv(n, "player_presence", null)
				if app.g.valid(pres):
					title = app.g.player_name(int(app.g.gv(pres, "network_id", -1)))
			if show_dist:
				title += ("  " if title != "" else "") + "[%dm]" % int(dist)
			if title != "":
				app.mod("overlay").text_center(c, Vector2(sp.x, y), title, draw_col, ts)
				y += ts + 2
			if val_text != "":
				app.mod("overlay").text_center(c, Vector2(sp.x, y), val_text, draw_col, ts)


func _draw_box(c: Control, cam: Camera3D, n: Node3D, boxh: float, col: Color) -> void:
	var box: AABB
	if boxh > 0.0:
		var w := boxh * 0.6
		box = AABB(Vector3(-w * 0.5, 0.0, -w * 0.5), Vector3(w, boxh, w))
	else:
		box = _local_aabb(n)
	var xf: Transform3D = n.global_transform
	var pts: Array = []
	for i in 8:
		var corner := box.get_endpoint(i)
		var wp: Vector3 = xf * corner
		if cam.is_position_behind(wp):
			return
		pts.append(cam.unproject_position(wp))
	# AABB endpoint order: bit0 = x, bit1 = y, bit2 = z
	var edges := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
	for e in edges:
		c.draw_line(pts[e[0]], pts[e[1]], col, 1.5, true)


func _local_aabb(n: Node3D) -> AABB:
	var id := n.get_instance_id()
	if _aabb_cache.has(id):
		return _aabb_cache[id]
	var inv := n.global_transform.affine_inverse()
	var merged := AABB()
	var have := false
	for d in app.g.descendants(n, true):
		if not (d is MeshInstance3D) or d.mesh == null:
			continue
		var b: AABB = (inv * d.global_transform) * d.get_aabb()
		if not have:
			merged = b
			have = true
		else:
			merged = merged.merge(b)
	if not have or merged.size.length() < 0.05:
		merged = AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1, 1, 1))
	if merged.size.length() > 60.0:
		merged = AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
	_aabb_cache[id] = merged
	return merged


# --- UI ------------------------------------------------------------------------------------

func build_ui(ui, page) -> void:
	_ui = ui
	ui.header(page, "ESP")
	ui.check(page, "Enable ESP", "esp.on")
	ui.live(page, func() -> String: return "Toggle hotkey: " + app.hk.bind_name(app.hk.bind_of("esp_toggle")), ui.MUTED)
	ui.slider(page, "Text size", "esp.text_size", 9, 24, 1)
	ui.check(page, "Ignore my own character", "esp.ignore_self")

	ui.header(page, "Minigames")
	for t in TOGGLES:
		ui.check(page, t[1], "esp.p." + t[0])
	ui.check(page, "Other minigames (no preset)", "esp.other",
		"Draw groups you've switched on below in minigames that have no preset.")

	ui.header(page, "Objects in current minigame")
	ui.live(page, func() -> String:
		if _mg_cls == "":
			return "Not in a minigame. Objects are listed automatically once one loads."
		var total := 0
		for k in groups.keys():
			total += groups[k].size()
		return "%s - %d object types, %d objects. Expand one to change how it's drawn." % [_mg_cls, groups.size(), total], ui.MUTED)
	_objects_box = VBoxContainer.new()
	_objects_box.add_theme_constant_override("separation", 2)
	page.add_child(_objects_box)
	_rebuild_objects_ui()


func _rebuild_objects_ui() -> void:
	if _objects_box == null or not is_instance_valid(_objects_box) or _ui == null:
		return
	var ui = _ui
	ui.clear(_objects_box)
	for cl in group_order:
		var nodes: Array = groups.get(cl, [])
		var lbl: String = _label_of(cl)
		var title := "%s  (%d)" % [lbl, nodes.size()] if lbl == cl else "%s - %s  (%d)" % [lbl, cl, nodes.size()]
		var s = ui.section(_objects_box, title, false)
		ui.check(s, "Draw", _gk(cl, "draw"))
		ui.check(s, "Name", _gk(cl, "name"))
		ui.check(s, "Distance", _gk(cl, "dist"))
		ui.check(s, "Box (3D)", _gk(cl, "box"))
		ui.option(s, "2D line", _gk(cl, "line"), LINE_MODES)
		ui.slider(s, "Max distance", _gk(cl, "max"), 5.0, 500.0, 5.0, "", "%.0f m")
		ui.slider(s, "Dot size", _gk(cl, "dot"), 0.0, 12.0, 0.5)
		ui.slider(s, "Box height (0 = fit model)", _gk(cl, "boxh"), 0.0, 10.0, 0.1)
		ui.color(s, "Color", _gk(cl, "color"))
		ui.check(s, "Show value", _gk(cl, "showval"), "Prints a live value next to the name.")
		ui.option_dynamic(s, "Value", _gk(cl, "val"), _value_items.bind(cl))
		ui.option_dynamic(s, "Only when", _gk(cl, "when"), _when_items.bind(cl),
			"Only draw objects where this is true (or false, below).")
		ui.option(s, "Only when value is", _gk(cl, "when_v"), WHEN_VALUES)


func _sample(cl: String) -> Node:
	for n in groups.get(cl, []):
		if is_instance_valid(n):
			return n
	return null


func _props(cl: String, bools_only: bool) -> Array:
	var out: Array = []
	var n := _sample(cl)
	if n == null:
		return out
	var s = n.get_script()
	if s == null:
		return out
	var ok_types := [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR3, TYPE_VECTOR2, TYPE_ARRAY, TYPE_DICTIONARY]
	for p in s.get_script_property_list():
		if not (int(p.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var t := int(p.get("type", 0))
		if bools_only and t != TYPE_BOOL:
			continue
		if not ok_types.has(t):
			continue
		var pn := str(p.get("name", ""))
		if pn != "" and not out.has(pn):
			out.append(pn)
	out.sort()
	return out


func _value_items(cl: String) -> Array:
	var items: Array = [["", "(none)"]]
	for t in TOKENS.get(cl, []):
		items.append([t, t + "  (computed)"])
	var cur := str(app.cfg.val(_gk(cl, "val"), ""))
	var props := _props(cl, false)
	if cur != "" and not cur.begins_with("@") and not props.has(cur):
		items.append([cur, cur])
	for p in props:
		items.append([p, p])
	items.append(["visible", "visible"])
	return items


func _when_items(cl: String) -> Array:
	var items: Array = [["", "(always)"]]
	for t in TOKENS.get(cl, []):
		items.append([t, t + "  (computed)"])
	var cur := str(app.cfg.val(_gk(cl, "when"), ""))
	var props := _props(cl, true)
	if cur != "" and not cur.begins_with("@") and not props.has(cur):
		items.append([cur, cur])
	for p in props:
		items.append([p, p])
	return items
