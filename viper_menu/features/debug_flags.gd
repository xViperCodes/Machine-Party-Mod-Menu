extends Node

## The game's own developer flags, each with Leave / Force On / Force Off.
## "Force" re-applies the value every frame, so the game can't flip it back.

var app = null

## [id, label, candidate "Autoload.property" paths (first that exists wins), tip]
const FLAGS := [
	["allow_singleplayer", "Allow Singleplayer", ["Globals.allow_singleplayer"], "Lets the lobby start and minigames run with just you."],
	["debug", "Debug", ["Globals.debug"], "Mostly gates editor-only behaviour; also enables the localization debug keys."],
	["debug_local", "Debug Local", ["Globals.debug_local"], "Editor-only boot into the local lobby."],
	["debug_tools_enabled", "Debug Tools Enabled", ["Globals.debug_tools_enabled"], "Flag behind the game's dev panel. Use the button below to actually open it."],
	["instant_start", "Instant Start", ["Globals.debug_instant_start"], ""],
	["skip_brief", "Skip Brief", ["Globals.debug_skip_brief"], "Skips minigame briefings on this machine."],
	["skip_intermission", "Skip Intermission", ["Globals.debug_skip_intermission"], "Host loads the next game straight away. Clients without the mod still play the picker animation."],
	["skip_intro", "Skip Intro Cutscene", ["Globals.skipping_intro_cutscene"], "Same as the lobby's skip-intro toggle."],
	["splash_viewed", "Splash Viewed", ["Globals.splash_screen_viewed"], "Skips the splash screen next time the main menu loads."],
	["debug_mode", "Debug Mode", ["GameManager.debug_mode", "Globals.debug_mode", "Globals.debug_capture_mouse_enabled"], "Uses the first of GameManager.debug_mode / Globals.debug_mode / Globals.debug_capture_mouse_enabled that exists in your game version."],
	["host_mode", "Host Mode Enabled", ["GameManager.host_mode_enabled"], ""],
	["multiplayer_mode", "Multiplayer Enabled", ["GameManager.multiplayer_mode_enabled"], ""],
	["host_game", "Host Game", ["GameManager.host_game"], ""],
]

var _originals: Dictionary = {}   # flag id -> original value before we forced it


func setup() -> void:
	for f in FLAGS:
		app.cfg.def("dbg." + f[0], "Leave")


func _resolve(f: Array) -> Array:
	for cand in f[2]:
		var parts: PackedStringArray = str(cand).split(".")
		var node: Node = app.g.al(parts[0])
		if node != null and (parts[1] in node):
			return [node, parts[1]]
	return []


func _value_text(f: Array) -> String:
	var r := _resolve(f)
	if r.is_empty():
		return "n/a"
	var v = r[0].get(r[1])
	return ("ON" if v else "off") if v is bool else str(v)


func _process(_delta: float) -> void:
	for f in FLAGS:
		var mode := str(app.cfg.val("dbg." + f[0], "Leave"))
		if mode == "Leave":
			continue
		var r := _resolve(f)
		if r.is_empty():
			continue
		var want := mode == "Force On"
		var cur = r[0].get(r[1])
		if not _originals.has(f[0]):
			_originals[f[0]] = cur
		if cur != want:
			r[0].set(r[1], want)


func restore_all() -> void:
	for f in FLAGS:
		app.cfg.put("dbg." + f[0], "Leave")
		if _originals.has(f[0]):
			var r := _resolve(f)
			if not r.is_empty():
				r[0].set(r[1], _originals[f[0]])
	_originals.clear()
	app.ui.refresh_bound()
	app.note("debug flags restored")


func shutdown() -> void:
	restore_all()


func build_ui(ui, page) -> void:
	ui.note(page, "The game's developer flags. Force On / Force Off keep the value pinned every frame; Leave hands control back to the game. The live value is shown next to each one.")
	ui.header(page, "Flags")
	for f in FLAGS:
		ui.tri(page, f[1], "dbg." + f[0], _value_text.bind(f), f[3])
	ui.buttons(page, [
		["Restore All", restore_all, "Set everything back to Leave and restore the values from before you forced them."],
		["Open dev panel", _open_dev_panel, "Calls Globals.enable_debug_tools() - the same thing the -debug-tools launch option does. Toggle the panel with F1."],
	])


func _open_dev_panel() -> void:
	var gl: Node = app.g.al("Globals")
	if gl != null and gl.has_method("enable_debug_tools"):
		gl.enable_debug_tools()
		app.note("dev panel enabled - press F1 in game")
	else:
		app.note("Globals.enable_debug_tools() not found in this game version")
