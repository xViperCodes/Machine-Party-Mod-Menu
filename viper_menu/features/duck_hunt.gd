extends Node

## Duck Hunt extras: magazine HUD, teleport to the finish marker, godmode,
## infinite ammo, rapidfire, speed hack.

var app = null

var _hud_hunter: Node = null
var _shots := 0
var _cap := 7
var _reload_until := 0.0
var _reload_was_playing := false
var _connected_hunter: Node = null

var _god_duck: Node = null
var _god_orig_max := 2
var _ammo_hunter: Node = null
var _speed_duck: Node = null
var _speed_orig := 4.0

const RELOAD_TIME := 2.85   # reload(): 3.8 - 0.95 seconds


func setup() -> void:
	var c = app.cfg
	c.def("duck.mag_hud", true)
	c.def("duck.god", false)
	c.def("duck.ammo", false)
	c.def("duck.rapid", false)
	c.def("duck.speed_on", false)
	c.def("duck.speed", 1.6)
	app.hk.register("duck_marker", "Teleport to the Duck Hunt marker", app.hk.kb(KEY_J), "Duck Hunt")
	app.hk.pressed.connect(func(id: String) -> void:
		if id == "duck_marker":
			tp_to_marker()
	)
	app.add_drawer(_draw)


func disable_all() -> void:
	for k in ["duck.god", "duck.ammo", "duck.rapid", "duck.speed_on"]:
		app.cfg.put(k, false)
	_restore_all()


func shutdown() -> void:
	_restore_all()


func _restore_all() -> void:
	_restore_god()
	_restore_ammo()
	_restore_speed()


func _restore_god() -> void:
	if app.g.valid(_god_duck):
		_god_duck.set("max_health", _god_orig_max)
		_god_duck.set("health", mini(int(_god_duck.get("health")), _god_orig_max))
	_god_duck = null


func _restore_ammo() -> void:
	if app.g.valid(_ammo_hunter):
		var caps = _ammo_hunter.get("magazine_capacity_by_duck_count")
		var cap := 7
		if caps is Dictionary:
			cap = int(caps.get(int(_ammo_hunter.get("duck_count")), 7))
		_ammo_hunter.set("magazine_capacity", cap)
		_ammo_hunter.set("num_of_current_rounds_in_magazine", mini(int(_ammo_hunter.get("num_of_current_rounds_in_magazine")), cap))
	_ammo_hunter = null


func _restore_speed() -> void:
	if app.g.valid(_speed_duck):
		_speed_duck.set("speed", _speed_orig)
	_speed_duck = null


# --- lookups -------------------------------------------------------------------------

func in_duck_hunt() -> bool:
	return app.g.minigame_cls() == "DuckHuntMinigame"


func hunter() -> Node:
	if not in_duck_hunt():
		return null
	return app.g.first_cls(app.g.minigame(), "DuckHuntHunterPlayer")


func my_duck() -> Node:
	var me: Node = app.g.my_char()
	return me if app.g.cls(me) == "DuckHuntDuckPlayer" else null


func am_hunter() -> bool:
	var h := hunter()
	return h != null and int(app.g.gv(h, "player_presence.network_id", -1)) == app.g.my_id()


# --- per frame ----------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not in_duck_hunt():
		if _god_duck != null or _ammo_hunter != null or _speed_duck != null:
			_restore_all()
		_connected_hunter = null
		return
	var h := hunter()
	_track_shots(h)

	var duck := my_duck()
	# Godmode: max_health == health means no injured slowdown, and a 2-damage
	# headshot can't take 9999 down to 0. Full effect needs you to be host,
	# because each machine runs its own copy of the health counter.
	if bool(app.cfg.val("duck.god", false)) and duck != null:
		if _god_duck != duck:
			_god_duck = duck
			_god_orig_max = int(duck.get("max_health"))
		duck.set("max_health", 9999)
		if int(duck.get("health")) > 0:
			duck.set("health", 9999)
	elif _god_duck != null:
		_restore_god()

	if bool(app.cfg.val("duck.speed_on", false)) and duck != null:
		if _speed_duck != duck:
			_speed_duck = duck
			_speed_orig = float(duck.get("speed"))
		duck.set("speed", _speed_orig * float(app.cfg.val("duck.speed", 1.6)))
	elif _speed_duck != null:
		_restore_speed()

	var mine_h: Node = h if am_hunter() else null
	if bool(app.cfg.val("duck.ammo", false)) and mine_h != null:
		_ammo_hunter = mine_h
		mine_h.set("magazine_capacity", 9999)
		mine_h.set("num_of_current_rounds_in_magazine", 9999)
	elif _ammo_hunter != null:
		_restore_ammo()

	if bool(app.cfg.val("duck.rapid", false)) and mine_h != null:
		if bool(mine_h.get("active")) and not bool(mine_h.get("can_shoot")):
			mine_h.set("can_shoot", true)


