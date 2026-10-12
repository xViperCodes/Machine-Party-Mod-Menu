extends Node

## Duck Hunt aimbot + auto fire.
##
## The hunter's camera rig is CameraBase -> CameraHorizontal (yaw, rotation.y)
## -> CameraVertical (pitch, rotation.x) -> Camera3D, and the shot is decided by
## a RayCast3D sitting at the camera origin pointing straight ahead. So we aim
## by writing yaw/pitch so the camera's forward passes through the hitbox, and
## fire by pressing the game's "action_1" input.

var app = null

const TRIGGERS := ["Hold", "Tap", "Always On"]
const TARGETS := ["Head", "Nearest Hitbox", "Body"]
const STYLES := ["FOV", "Distance", "First In List", "Lowest Health"]
const LOCK_DRAW := ["None", "Box", "Name", "Both"]

var target: Node3D = null          # DuckHuntHitbox (Area3D)
var _always_on := false
var _lost_t := 0.0
var _lock_t := 0.0
var _fire_state := "idle"           # idle / pre / pressing / post / done
var _fire_t := 0.0
var _fire_wait := 0.0
var _pressing := false
var _hunter: Node = null


func setup() -> void:
	process_priority = -100   # run before game nodes so simulated fire presses count as "just pressed" this frame
	var c = app.cfg
	c.def("aim.on", false)
	c.def("aim.trigger", "Hold")
	c.def("aim.target", "Head")
	c.def("aim.style", "FOV")
	c.def("aim.smooth", 0.35)
	c.def("aim.fov", 160.0)
	c.def("aim.draw_fov", true)
	c.def("aim.min_dist", 0.0)
	c.def("aim.max_dist", 300.0)
	c.def("aim.skip_downed", true)
	c.def("aim.stick", true)
	c.def("aim.switch_delay", 0.15)
	c.def("aim.deadzone", 0.15)
	c.def("aim.max_step", 0.0)
	c.def("aim.draw_locked", "Both")
	c.def("aim.lock_box", 18.0)
	c.def("aim.lock_thick", 2.0)
	c.def("af.on", false)
	c.def("af.only_hunter", true)
	c.def("af.hold_time", 0.05)
	c.def("af.pre_min", 0.05)
	c.def("af.pre_max", 0.15)
	c.def("af.post_min", 0.25)
	c.def("af.post_max", 0.45)
	c.def("af.press_len", 0.05)
	c.def("af.only_within", true)
	app.hk.register("aim_key", "Aim key (Duck Hunt)", app.hk.mb(MOUSE_BUTTON_RIGHT), "Aimbot")
	app.hk.pressed.connect(_on_hotkey)
	app.add_drawer(_draw)


func disable_all() -> void:
	app.cfg.put("aim.on", false)
	app.cfg.put("af.on", false)
	_reset()


func shutdown() -> void:
	_reset()


func _reset() -> void:
	target = null
	_always_on = false
	_release_fire()
	_fire_state = "idle"


func _on_hotkey(id: String) -> void:
	if id == "aim_key" and str(app.cfg.val("aim.trigger", "Hold")) == "Always On":
		_always_on = not _always_on
		if not _always_on:
			target = null
			_release_fire()


# --- helpers ---------------------------------------------------------------------

## My hunter node, or null when I'm not the hunter / not in Duck Hunt.
func my_hunter() -> Node:
	var mg: Node = app.g.minigame()
	if mg == null or app.g.cls(mg) != "DuckHuntMinigame":
		return null
	if app.g.valid(_hunter) and _hunter.is_inside_tree():
		return _hunter
	_hunter = null
	for n in app.g.find_cls(mg, ["DuckHuntHunterPlayer"]):
		if int(app.g.gv(n, "player_presence.network_id", -1)) == app.g.my_id():
			_hunter = n
			break
	return _hunter


func _hitboxes() -> Array:
	return app.g.find_cls(app.g.minigame(), ["DuckHuntHitbox"])


func hitbox_point(hb: Node3D) -> Vector3:
	for ch in hb.get_children():
		if ch is CollisionShape3D:
			return ch.global_position
	return hb.global_position


func _duck_ok(hb: Node) -> bool:
	var duck = app.g.gv(hb, "player", null)
	if not app.g.valid(duck) or not duck.is_visible_in_tree():
		return false
	if bool(app.cfg.val("aim.skip_downed", true)):
		if not bool(app.g.gv(duck, "active", false)) or int(app.g.gv(duck, "health", 1)) <= 0:
			return false
	return true


