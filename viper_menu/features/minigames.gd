extends Node

## Minigame control (host): force-start, a custom queue that slots into the
## game's own rotation, per-game round counts, and "play now".
##
## How the queue works: the game always plays session_minigame_list[0] next and
## deletes it when that game ends. We insert our next queued game at the front
## right after a game ends (MinigameEnd) or when the picker starts
## (MinigamePick - the picker waits 1s before reading the list). When the queue
## is empty nothing is inserted, so the normal rotation simply carries on.

var app = null

var _game: Node = null
var _override_active := false
var _saved_custom = null
var _inserted_this_cycle := false


func setup() -> void:
	app.cfg.def("mg.force_single", false)
	app.cfg.def("mg.pick", -1)
	app.cfg.def("mg.rounds", 1)
	app.cfg.def("mg.queue", [])
	app.cfg.def("mg.endless", false)


# --- minigame names --------------------------------------------------------------

func ids() -> Dictionary:
	return app.g.autoload_enum("Globals", "MinigameIdentifier")


func name_of(id: int) -> String:
	var gl: Node = app.g.al("Globals")
	var names = app.g.gv(gl, "MinigameReadableNames", null)
	if not (names is Dictionary):
		names = app.g.script_consts(gl).get("MinigameReadableNames", {})
	if names is Dictionary and names.has(id):
		var t := tr(str(names[id]))
		if not t.is_empty() and not t.begins_with("LOC_"):
			return t
	for k in ids().keys():
		if int(ids()[k]) == id:
			return str(k).capitalize()
	return "Minigame %d" % id


func _minigame_items() -> Array:
	var out: Array = []
	var e := ids()
	for k in e.keys():
		var id := int(e[k])
		if str(k) == "EMPTY":
			continue
		out.append([id, "%s  (%s)" % [name_of(id), k]])
	return out


# --- state machine hook -------------------------------------------------------------

func _process(_delta: float) -> void:
	if bool(app.cfg.val("mg.force_single", false)):
		var gl: Node = app.g.al("Globals")
		if gl != null and ("allow_singleplayer" in gl) and not gl.get("allow_singleplayer"):
			gl.set("allow_singleplayer", true)

	var gm: Node = app.g.game()
	if gm != _game:
		_game = gm
		_override_active = false
		_saved_custom = null
		if gm != null:
			var sm = gm.get("state_machine")
			if app.g.valid(sm) and sm.has_signal("state_changed"):
				sm.state_changed.connect(_on_state_changed)


func _on_state_changed(state_name) -> void:
	if not app.g.is_host() or _game == null or not is_instance_valid(_game):
		return
	var st := str(state_name)
	if st == "MinigameEnd":
		_restore_round_override()
		_inserted_this_cycle = false
		var list = _game.get("session_minigame_list")
		if list is Array and list.is_empty():
			if not queue().is_empty():
				_apply_next()
				_inserted_this_cycle = true
			elif bool(app.cfg.val("mg.endless", false)):
				_refill_rotation()
	elif st == "MinigamePick":
		if _inserted_this_cycle:
			_inserted_this_cycle = false
			return
		if not queue().is_empty():
			_apply_next()


func queue() -> Array:
	var q = app.cfg.val("mg.queue", [])
	return q if q is Array else []


func _set_queue(q: Array) -> void:
	app.cfg.put("mg.queue", q)
	_refresh_list()


func _apply_next() -> void:
	var q := queue().duplicate(true)
	if q.is_empty():
		return
	var entry = q.pop_front()
	_set_queue(q)
	var id := int(entry[0])
	var rounds := maxi(1, int(entry[1]))
	_put_front(id, rounds)
	app.note("queue: up next is %s (%d round%s)" % [name_of(id), rounds, "" if rounds == 1 else "s"])


func _put_front(id: int, rounds: int) -> void:
	var list = _game.get("session_minigame_list")
	if not (list is Array):
		return
	list.insert(0, id)
	var rd = _game.get("session_minigame_rounds")
	if rd is Dictionary:
		rd[id] = rounds
	_round_override(rounds)
	_sync_playlist()