## Count the hunter's shots on every machine: each shot spawns a smoke particle
## under the hunter (play_shoot_sound_rpc runs on all peers) and an empty
## magazine plays the reload sound.
func _track_shots(h: Node) -> void:
	if h != _connected_hunter:
		_connected_hunter = h
		_shots = 0
		_reload_until = 0.0
		if app.g.valid(h) and not h.child_entered_tree.is_connected(_on_hunter_child):
			h.child_entered_tree.connect(_on_hunter_child)
	if not app.g.valid(h):
		return
	_cap = int(app.g.gv(h, "magazine_capacity", 7))
	var spk = app.g.gv(h, "speaker_reload", null)
	var playing: bool = app.g.valid(spk) and spk.playing
	if playing and not _reload_was_playing:
		_reload_until = Time.get_ticks_msec() / 1000.0 + RELOAD_TIME
	_reload_was_playing = playing
	if _reload_until > 0.0 and Time.get_ticks_msec() / 1000.0 >= _reload_until:
		_reload_until = 0.0
		_shots = 0


func _on_hunter_child(n: Node) -> void:
	if n is GPUParticles3D or n is CPUParticles3D:
		_shots += 1


func magazine() -> Dictionary:
	var h := hunter()
	if h == null:
		return {}
	var now := Time.get_ticks_msec() / 1000.0
	if am_hunter():
		var rounds := int(app.g.gv(h, "num_of_current_rounds_in_magazine", 0))
		var anim = app.g.gv(h, "anim_rig", null)
		var reloading: bool = not bool(app.g.gv(h, "can_shoot", true)) and app.g.valid(anim) and str(anim.current_animation).contains("reload")
		return {"rounds": rounds, "cap": int(app.g.gv(h, "magazine_capacity", 7)), "reloading": reloading, "left": 0.0}
	var reload := _reload_until > now
	return {"rounds": maxi(_cap - _shots, 0), "cap": _cap, "reloading": reload, "left": maxf(_reload_until - now, 0.0)}


# --- actions -------------------------------------------------------------------------

func tp_to_marker() -> void:
	var duck := my_duck()
	if duck == null:
		app.note("marker: you need to be a duck in Duck Hunt")
		return
	var area = app.g.gv(app.g.minigame(), "finish_area", null)
	if not app.g.valid(area):
		app.note("marker: finish area not found")
		return
	var p: Vector3 = area.global_position
	for ch in area.get_children():
		if ch is CollisionShape3D:
			p = ch.global_position
			break
	app.g.teleport(duck, p + Vector3.UP * 0.2)


# --- drawing --------------------------------------------------------------------------

func _draw(c: Control) -> void:
	if not bool(app.cfg.val("duck.mag_hud", true)) or not in_duck_hunt():
		return
	var m := magazine()
	if m.is_empty():
		return
	var vp := c.get_viewport_rect().size
	var rows: Array = []
	var who := "Your rifle" if am_hunter() else "Hunter's rifle"
	if m["reloading"]:
		var extra: String = (" %.1fs" % m["left"]) if float(m["left"]) > 0.0 else ""
		rows.append(["%s: RELOADING%s" % [who, extra], Color("#ff3030")])
	else:
		var r := int(m["rounds"])
		var col := Color("#ff9a30") if r <= 2 else Color.WHITE
		rows.append(["%s: %d / %d" % [who, r, int(m["cap"])], col])
	app.mod("overlay").hud_center(c, vp.y - 40.0, rows, 18)


# --- UI ---------------------------------------------------------------------------------

func build_ui(ui, page) -> void:
	ui.header(page, "Duck Hunt")
	ui.check(page, "Magazine HUD", "duck.mag_hud",
		"Hunter's rounds left, red while reloading. As a duck it's counted from the shots you hear.")
	ui.keybind(page, "duck_marker")
	ui.buttons(page, [["Teleport to the marker", tp_to_marker, "Puts your duck in the finish area."]])
	ui.check(page, "Godmode (duck only)", "duck.god",
		"Infinite health. Fully works when you're the host; as a client the hunter's game may still count you as shot.")
	ui.check(page, "Infinite ammo (hunter only)", "duck.ammo", "Sets the magazine to 9999.")


func build_misc_ui(ui, page) -> void:
	ui.header(page, "Duck Hunt (beta)")
	ui.check(page, "Rapidfire (hunter only)", "duck.rapid",
		"Skips the bolt/reload wait between shots. Pair with infinite ammo.")
	ui.check(page, "Speed hack (duck only)", "duck.speed_on")
	ui.slider(page, "Speed multiplier", "duck.speed", 1.0, 4.0, 0.05, "", "x%.2f")
