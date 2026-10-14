extends Node

## Server Browser tab: a list of public lobbies, join by room ID, and (host)
## make your own lobby public.
##
## The public-lobby tags (mpsb_*), the Steam lobby search and the join flow are
## adapted from MachineParty+ by J_axon and Krunk (MIT License - see
## THIRD_PARTY_NOTICES.md). Using the same tags means Viper Menu and
## MachineParty+ players see each other's public lobbies.

var app = null

const KEY_PUB := "mpsb_pub"
const KEY_NAME := "mpsb_name"
const KEY_MAX := "mpsb_max"
const KEY_VER := "mpsb_ver"
const KEY_HOST := "mpsb_host"
const KEY_JOIN := "mpsb_join"      # "1" while joinable (public, not full, lobby or mid-join allowed)
const KEY_MID := "mpsb_mid"        # "1" if joining mid-match is allowed
const KEY_STATE := "mpsb_state"    # "lobby" | "ingame"
const KEY_COUNT := "mpsb_count"
const KEY_BANS := "mpsb_bans"      # comma-joined steam ids the lobby hides from

const VANILLA_CAP := 4
const LOBBY_TSCN := "res://scenes/lobby/lobby_scene.tscn"

var _signal_hooked := false
var _pending := false
var _results: Array = []
var _refreshed_at := -1.0
var _status := "Press Refresh to search for public lobbies."
var _list_box: VBoxContainer = null
var _ui = null
var _sig := ""
var _was_open := false
var _upd_t := 0.0
var _pending_join := 0
var _pending_join_t := 0.0


func setup() -> void:
	var c = app.cfg
	c.def("sb.filter", "")
	c.def("sb.code", "")
	c.def("sb.name", "")
	c.def("sb.max", 4)
	c.def("sb.mid", true)


# --- steam ---------------------------------------------------------------------------

## GodotSteam's singleton. Looked up at runtime so the mod still loads if Steam
## isn't there (the harness uses a stand-in node called /root/Steam).
func steam():
	if Engine.has_singleton("Steam"):
		return Engine.get_singleton("Steam")
	return app.g.al("Steam")


func steam_ready() -> bool:
	if steam() == null:
		return false
	var sw: Node = app.g.al("Steamworks")
	if sw != null and ("is_initialized" in sw):
		return bool(sw.get("is_initialized"))
	return true


func _k(constant: String, fallback: int) -> int:
	if ClassDB.class_exists("Steam") and ClassDB.class_has_integer_constant("Steam", constant):
		return ClassDB.class_get_integer_constant("Steam", constant)
	return fallback


func _hook_signal() -> void:
	if _signal_hooked:
		return
	var s = steam()
	if s != null and s.has_signal("lobby_match_list"):
		s.connect("lobby_match_list", _on_lobby_match_list)
		_signal_hooked = true


func _my_steam_id() -> int:
	var s = steam()
	return int(s.getSteamID()) if s != null else 0


func _my_steam_name() -> String:
	var s = steam()
	if s == null:
		return "Host"
	return str(s.getFriendPersonaName(s.getSteamID()))


# --- lobby info ----------------------------------------------------------------------

## The Steam lobby this machine hosts (0 if not hosting).
func my_lobby_id() -> int:
	if not app.g.is_host():
		return 0
	return int(app.g.gv(app.g.backend(), "lobby_id", 0))


## The lobby we're in, host or not (the 18-digit room ID).
func room_id() -> int:
	return int(app.g.gv(app.g.backend(), "lobby_id", 0))


func is_public() -> bool:
	var id := my_lobby_id()
	return id > 0 and steam_ready() and str(steam().getLobbyData(id, KEY_PUB)) == "1"


## Machine Party's own player cap (NetworkManager.MAX_PLAYERS).
func player_cap() -> int:
	var nm: Node = app.g.al("NetworkManager")
	var mx := int(app.g.script_consts(nm).get("MAX_PLAYERS", VANILLA_CAP))
	return maxi(mx, 1)


func _game_version() -> String:
	return str(app.g.gv(app.g.al("Globals"), "game_version", ""))


## Ignore extra tags other mods add to the version string (e.g. "v2.1.2-8P-...").
func _base_version(v: String) -> String:
	var i := v.find("-8P")
	return v.substr(0, i) if i >= 0 else v


func _player_count() -> int:
	var cp = app.g.gv(app.g.backend(), "connected_players", {})
	return maxi(1, cp.size()) if cp is Dictionary else 1


# --- browse ----------------------------------------------------------------------------