func _sync_playlist() -> void:
	if not app.g.has_peer() or not _game.has_method("update_playlist_state_rpc"):
		return
	_game.rpc("update_playlist_state_rpc", _game.get("session_minigame_list"),
		int(app.g.gv(_game, "session_next_minigame_index", 0)),
		int(app.g.gv(_game, "session_next_minigame_identifier", 0)))


## Outside custom games the game takes round counts from its own per-player-count
## table. Flagging the session as custom while a queued game plays makes it use
## our number instead; the flag is put back when that game ends.
func _round_override(_rounds: int) -> void:
	var gmgr: Node = app.g.al("GameManager")
	if gmgr == null or not ("custom_game" in gmgr):
		return
	if not _override_active:
		_saved_custom = gmgr.get("custom_game")
		_override_active = true
	gmgr.set("custom_game", true)


func _restore_round_override() -> void:
	if not _override_active:
		return
	var gmgr: Node = app.g.al("GameManager")
	if gmgr != null and _saved_custom != null:
		gmgr.set("custom_game", _saved_custom)
	_override_active = false
	_saved_custom = null


func _refill_rotation() -> void:
	var gl: Node = app.g.al("Globals")
	var dp = app.g.gv(gl, "default_playlist", [])
	var sp = app.g.gv(gl, "session_playlist", [])
	var src: Array = sp if (sp is Array and not sp.is_empty()) else dp
	var list = _game.get("session_minigame_list")
	var rd = _game.get("session_minigame_rounds")
	for mlr in src:
		var id := int(app.g.gv(mlr, "game_identifier", -1))
		if id < 0:
			continue
		list.append(id)
		if rd is Dictionary and not rd.has(id):
			rd[id] = maxi(1, int(app.g.gv(mlr, "total_rounds", 1)))
	var played = _game.get("session_minigame_played_list")
	if played is Array:
		played.clear()
	_sync_playlist()
	app.note("endless: rotation refilled with %d games" % list.size())


# --- actions --------------------------------------------------------------------------

func add_to_queue(front: bool = false) -> void:
	var id := int(app.cfg.val("mg.pick", -1))
	if id < 0:
		app.note("pick a minigame first")
		return
	var q := queue().duplicate(true)
	var entry := [id, maxi(1, int(app.cfg.val("mg.rounds", 1)))]
	if front:
		q.insert(0, entry)
	else:
		q.append(entry)
	_set_queue(q)


func play_now() -> void:
	var id := int(app.cfg.val("mg.pick", -1))
	var gm: Node = app.g.game()
	if id < 0 or gm == null:
		app.note("play now: pick a minigame and be in a game session")
		return
	if not app.g.is_host():
		app.note("play now: host only")
		return
	_game = gm
	var rounds := maxi(1, int(app.cfg.val("mg.rounds", 1)))
	var list = gm.get("session_minigame_list")
	if list is Array:
		list.insert(0, id)
	var rd = gm.get("session_minigame_rounds")
	if rd is Dictionary:
		rd[id] = rounds
	gm.set("session_minigame_index", 0)
	gm.set("session_next_minigame_identifier", id)
	_round_override(rounds)
	_sync_playlist()
	# Hide the intermission screens on everyone, like the game's dev panel does.
	var dt: Node = app.g.al("DebugTools")
	if dt != null and dt.has_method("hide_intermission_related_rpc") and app.g.valid(dt.get("game_instance")):
		dt.rpc("hide_intermission_related_rpc")
	var loaded = gm.get("minigame_players_loaded")
	if loaded is Array:
		loaded.clear()
	gm.load_minigame(id, false, rounds)
	app.note("loading %s now" % name_of(id))