func _passes(hb: Node3D, cam: Camera3D, center: Vector2) -> bool:
	if not app.g.valid(hb) or not hb.is_inside_tree() or not _duck_ok(hb):
		return false
	var want := str(app.cfg.val("aim.target", "Head"))
	var is_head := bool(app.g.gv(hb, "is_head", false))
	if want == "Head" and not is_head:
		return false
	if want == "Body" and is_head:
		return false
	var p := hitbox_point(hb)
	var d := cam.global_position.distance_to(p)
	if d < float(app.cfg.val("aim.min_dist", 0.0)) or d > float(app.cfg.val("aim.max_dist", 300.0)):
		return false
	if cam.is_position_behind(p):
		return false
	var style := str(app.cfg.val("aim.style", "FOV"))
	if style == "FOV" or want == "Nearest Hitbox":
		if cam.unproject_position(p).distance_to(center) > float(app.cfg.val("aim.fov", 160.0)):
			return false
	return true


func _pick(cam: Camera3D, center: Vector2) -> Node3D:
	var style := str(app.cfg.val("aim.style", "FOV"))
	var want := str(app.cfg.val("aim.target", "Head"))
	var best: Node3D = null
	var best_score := INF
	for hb in _hitboxes():
		if not _passes(hb, cam, center):
			continue
		var p := hitbox_point(hb)
		var score := 0.0
		if want == "Nearest Hitbox" or style == "FOV":
			score = cam.unproject_position(p).distance_to(center)
		elif style == "Distance":
			score = cam.global_position.distance_to(p)
		elif style == "First In List":
			return hb
		elif style == "Lowest Health":
			score = float(app.g.gv(hb, "player.health", 99)) * 10000.0 + cam.unproject_position(p).distance_to(center)
		if want == "Body":
			# prefer the chest/stomach over limbs: bigger damage, bigger target
			score -= float(app.g.gv(hb, "damage_on_hit", 1)) * 0.001
		if score < best_score:
			best_score = score
			best = hb
	return best


# --- per frame ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if not bool(app.cfg.val("aim.on", false)) and not bool(app.cfg.val("af.on", false)):
		if target != null or _pressing:
			_reset()
		return
	var hunter := my_hunter()
	if hunter == null:
		if target != null or _pressing:
			_reset()
		return
	if app.ui.is_open:
		_release_fire()
		return
	var cam = app.g.gv(hunter, "camera", null)
	if not (cam is Camera3D):
		return
	var vp := get_viewport().get_visible_rect().size
	var center := vp * 0.5

	var trig := str(app.cfg.val("aim.trigger", "Hold"))
	var engaged: bool = _always_on if trig == "Always On" else app.hk.held("aim_key")
	if not engaged or not bool(app.g.gv(hunter, "can_aim", true)):
		target = null
		_lock_t = 0.0
		_fire_state = "idle"
		_release_fire()
		return

	# keep / switch target
	if target != null and not _passes(target, cam, center):
		target = null
		_lost_t = 0.0
	elif target != null and not bool(app.cfg.val("aim.stick", true)):
		var best := _pick(cam, center)
		if best != null:
			target = best
	if target == null:
		_lost_t += delta
		_lock_t = 0.0
		if _fire_state != "pressing":
			_fire_state = "idle"
		if _lost_t >= float(app.cfg.val("aim.switch_delay", 0.15)):
			target = _pick(cam, center)
			if target != null:
				_lost_t = 0.0
	if target == null:
		_release_fire()
		return
	_lock_t += delta

	if bool(app.cfg.val("aim.on", false)):
		_aim_at(hunter, cam, hitbox_point(target), delta)
	_auto_fire(hunter, delta, trig)


