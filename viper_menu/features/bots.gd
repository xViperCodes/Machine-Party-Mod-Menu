extends Node

## Bots (beta, host only). A bot is an extra player presence with no network
## peer behind it: minigames spawn a character for it, and it stands still.
## The host answers the "I've loaded / I'm ready / I saw my role" handshakes on
## its behalf so sessions don't stall waiting for it.
##
## Known limits: a bot never plays, and a minigame that waits for every player
## to do something the mod doesn't answer for can stall - remove the bot then.

var app = null

const BASE_ID := 2000000000

var bots: Dictionary = {}          # id -> name
var _next := 1
var _acked: Dictionary = {}        # "<minigame instance>:<id>:<what>" -> true
var _list_box: VBoxContainer = null
var _ui = null
var _last_mg: Node = null


func setup() -> void:
	app.cfg.def("bots.name", "Bot")


func is_bot(id: int) -> bool:
	return bots.has(id)


func bot_name(id: int) -> String:
	return str(bots.get(id, ""))


func shutdown() -> void:
	remove_all()


# --- add / remove ------------------------------------------------------------------

func add_bot() -> void:
	if not app.g.is_host():
		app.note("bots: host only")
		return
	var gm: Node = app.g.game()
	if gm == null:
		app.note("bots: start the game first - add bots from the intermission screen")
		return
	var pm: Node = app.g.al("PlayerManager")
	if pm == null or not pm.has_method("add_player"):
		app.note("bots: PlayerManager.add_player not found")
		return
	var id := BASE_ID + _next
	_next += 1
	var nm := str(app.cfg.val("bots.name", "Bot")).strip_edges()
	if nm.is_empty():
		nm = "Bot"
	if bots.values().has(nm):
		nm = "%s %d" % [nm, _next - 1]
	var custom: Array = ["", "", ""]
	var me = app.g.presences().get(app.g.my_id(), null)
	if app.g.valid(me) and me.get("customization") is Array:
		custom = me.get("customization").duplicate()
	var presence = pm.call("add_player", id, custom)
	if not app.g.valid(presence):
		app.note("bots: add_player failed")
		return
	bots[id] = nm
	app.g.sv(presence, "network_name", nm)
	if pm.has_method("propagate_player_rpc"):
		pm.rpc("propagate_player_rpc", id, presence.get_path())
	for dict_name in ["total_score_by_network_id", "game_score_by_network_id", "round_score_by_network_id"]:
		var d = gm.get(dict_name)
		if d is Dictionary and not d.has(id):
			d[id] = 0
	_refresh_scoreboard(gm)
	app.note("added bot '%s' (beta) - it joins from the next minigame" % nm)
	_rebuild_list()


func remove_bot(id: int) -> void:
	if not bots.has(id):
		return
	var nm: String = bots[id]
	bots.erase(id)
	var gm: Node = app.g.game()
	var mg: Node = app.g.minigame()
	if app.g.valid(mg) and mg.has_method("player_disconnected"):
		mg.player_disconnected(id)
	var pm: Node = app.g.al("PlayerManager")
	if pm != null and pm.has_method("remove_player_rpc") and app.g.is_host():
		pm.rpc("remove_player_rpc", id)
	if gm != null:
		for dict_name in ["total_score_by_network_id", "game_score_by_network_id", "round_score_by_network_id"]:
			var d = gm.get(dict_name)
			if d is Dictionary:
				d.erase(id)
		_refresh_scoreboard(gm)
	app.note("removed bot '%s'" % nm)
	_rebuild_list()


func remove_all() -> void:
	for id in bots.keys().duplicate():
		remove_bot(int(id))


func _refresh_scoreboard(gm: Node) -> void:
	var br = app.g.gv(gm, "intermission_manager.screen_briefing", null)
	if app.g.valid(br) and br.has_method("update_player_data_rpc"):
		br.rpc("update_player_data_rpc", gm.get("total_score_by_network_id"))


# --- answering handshakes for bots -------------------------------------------------

func _process(_delta: float) -> void:
	if bots.is_empty() or not app.g.is_host():
		return
	var gm: Node = app.g.game()
	if gm == null:
		bots.clear()
		return
	var mg: Node = app.g.minigame()
	if mg != _last_mg:
		_last_mg = mg
		_acked.clear()
	if app.g.valid(mg):
		var key := str(mg.get_instance_id())
		var loaded = mg.get("players_loaded")
		for id in bots.keys():
			# Minigame waits for every presence to report it loaded.
			if loaded is Array and not loaded.has(id) and not _acked.has(key + ":%d:load" % id):
				_acked[key + ":%d:load" % id] = true
				_ack_load.call_deferred(mg, id)
			# Duck Hunt waits for every player to acknowledge their role.
			if mg.has_method("acknowledge_role_rpc") and mg.get("players_acknowledged") is Array:
				var acks: Array = mg.get("players_acknowledged")
				if not acks.has(id) and app.g.valid(mg.get("hunter_player")) and not _acked.has(key + ":%d:role" % id):
					_acked[key + ":%d:role" % id] = true
					mg.acknowledge_role_rpc(id)
	# Intermission briefing waits for everyone to press Ready.
	var br = app.g.gv(gm, "intermission_manager.screen_briefing", null)
	if app.g.valid(br) and bool(app.g.gv(br, "active", false)):
		var ready = br.get("players_ready")
		if ready is Dictionary:
			for id in bots.keys():
				if ready.has(id) and not ready[id]:
					br.rpc("set_ready_rpc", int(id), true)


func _ack_load(mg: Node, id: int) -> void:
	await get_tree().create_timer(0.5).timeout
	if app.g.valid(mg) and mg.has_method("player_loaded"):
		mg.player_loaded(id)


# --- UI -------------------------------------------------------------------------------

func build_ui(ui, page) -> void:
	_ui = ui
	ui.note(page, "BETA - bots may make the game crash or get stuck. Host only. Add them on the intermission screen; they join from the next minigame and stand still. If a minigame hangs waiting for a bot, remove it.", ui.WARN)
	ui.header(page, "Add bot")
	ui.text_input(page, "Bot name", "bots.name", "Bot")
	ui.buttons(page, [["Add bot", add_bot], ["Remove all bots", remove_all]])
	ui.header(page, "Bots loaded")
	_list_box = VBoxContainer.new()
	page.add_child(_list_box)
	_rebuild_list()


func _rebuild_list() -> void:
	if _list_box == null or not is_instance_valid(_list_box) or _ui == null:
		return
	_ui.clear(_list_box)
	if bots.is_empty():
		_ui.note(_list_box, "No bots.")
		return
	for id in bots.keys():
		var h := HBoxContainer.new()
		_list_box.add_child(h)
		var l := Label.new()
		l.text = "%s   (id %d)" % [bots[id], id]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		_ui.button(h, "Remove", remove_bot.bind(int(id)))