func force_start() -> void:
	if not app.g.is_host():
		app.note("force-start: host only")
		return
	var lobby: Node = app.g.lobby_scene()
	if lobby != null:
		if app.g.player_ids().size() <= 1:
			app.cfg.put("mg.force_single", true)
			var gl: Node = app.g.al("Globals")
			app.g.sv(gl, "allow_singleplayer", true)
		lobby.rpc("start_game_rpc")
		app.note("starting the game")
		return
	var gm: Node = app.g.game()
	if gm != null:
		var im = gm.get("intermission_manager")
		var br = app.g.gv(im, "screen_briefing", null)
		if app.g.valid(br) and bool(app.g.gv(br, "active", false)):
			var ready = br.get("players_ready")
			if ready is Dictionary and not ready.is_empty():
				for pid in ready.keys():
					br.rpc("set_ready_rpc", int(pid), true)
				app.note("marked everyone ready")
				return
	app.note("nothing to force-start right now (works in the lobby or on the briefing screen)")


# --- UI ---------------------------------------------------------------------------------

var _list: ItemList = null


func build_ui(ui, page) -> void:
	ui.header(page, "Start")
	ui.buttons(page, [["Force-start game", force_start,
		"Lobby: starts even if the Start button is greyed out. Briefing screen: marks everyone ready."]])
	ui.check(page, "Force-start single player", "mg.force_single",
		"Keeps Globals.allow_singleplayer on so you can start and play alone. Turn it on before starting the game.")
	ui.note(page, "Playing alone: the game ends multi-round minigames after one round when fewer than 2 players are in.")

	ui.header(page, "Pick a minigame")
	ui.option_dynamic(page, "Minigame", "mg.pick", _minigame_items)
	ui.spin(page, "Rounds", "mg.rounds", 1, 10, "How many rounds it plays when it comes up from the queue.")
	ui.buttons(page, [
		["Add to queue", add_to_queue.bind(false)],
		["Play next", add_to_queue.bind(true), "Adds it to the front of your queue."],
		["Play now", play_now, "Host: loads it immediately, skipping the intermission (like the game's dev panel). Can leave intermission visuals a little off."],
	])

	ui.header(page, "Custom queue")
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 130)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.select_mode = ItemList.SELECT_SINGLE
	page.add_child(_list)
	ui.buttons(page, [
		["Up", _move.bind(-1)],
		["Down", _move.bind(1)],
		["Remove", _remove_selected],
		["Clear", func() -> void: _set_queue([])],
	])
	ui.note(page, "Queued games play next, in order, using the rounds you picked. When the queue is empty the game carries on with its normal rotation. Host only; works with friends on the vanilla game.")
	ui.check(page, "Endless session", "mg.endless",
		"When the rotation runs out, refill it instead of ending the session.")

	ui.header(page, "Default rotation (up next)")
	ui.live(page, _rotation_text, ui.MUTED)
	_refresh_list()
	app.cfg.reloaded.connect(_refresh_list)
	app.cfg.changed.connect(func(key: String, _v) -> void:
		if key == "mg.queue":
			_refresh_list()
	)


func _rotation_text() -> String:
	var gm: Node = app.g.game()
	if gm == null:
		return "Not in a game session."
	var list = gm.get("session_minigame_list")
	if not (list is Array) or list.is_empty():
		return "Rotation is empty - the session ends after this game."
	var names: Array = []
	for id in list:
		names.append(name_of(int(id)))
	return ", ".join(names)


func _refresh_list() -> void:
	if _list == null or not is_instance_valid(_list):
		return
	var sel := _list.get_selected_items()
	_list.clear()
	var q := queue()
	for i in q.size():
		var e = q[i]
		_list.add_item("%d.  %s   x%d" % [i + 1, name_of(int(e[0])), int(e[1])])
	if sel.size() > 0 and sel[0] < q.size():
		_list.select(sel[0])


func _move(dir: int) -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return
	var i: int = sel[0]
	var j := i + dir
	var q := queue().duplicate(true)
	if j < 0 or j >= q.size():
		return
	var tmp = q[i]
	q[i] = q[j]
	q[j] = tmp
	_set_queue(q)
	_list.select(j)


func _remove_selected() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return
	var q := queue().duplicate(true)
	q.remove_at(sel[0])
	_set_queue(q)


func shutdown() -> void:
	_restore_round_override()