func refresh() -> void:
	if not steam_ready():
		_status = "Steam isn't running - start Machine Party through Steam."
		_results = []
		_sig = ""
		return
	_hook_signal()
	var s = steam()
	_pending = true
	s.addRequestLobbyListDistanceFilter(_k("LOBBY_DISTANCE_FILTER_WORLDWIDE", 3))
	s.addRequestLobbyListStringFilter(KEY_PUB, "1", _k("LOBBY_COMPARISON_EQUAL", 0))
	s.addRequestLobbyListStringFilter(KEY_JOIN, "1", _k("LOBBY_COMPARISON_EQUAL", 0))
	s.addRequestLobbyListResultCountFilter(50)
	s.requestLobbyList()
	_status = "Searching..."


func _on_lobby_match_list(lobbies: Array) -> void:
	if not _pending:
		return
	_pending = false
	var s = steam()
	var me := str(_my_steam_id())
	var mine := _base_version(_game_version())
	var out: Array = []
	for lid in lobbies:
		var id := int(lid)
		if str(s.getLobbyData(id, KEY_PUB)) != "1":
			continue
		var bans := str(s.getLobbyData(id, KEY_BANS))
		if bans != "" and ("," + bans + ",").contains("," + me + ","):
			continue
		var lname := str(s.getLobbyData(id, KEY_NAME)).strip_edges()
		var host := str(s.getLobbyData(id, KEY_HOST)).strip_edges()
		if lname.is_empty():
			lname = host if not host.is_empty() else "Machine Party Lobby"
		var ver := str(s.getLobbyData(id, KEY_VER))
		var maxp := int(str(s.getLobbyData(id, KEY_MAX)))
		if maxp <= 0:
			maxp = VANILLA_CAP
		var count := int(str(s.getLobbyData(id, KEY_COUNT)))
		if count <= 0:
			count = int(s.getNumLobbyMembers(id))
		count = maxi(count, 1)
		out.append({
			"id": id, "name": lname, "host": host, "players": count, "max": maxp,
			"version": ver, "state": str(s.getLobbyData(id, KEY_STATE)),
			"full": count >= maxp,
			"compatible": ver.is_empty() or mine.is_empty() or _base_version(ver) == mine,
		})
	out.sort_custom(func(a, b) -> bool:
		if a["compatible"] != b["compatible"]:
			return a["compatible"]
		return int(a["players"]) > int(b["players"]))
	_results = out
	_refreshed_at = Time.get_ticks_msec() / 1000.0
	_status = "%d public lobb%s found." % [out.size(), "y" if out.size() == 1 else "ies"]
	_sig = ""


func results() -> Array:
	return _results


# --- join ------------------------------------------------------------------------------

func join_by_code(code: String) -> void:
	code = code.strip_edges()
	if code.length() != 18 or not code.is_valid_int():
		app.note("room IDs are 18 digits - copy it from the host's lobby")
		return
	join(int(code))


func paste_code() -> void:
	app.cfg.put("sb.code", DisplayServer.clipboard_get().strip_edges())


## Uses the game's own client join, the same path as accepting a Steam invite.
## Already in a lobby or match? Leave it the way the pause menu's Quit does,
## then join from the main menu.
func join(lobby_id: int) -> void:
	if lobby_id <= 0:
		return
	if not steam_ready():
		app.note("join: Steam isn't running")
		return
	if lobby_id == room_id():
		app.note("you're already in that lobby")
		return
	var nm: Node = app.g.al("NetworkManager")
	if nm != null and nm.has_method("is_active") and nm.is_active():
		var pm: Node = app.g.al("PauseMenu")
		if pm != null and pm.has_method("_on_quit_confirm_pressed"):
			_pending_join = lobby_id
			_pending_join_t = 0.0
			app.ui.set_open(false)
			app.note("leaving this lobby, then joining...")
			pm._on_quit_confirm_pressed()
		else:
			app.note("leave your current lobby first (Esc > Quit), then join")
		return
	_do_join(lobby_id)


func _do_join(lobby_id: int) -> void:
	var gm: Node = app.g.al("GameManager")
	if gm == null:
		return
	gm.set("join_lobby_id", lobby_id)
	gm.set("host_game", false)
	gm.set("custom_game", false)
	app.ui.set_open(false)
	app.note("joining lobby %d" % lobby_id)
	var sc: Node = app.g.scene()
	if app.g.valid(sc) and sc.has_method("switch_to_lobby_scene"):
		sc.switch_to_lobby_scene()
		return
	var ov: Node = app.g.al("GlobalOverlay")
	if ov != null and ov.has_method("fade_overlay") and ov.has_signal("fade_finished"):
		ov.fade_overlay(Color.BLACK, 1.0)
		await ov.fade_finished
	if is_inside_tree():
		get_tree().change_scene_to_file(LOBBY_TSCN)