func _aim_at(hunter: Node, cam: Camera3D, point: Vector3, delta: float) -> void:
	var yaw_node = app.g.gv(hunter, "camera_horizontal", null)
	var pitch_node = app.g.gv(hunter, "camera_vertical", null)
	if not (yaw_node is Node3D) or not (pitch_node is Node3D):
		return
	var base: Node3D = yaw_node.get_parent()
	var dw := point - cam.global_position
	if dw.length() < 0.01:
		return
	var dl: Vector3 = (base.global_transform.basis.inverse() * dw).normalized()
	var want_pitch := asin(clampf(dl.y, -1.0, 1.0))
	var want_yaw := atan2(-dl.x, -dl.z)
	var hl := deg_to_rad(float(app.g.gv(hunter, "horizontal_limit", 180.0)))
	var vl := deg_to_rad(float(app.g.gv(hunter, "vertical_limit", 90.0)))
	if hl > 0.0:
		want_yaw = clampf(want_yaw, -hl, hl)
	if vl > 0.0:
		want_pitch = clampf(want_pitch, -vl, vl)

	var cur_yaw: float = yaw_node.rotation.y
	var cur_pitch: float = pitch_node.rotation.x
	var dy := angle_difference(cur_yaw, want_yaw)
	var dp := angle_difference(cur_pitch, want_pitch)
	var dead := deg_to_rad(float(app.cfg.val("aim.deadzone", 0.15)))
	if absf(dy) < dead and absf(dp) < dead:
		return
	var smooth := clampf(float(app.cfg.val("aim.smooth", 0.35)), 0.0, 0.98)
	var t := 1.0 - pow(smooth, delta * 60.0)
	var sy := dy * t
	var sp := dp * t
	var max_step := deg_to_rad(float(app.cfg.val("aim.max_step", 0.0)))
	if max_step > 0.0:
		var mag := Vector2(sy, sp).length()
		if mag > max_step:
			sy *= max_step / mag
			sp *= max_step / mag
	yaw_node.rotation.y = cur_yaw + sy
	pitch_node.rotation.x = cur_pitch + sp


# --- auto fire --------------------------------------------------------------------

func _on_target(hunter: Node) -> bool:
	var ray = app.g.gv(hunter, "laser_raycast", null)
	if not (ray is RayCast3D):
		return true
	ray.force_raycast_update()
	if not ray.is_colliding():
		return false
	var col = ray.get_collider()
	if app.g.cls(col) != "DuckHuntHitbox":
		return false
	return app.g.gv(col, "player", null) == app.g.gv(target, "player", null)


func _auto_fire(hunter: Node, delta: float, trig: String) -> void:
	if not bool(app.cfg.val("af.on", false)):
		_release_fire()
		return
	if bool(app.cfg.val("af.only_hunter", true)) and hunter == null:
		return
	_fire_t += delta
	match _fire_state:
		"idle":
			if _lock_t >= float(app.cfg.val("af.hold_time", 0.05)):
				_fire_state = "pre"
				_fire_t = 0.0
				_fire_wait = _rand("af.pre_min", "af.pre_max")
		"pre", "post":
			if _fire_t < _fire_wait:
				return
			if not bool(app.g.gv(hunter, "can_shoot", true)):
				return
			if bool(app.cfg.val("af.only_within", true)) and not _on_target(hunter):
				return
			_press_fire()
			_fire_state = "pressing"
			_fire_t = 0.0
		"pressing":
			if _fire_t >= float(app.cfg.val("af.press_len", 0.05)):
				_release_fire()
				if trig == "Hold":
					_fire_state = "done"     # one shot per lock in Hold mode
				else:
					_fire_state = "post"
					_fire_t = 0.0
					_fire_wait = _rand("af.post_min", "af.post_max")
		"done":
			pass


func _rand(k_min: String, k_max: String) -> float:
	var a := float(app.cfg.val(k_min, 0.0))
	var b := float(app.cfg.val(k_max, 0.0))
	return randf_range(minf(a, b), maxf(a, b))


func _press_fire() -> void:
	if InputMap.has_action("action_1"):
		Input.action_press("action_1")
		_pressing = true


func _release_fire() -> void:
	if _pressing and InputMap.has_action("action_1"):
		Input.action_release("action_1")
	_pressing = false


# --- drawing ------------------------------------------------------------------------

func _draw(c: Control) -> void:
	if not bool(app.cfg.val("aim.on", false)) and not bool(app.cfg.val("af.on", false)):
		return
	var hunter := my_hunter()
	if hunter == null:
		return
	var center := c.get_viewport_rect().size * 0.5
	if bool(app.cfg.val("aim.draw_fov", true)):
		var engaged: bool = _always_on or app.hk.held("aim_key")
		c.draw_arc(center, float(app.cfg.val("aim.fov", 160.0)), 0.0, TAU, 96,
			Color(1, 1, 1, 0.55) if engaged else Color(1, 1, 1, 0.25), 1.5, true)
	if target == null or not is_instance_valid(target):
		return
	var cam = app.g.gv(hunter, "camera", null)
	if not (cam is Camera3D):
		return
	var p := hitbox_point(target)
	if cam.is_position_behind(p):
		return
	var sp: Vector2 = cam.unproject_position(p)
	var mode := str(app.cfg.val("aim.draw_locked", "Both"))
	var col := Color("#ff3b3b")
	if mode == "Box" or mode == "Both":
		var s := float(app.cfg.val("aim.lock_box", 18.0))
		c.draw_rect(Rect2(sp - Vector2(s, s) * 0.5, Vector2(s, s)), col, false, float(app.cfg.val("aim.lock_thick", 2.0)))
	if mode == "Name" or mode == "Both":
		var duck = app.g.gv(target, "player", null)
		var nm := "target"
		if app.g.valid(duck):
			nm = app.g.player_name(int(app.g.gv(duck, "player_presence.network_id", -1)))
			nm += "  HEAD" if bool(app.g.gv(target, "is_head", false)) else ""
		app.mod("overlay").text_center(c, sp + Vector2(0, -float(app.cfg.val("aim.lock_box", 18.0))), nm, col, 14)


