extends Node

## Rebindable hotkeys. A binding is {"t": "k"|"m"|"", "c": code}:
##   "k" = physical keycode, "m" = mouse button index, "" = unbound.
## Keys are polled every frame so they work even while the game captures input.

var app = null
var actions: Dictionary = {}     # id -> {"label": String, "group": String}
var order: Array = []
var _down: Dictionary = {}
var capturing: String = ""
var _capture_done: Callable = Callable()
var _suppress := 0

const MOUSE_NAMES := {1: "Mouse 1", 2: "Mouse 2", 3: "Mouse 3", 8: "Mouse 4", 9: "Mouse 5"}

signal pressed(id: String)
signal released(id: String)


static func kb(code: int) -> Dictionary:
	return {"t": "k", "c": code}


static func mb(button: int) -> Dictionary:
	return {"t": "m", "c": button}


static func unbound() -> Dictionary:
	return {"t": "", "c": 0}


func setup() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	register("menu", "Toggle menu", kb(KEY_INSERT), "General")
	register("unload", "Unload mod", kb(KEY_END), "General")


func register(id: String, label: String, default_bind: Dictionary, group: String = "General") -> void:
	if not actions.has(id):
		order.append(id)
	actions[id] = {"label": label, "group": group}
	app.cfg.def("bind." + id, default_bind)


func bind_of(id: String) -> Dictionary:
	var b = app.cfg.val("bind." + id, unbound())
	return b if b is Dictionary else unbound()


func set_bind(id: String, b: Dictionary) -> void:
	app.cfg.put("bind." + id, b)


func bind_name(b: Dictionary) -> String:
	var t := str(b.get("t", ""))
	var c := int(b.get("c", 0))
	if c == 0 or t == "":
		return "None"
	if t == "m":
		return MOUSE_NAMES.get(c, "Mouse %d" % c)
	var s := OS.get_keycode_string(c)
	return s.to_upper() if not s.is_empty() else "Key %d" % c


## True while the hotkey is physically held (ignores typing / capture).
func held(id: String) -> bool:
	return bool(_down.get(id, false))


func _is_down(b: Dictionary) -> bool:
	var c := int(b.get("c", 0))
	if c == 0:
		return false
	match str(b.get("t", "")):
		"k":
			return Input.is_physical_key_pressed(c)
		"m":
			return Input.is_mouse_button_pressed(c)
	return false


func _typing() -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	var f := vp.gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func _process(_delta: float) -> void:
	var blocked := _typing() or capturing != "" or not DisplayServer.window_is_focused()
	var menu_open: bool = app.ui != null and app.ui.is_open
	for id in order:
		var now := false
		# While the menu is open only the menu/unload keys work, so clicking
		# around the menu doesn't fire game hotkeys (e.g. Mouse 2 = aim key).
		if not blocked and (not menu_open or id == "menu" or id == "unload"):
			now = _is_down(bind_of(id))
		var was: bool = _down.get(id, false)
		_down[id] = now
		if _suppress > 0:
			continue
		if now and not was:
			pressed.emit(id)
		elif was and not now:
			released.emit(id)
	if _suppress > 0:
		_suppress -= 1


# --- capture --------------------------------------------------------------------

func start_capture(id: String, done: Callable) -> void:
	capturing = id
	_capture_done = done


func cancel_capture() -> void:
	_finish_capture(false, unbound())


func _finish_capture(apply: bool, b: Dictionary) -> void:
	var id := capturing
	capturing = ""
	if apply and id != "":
		set_bind(id, b)
	_suppress = 2
	if _capture_done.is_valid():
		_capture_done.call()
	_capture_done = Callable()


func _input(event: InputEvent) -> void:
	if capturing == "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode
		if code == 0:
			code = event.keycode
		if code == KEY_ESCAPE:
			_finish_capture(false, unbound())
		else:
			_finish_capture(true, kb(code))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if MOUSE_NAMES.has(event.button_index):
			_finish_capture(true, mb(event.button_index))
			get_viewport().set_input_as_handled()