func _tick_pending_join(delta: float) -> void:
	if _pending_join <= 0:
		return
	_pending_join_t += delta
	if _pending_join_t > 20.0:
		app.note("join cancelled - didn't get back to the main menu")
		_pending_join = 0
		return
	var nm: Node = app.g.al("NetworkManager")
	if nm != null and nm.has_method("is_active") and nm.is_active():
		return
	var sc: Node = app.g.scene()
	if not app.g.valid(sc) or not sc.has_method("switch_to_lobby_scene"):
		return
	# Give the main menu a moment to finish fading in.
	if _pending_join_t < 1.5:
		return
	var id := _pending_join
	_pending_join = 0
	_do_join(id)


# --- host: public lobby ----------------------------------------------------------------

func publish() -> void:
	if not app.g.is_host():
		app.note("only the host can make the lobby public")
		return
	var id := my_lobby_id()
	if id <= 0 or not steam_ready():
		app.note("host an online lobby first")
		return
	var s = steam()
	var mx := clampi(int(app.cfg.val("sb.max", 4)), maxi(1, _player_count()), player_cap())
	var lname := str(app.cfg.val("sb.name", "")).strip_edges()
	if lname.is_empty():
		lname = "%s's lobby" % _my_steam_name()
	s.setLobbyType(id, _k("LOBBY_TYPE_PUBLIC", 2))
	s.setLobbyJoinable(id, true)
	s.setLobbyMemberLimit(id, mx)
	s.setLobbyData(id, KEY_PUB, "1")
	s.setLobbyData(id, KEY_NAME, lname.substr(0, 63))
	s.setLobbyData(id, KEY_MAX, str(mx))
	s.setLobbyData(id, KEY_VER, _game_version())
	s.setLobbyData(id, KEY_HOST, _my_steam_name())
	s.setLobbyData(id, KEY_MID, "1" if bool(app.cfg.val("sb.mid", true)) else "0")
	s.setLobbyData(id, KEY_BANS, _bans_csv())
	var nm: Node = app.g.al("NetworkManager")
	if nm != null and ("max_player_count" in nm):
		nm.set("max_player_count", mx)
	_update_joinable()
	app.note("lobby is public: \"%s\" (%d max)" % [lname, mx])


func unpublish() -> void:
	var id := my_lobby_id()
	if id <= 0 or not steam_ready():
		return
	var s = steam()
	s.setLobbyType(id, _k("LOBBY_TYPE_FRIENDS_ONLY", 1))
	s.setLobbyData(id, KEY_PUB, "0")
	s.setLobbyData(id, KEY_JOIN, "0")
	app.note("lobby is private again (friends only)")


## Keeps the browser listing honest: hidden while full, or mid-match when
## mid-joining is off.
func _update_joinable() -> void:
	if not is_public():
		return
	var s = steam()
	var id := my_lobby_id()
	var maxp := int(str(s.getLobbyData(id, KEY_MAX)))
	if maxp <= 0:
		maxp = VANILLA_CAP
	var count := _player_count()
	var mid: bool = str(s.getLobbyData(id, KEY_MID)) == "1"
	var in_game := bool(app.g.gv(app.g.al("GameManager"), "game_in_progress", false))
	var joinable: bool = count < maxp and (mid or not in_game)
	s.setLobbyData(id, KEY_JOIN, "1" if joinable else "0")
	s.setLobbyData(id, KEY_COUNT, str(count))
	s.setLobbyData(id, KEY_STATE, "ingame" if in_game else "lobby")
	var bans := _bans_csv()
	if str(s.getLobbyData(id, KEY_BANS)) != bans:
		s.setLobbyData(id, KEY_BANS, bans)


## Players kicked with "block from rejoining" don't see this lobby in browsers.
func _bans_csv() -> String:
	var pl = app.mod("players")
	var ids = pl.get("_blocked_steam_ids") if pl != null else []
	var out: PackedStringArray = PackedStringArray()
	if ids is Array:
		for sid in ids:
			out.append(str(sid))
	return ",".join(out)


func copy_room_id() -> void:
	var id := room_id()
	if id <= 0:
		app.note("not in an online lobby")
		return
	DisplayServer.clipboard_set(str(id))
	app.note("room ID copied: %d" % id)


func _process(delta: float) -> void:
	_tick_pending_join(delta)
	_upd_t += delta
	if _upd_t >= 2.0:
		_upd_t = 0.0
		if app.g.is_host() and my_lobby_id() > 0:
			_update_joinable()
	var open: bool = app.ui.is_open and app.ui.current_tab == "Server Browser"
	if open and not _was_open:
		# Opening the tab refreshes the list if it's more than 30 s old.
		var now := Time.get_ticks_msec() / 1000.0
		if not _pending and (_refreshed_at < 0.0 or now - _refreshed_at > 30.0):
			refresh()
	_was_open = open
	if open:
		var sig := "%s|%s|%d" % [str(_results.size()), str(app.cfg.val("sb.filter", "")), room_id()]
		for r in _results:
			sig += ",%d:%d" % [r["id"], r["players"]]
		if sig != _sig:
			_sig = sig
			_rebuild_list()