# --- UI ----------------------------------------------------------------------------

func build_ui(ui, page) -> void:
	ui.note(page, "Duck Hunt, when you're the hunter. Aims by turning your rifle camera onto a duck's hitbox; the game decides hits with a ray from the centre of your scope, so what's under the crosshair is what you hit.")
	ui.header(page, "Aimbot")
	ui.check(page, "Enable aimbot", "aim.on")
	ui.keybind(page, "aim_key")
	ui.option(page, "Trigger mode", "aim.trigger", TRIGGERS,
		"Hold: aim while the key is held. Tap: aim and keep tapping shots while held. Always On: click the key once to keep aiming and firing, click again to stop.")
	ui.option(page, "Target", "aim.target", TARGETS)
	ui.option(page, "Aim style", "aim.style", STYLES)
	ui.slider(page, "Smoothness", "aim.smooth", 0.0, 0.98, 0.01, "0 snaps instantly; higher is slower and more human.")
	ui.slider(page, "FOV radius", "aim.fov", 10.0, 900.0, 5.0, "", "%.0f px")
	ui.check(page, "Draw FOV", "aim.draw_fov")
	ui.slider(page, "Min aim distance", "aim.min_dist", 0.0, 100.0, 1.0, "", "%.0f m")
	ui.slider(page, "Max aim distance", "aim.max_dist", 5.0, 500.0, 5.0, "", "%.0f m")
	ui.check(page, "Skip downed ducks", "aim.skip_downed")
	ui.check(page, "Stick to target", "aim.stick", "Holds one hitbox instead of flicking between them.")
	ui.slider(page, "Switch delay", "aim.switch_delay", 0.0, 1.5, 0.01, "Wait before picking a new target.", "%.2f s")
	ui.slider(page, "Deadzone", "aim.deadzone", 0.0, 3.0, 0.05, "Don't move when already this close.", "%.2f deg")
	ui.slider(page, "Max step", "aim.max_step", 0.0, 20.0, 0.25, "Largest turn per frame. 0 = unlimited.", "%.2f deg")
	ui.option(page, "Draw locked", "aim.draw_locked", LOCK_DRAW)
	ui.slider(page, "Locked box size", "aim.lock_box", 4.0, 80.0, 1.0, "", "%.0f px")
	ui.slider(page, "Locked box thickness", "aim.lock_thick", 1.0, 6.0, 0.5)

	ui.header(page, "Auto fire")
	ui.check(page, "Enable auto fire", "af.on")
	ui.check(page, "Only as hunter", "af.only_hunter")
	ui.slider(page, "Hold time", "af.hold_time", 0.0, 1.0, 0.01, "How long a target must be locked before the first shot.", "%.2f s")
	ui.slider(page, "Min pre-fire delay", "af.pre_min", 0.0, 1.0, 0.01, "Wait before the first shot - lands anywhere between min and max.", "%.2f s")
	ui.slider(page, "Max pre-fire delay", "af.pre_max", 0.0, 1.0, 0.01, "", "%.2f s")
	ui.slider(page, "Min post-fire delay", "af.post_min", 0.0, 2.0, 0.01, "Time between shots in Tap / Always On mode.", "%.2f s")
	ui.slider(page, "Max post-fire delay", "af.post_max", 0.0, 2.0, 0.01, "", "%.2f s")
	ui.slider(page, "Press length", "af.press_len", 0.02, 0.3, 0.01, "How long the fire input is held for each shot.", "%.2f s")
	ui.check(page, "Only fire within hitbox", "af.only_within", "Holds fire until the scope ray is actually on the target, so no rounds are wasted mid-swing.")
	ui.live(page, _status, ui.MUTED)


func _status() -> String:
	var h := my_hunter()
	if h == null:
		return "Status: not the hunter right now."
	var t := "none"
	if target != null and is_instance_valid(target):
		t = app.g.player_name(int(app.g.gv(target, "player.player_presence.network_id", -1)))
	return "Status: hunter  |  target: %s  |  can shoot: %s" % [t, "yes" if app.g.gv(h, "can_shoot", false) else "no"]
