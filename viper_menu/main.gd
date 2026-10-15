extends Node

## Viper Menu - entry script for Krunk-theduck's MachinePartyModLoader.
##
## The loader compiles this file and calls _mod_init / _mod_ready. Everything
## else lives in core/ and features/ and is compiled here with loader.compile().
## Modules talk to each other through this node (`app`), using duck typing,
## because loose scripts compiled at runtime can't reference each other's types.

const MOD_ID := "viper_menu"
const MOD_NAME := "Viper Menu"
const VERSION := "v0.3.1"
const AUTHOR := "xViperCodes"
## Info tab buttons.
const GITHUB_URL := "https://github.com/xViperCodes/Machine-Party-Mod-Menu"
const YOUTUBE_URL := "https://www.youtube.com/@xViperCodes"

## [module key, path relative to this folder]. Order matters: core first.
const MODULES := [
	["cfg", "core/config.gd"],
	["g", "core/game.gd"],
	["hk", "core/hotkeys.gd"],
	["ui", "core/ui.gd"],
	["overlay", "features/overlay.gd"],
	["debug", "features/debug_flags.gd"],
	["minigames", "features/minigames.gd"],
	["session", "features/session.gd"],
	["browser", "features/server_browser.gd"],
	["players", "features/players.gd"],
	["esp", "features/esp.gd"],
	["aimbot", "features/aimbot.gd"],
	["duck", "features/duck_hunt.gd"],
	["solvers", "features/solvers.gd"],
	["misc", "features/misc.gd"],
	["bots", "features/bots.gd"],
]

var loader = null
var dir: String = ""
var mods: Dictionary = {}
var order: Array = []
var cfg = null
var g = null
var hk = null
var ui = null
var booted := false
var unloaded := false

var canvas_layer: CanvasLayer = null
var canvas: Control = null
var _drawers: Array = []
var _log: PackedStringArray = PackedStringArray()

signal log_added(line: String)


func _mod_init(l) -> void:
	loader = l
	dir = str(l.dir_of(MOD_ID))


func _mod_ready(l) -> void:
	loader = l
	if dir.is_empty():
		dir = str(l.dir_of(MOD_ID))
	# Other autoloads (Globals, GameManager...) are not in the tree yet while the
	# loader is still being added, so finish booting at the end of the frame.
	_boot.call_deferred()


func _boot() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	canvas_layer = CanvasLayer.new()
	canvas_layer.name = "ViperDraw"
	canvas_layer.layer = 118
	add_child(canvas_layer)
	canvas = Control.new()
	canvas.name = "Canvas"
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(canvas)
	canvas.draw.connect(_on_canvas_draw)

	for entry in MODULES:
		var key: String = entry[0]
		var node = _spawn(entry[1], key)
		if node == null:
			continue
		mods[key] = node
		order.append(node)
		match key:
			"cfg": cfg = node
			"g": g = node
			"hk": hk = node
			"ui": ui = node

	if cfg == null or g == null or hk == null or ui == null:
		note("core module missing - menu disabled")
		return

	for n in order:
		if n.has_method("setup"):
			n.setup()
	cfg.load_file()
	for n in order:
		if n.has_method("after_config"):
			n.after_config()
	ui.build()
	hk.pressed.connect(_on_hotkey)
	booted = true
	note("%s %s ready - press %s to open" % [MOD_NAME, VERSION, hk.bind_name(hk.bind_of("menu"))])


func _spawn(rel: String, key: String):
	var path := dir.path_join(rel)
	var s = loader.compile(path)
	if s == null:
		note("module failed to compile: %s (see godot.log for the parser error)" % rel)
		return null
	var n = s.new()
	if not (n is Node):
		note("module is not a Node: " + rel)
		return null
	n.name = key
	n.set("app", self)
	add_child(n)
	return n


func _process(_delta: float) -> void:
	if booted and canvas != null:
		canvas.queue_redraw()


func _on_canvas_draw() -> void:
	for cb in _drawers:
		if cb is Callable and cb.is_valid():
			cb.call(canvas)


func add_drawer(cb: Callable) -> void:
	if not _drawers.has(cb):
		_drawers.append(cb)


func remove_drawer(cb: Callable) -> void:
	_drawers.erase(cb)


func mod(key: String):
	return mods.get(key, null)


func _on_hotkey(id: String) -> void:
	match id:
		"menu":
			ui.set_open(not ui.is_open)
		"unload":
			unload()


func note(msg: String) -> void:
	var line := "[viper] " + msg
	_log.append(line)
	if loader != null and loader.has_method("note"):
		loader.note(line)
	else:
		print(line)
	log_added.emit(line)


func log_lines() -> PackedStringArray:
	return _log


## "Disable all cheats": every module turns its gameplay features off.
func panic() -> void:
	for n in order:
		if is_instance_valid(n) and n.has_method("disable_all"):
			n.disable_all()
	note("all cheats disabled")


## END key: restore everything the mod changed and remove it until restart.
func unload() -> void:
	if unloaded:
		return
	unloaded = true
	for n in order:
		if is_instance_valid(n) and n.has_method("shutdown"):
			n.shutdown()
	booted = false
	_drawers.clear()
	for c in get_children():
		c.queue_free()
	mods.clear()
	order.clear()
	set_process(false)
	note("unloaded - restart the game to load it again")