# --- UI ----------------------------------------------------------------------------------

func build_ui(ui, page) -> void:
	_ui = ui
	ui.note(page, "Public lobbies from players running Viper Menu or MachineParty+. Joining uses the game's own join, the same as accepting a Steam invite, so the host doesn't need any mod.")

	ui.header(page, "Public lobbies")
	ui.live(page, func() -> String:
		var t := _status
		if _refreshed_at >= 0.0 and not _pending:
			t += "  (updated %ds ago)" % int(Time.get_ticks_msec() / 1000.0 - _refreshed_at)
		return t, ui.MUTED)
	ui.text_input(page, "Search", "sb.filter", "lobby or host name")
	ui.buttons(page, [["Refresh", refresh]])
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 4)
	page.add_child(_list_box)

	ui.header(page, "Join by room ID")
	ui.text_input(page, "Room ID", "sb.code", "18-digit room ID")
	ui.buttons(page, [
		["Paste", paste_code],
		["Join", func() -> void: join_by_code(str(app.cfg.val("sb.code", "")))],
	])
	ui.note(page, "Works for private lobbies too - the host copies the room ID from their lobby screen or with the button below.")

	ui.header(page, "Your lobby")
	ui.live(page, _lobby_line)
	ui.buttons(page, [["Copy room ID", copy_room_id]])
	ui.text_input(page, "Lobby name", "sb.name", "your name's lobby")
	ui.spin(page, "Max players", "sb.max", 1, 8,
		"Capped at the game's own player limit (4).")
	ui.check(page, "Allow joining mid-match", "sb.mid",
		"Off: the lobby drops off the browser while a match is running.")
	ui.buttons(page, [
		["Make lobby public", publish, "Lists your lobby in the server browser. Press again to update the name / max players."],
		["Make lobby private", unpublish, "Back to the game's normal friends-only lobby."],
	])
	ui.note(page, "Host only. Public lobbies show up for anyone running Viper Menu or MachineParty+; friends on the vanilla game can still join with the room ID.")
	ui.note(page, "Server browser and public lobbies adapted from MachineParty+ by J_axon and Krunk (MIT License).")
	_rebuild_list()


func _lobby_line() -> String:
	var id := room_id()
	if id <= 0:
		return "Not in an online lobby."
	if not app.g.is_host():
		return "Room ID: %d   |   You're a guest - only the host can make the lobby public." % id
	var pub := is_public()
	var listed := pub and str(steam().getLobbyData(id, KEY_JOIN)) == "1"
	var t := "Room ID: %d   |   %s" % [id, "Public" if pub else "Private (friends only)"]
	if pub:
		t += "   |   %s" % ("listed" if listed else "hidden (full or mid-match)")
	t += "   |   Max players here: %d" % player_cap()
	return t


func _rebuild_list() -> void:
	if _list_box == null or not is_instance_valid(_list_box) or _ui == null:
		return
	_ui.clear(_list_box)
	var q := str(app.cfg.val("sb.filter", "")).strip_edges().to_lower()
	var shown := 0
	for r in _results:
		if not q.is_empty() and not (str(r["name"]).to_lower().contains(q) or str(r["host"]).to_lower().contains(q)):
			continue
		shown += 1
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		_list_box.add_child(h)
		var l := Label.new()
		l.text = str(r["name"])
		if str(r["host"]) != "" and str(r["host"]) != str(r["name"]):
			l.text += "  -  " + str(r["host"])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		l.tooltip_text = l.text
		h.add_child(l)
		var info := Label.new()
		info.text = "%d/%d  %s" % [r["players"], r["max"], "in match" if r["state"] == "ingame" else "in lobby"]
		info.add_theme_color_override("font_color", _ui.MUTED)
		h.add_child(info)
		var b: Button = _ui.button(h, "Join", join.bind(int(r["id"])))
		if int(r["id"]) == room_id():
			b.disabled = true
			b.text = "Here"
		elif not r["compatible"]:
			b.disabled = true
			b.tooltip_text = "Different game version (%s)" % r["version"]
		elif r["full"]:
			b.disabled = true
			b.tooltip_text = "Full"
	if shown == 0:
		_ui.note(_list_box, "No public lobbies right now." if q.is_empty() else "No lobbies match your search.")
