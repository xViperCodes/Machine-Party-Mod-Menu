extends Node

## Session tab (host): score editor, skip / restart / end, pick the Duck Hunt hunter.

var app = null

# score editor
var _base_multiplier := -1
var _score_box: VBoxContainer = null
var _score_sig := ""
var _ui = null

# duck hunt hunter
var _dh_mg: Node = null
var _dh_pool: Array = []        # ids still due to hunt this game, in our own bookkeeping
var _dh_last_hunter := -1


func setup() -> void:
	app.cfg.def("sess.step", 85)
	app.cfg.def("sess.mult", 1)
	app.cfg.def("sess.hunter", -1)
	app.cfg.def("sess.hunter_every", false)
	app.cfg.changed.connect(func(key: String, _v) -> void:
		if key == "sess.mult":
			_apply_multiplier()
	)


func shutdown() -> void:
	var gm: Node = app.g.game()
	if gm != null and _base_multiplier > 0:
		gm.set("score_multiplier", _base_multiplier)


func _host_game() -> Node:
	if not app.g.is_host():
		app.note("host only")
		return null
	var gm: Node = app.g.game()
	if gm == null:
		app.note("not in a game session")
	return gm


# ==== scores =========================================================================

func scores() -> Dictionary:
	var gm: Node = app.g.game()
	var d = app.g.gv(gm, "total_score_by_network_id", {})
	return d if d is Dictionary else {}


func add_score(id: int, amount: int) -> void:
	var gm := _host_game()
	if gm == null:
		return
	var total = gm.get("total_score_by_network_id")
	if not (total is Dictionary):
		return
	total[id] = maxi(0, int(total.get(id, 0)) + amount)
	_push_scores(gm)


func set_score(id: int, value: int) -> void:
	var gm := _host_game()
	if gm == null:
		return
	var total = gm.get("total_score_by_network_id")
	if total is Dictionary:
		total[id] = maxi(0, value)
		_push_scores(gm)


func reset_scores() -> void:
	var gm := _host_game()
	if gm == null:
		return
	for dict_name in ["total_score_by_network_id", "game_score_by_network_id", "round_score_by_network_id"]:
		var d = gm.get(dict_name)
		if d is Dictionary:
			for k in d.keys():
				d[k] = 0
	_push_scores(gm)
	app.note("all scores reset")


## Send the new totals to everyone and refresh the intermission scoreboard.
func _push_scores(gm: Node) -> void:
	var total = gm.get("total_score_by_network_id")
	var game_scores = gm.get("game_score_by_network_id")
	if gm.has_method("receive_scores_rpc"):
		app.g._rpc(gm, "receive_scores_rpc", [total, game_scores if game_scores is Dictionary else {}])
	var im = gm.get("intermission_manager")
	if app.g.valid(im) and im.has_method("synchronise_total_score_by_network_id"):
		app.g._rpc(im, "synchronise_total_score_by_network_id", [total])
	var br = app.g.gv(im, "screen_briefing", null)
	if app.g.valid(br) and br.has_method("update_player_data_rpc"):
		app.g._rpc(br, "update_player_data_rpc", [total])
	_score_sig = ""


## Every minigame point is multiplied by Game.score_multiplier (85 by default).
func _apply_multiplier() -> void:
	var gm: Node = app.g.game()
	if gm == null or not app.g.is_host() or not ("score_multiplier" in gm):
		return
	if _base_multiplier <= 0:
		_base_multiplier = int(gm.get("score_multiplier"))
	gm.set("score_multiplier", _base_multiplier * maxi(1, int(app.cfg.val("sess.mult", 1))))


# ==== skip / restart / end ===============================================================

func _game_state(gm: Node) -> String:
	return str(app.g.gv(gm, "state_machine.current_state.name", ""))


func _finished_state_name(mg: Node) -> String:
	var sm = mg.get("state_machine")
	if not app.g.valid(sm):
		return ""
	for c in sm.get_children():
		var n := str(c.name)
		if n.to_lower().begins_with("finish") or n == "GameFinished":
			return n
	return ""


## Ends the current round (or the whole minigame) through the minigame's own
## Finished state, so everyone sees the normal end screen and the game moves on.
func skip(whole_minigame: bool) -> void:
	var gm := _host_game()
	if gm == null:
		return
	var mg: Node = app.g.minigame()
	if mg == null or _game_state(gm) != "MinigamePlaying":
		app.note("skip: no minigame is being played right now")
		return
	var fin := _finished_state_name(mg)
	if fin == "":
		app.note("skip: this minigame has no Finished state")
		return
	if whole_minigame:
		# The game adds 1 and compares with the round count (which can come from
		# a per-player-count table), so push it well past any real count.
		gm.set("session_current_minigame_round", maxi(int(app.g.gv(gm, "session_current_minigame_max_rounds", 1)), 99))
	if mg.has_method("set_minigame_sfx_linear_volume_rpc"):
		app.g._rpc(mg, "set_minigame_sfx_linear_volume_rpc", [0.0])
	if mg.has_method("set_effects_visibility_rpc"):
		app.g._rpc(mg, "set_effects_visibility_rpc", [false])
	var sm = mg.get("state_machine")
	app.g._rpc(sm, "transition_to_rpc", [fin, {}, true])
	app.note("skipping %s" % ("the minigame" if whole_minigame else "this round"))


## What's loaded right now. Game.load_minigame writes Globals.current_minigame_identifier.
func current_minigame_id(gm: Node) -> int:
	var paths = app.g.gv(app.g.al("Globals"), "MinigamePaths", null)
	var cands: Array = [
		app.g.gv(app.g.al("Globals"), "current_minigame_identifier", null),
		app.g.gv(app.g.al("GameManager"), "current_minigame_identifier", null),
	]
	var list = app.g.gv(gm, "session_minigame_list", [])
	var idx := int(app.g.gv(gm, "session_minigame_index", -1))
	if list is Array and idx >= 0 and idx < list.size():
		cands.append(list[idx])
	for c in cands:
		if c == null:
			continue
		var id := int(c)
		if paths is Dictionary:
			if paths.has(id):
				return id
		elif paths is Array:
			if id >= 0 and id < paths.size() and str(paths[id]) != "":
				return id
		elif id > 0:
			return id
	return -1


func restart() -> void:
	var gm := _host_game()
	if gm == null:
		return
	var id := current_minigame_id(gm)
	if id < 0 or app.g.minigame() == null:
		app.note("restart: no minigame loaded")
		return
	var rounds := maxi(1, int(app.g.gv(gm, "session_current_minigame_max_rounds", 1)))
	var dt: Node = app.g.al("DebugTools")
	if dt != null and dt.has_method("hide_intermission_related_rpc") and app.g.valid(dt.get("game_instance")):
		app.g._rpc(dt, "hide_intermission_related_rpc", [])
	var loaded = gm.get("minigame_players_loaded")
	if loaded is Array:
		loaded.clear()
	gm.load_minigame(id, false, rounds)
	app.note("restarting %s" % app.mod("minigames").name_of(id))


## End after this minigame: empty the rest of the rotation (and the custom
## queue). End now: same, then skip the current minigame - or go straight to
## the session end screen if nothing is being played.
func end_session(now: bool) -> void:
	var gm := _host_game()
	if gm == null:
		return
	app.cfg.put("mg.queue", [])
	app.cfg.put("mg.endless", false)
	var list = gm.get("session_minigame_list")
	var playing := _game_state(gm) == "MinigamePlaying"
	if list is Array and list.size() > 1:
		# The front entry is the minigame being played (or already picked on
		# the intermission screen); the game still needs it, so keep it.
		var front = list[0]
		list.clear()
		list.append(front)
		app.mod("minigames")._game = gm
		app.mod("minigames")._sync_playlist()
	if not now:
		app.note("the session ends after this minigame")
		return
	if playing:
		skip(true)
	else:
		var sm = gm.get("state_machine")
		app.g._rpc(sm, "transition_to_rpc", ["SessionEnd", {}, true])
	app.note("ending the session")


# ==== Duck Hunt hunter ====================================================================

## The host picks each round's hunter with possible_hunters.shuffle() then
## pop_front(). Filling that list with the chosen player (same length, so the
## number of rounds doesn't change) makes the pick land on them.
func _process(_delta: float) -> void:
	if not app.g.is_host():
		return
	var mg: Node = app.g.minigame()
	if mg == null or app.g.cls(mg) != "DuckHuntMinigame":
		_dh_mg = null
		return
	var ph = mg.get("possible_hunters")
	if not (ph is Array):
		return
	if mg != _dh_mg:
		_dh_mg = mg
		_dh_pool = ph.duplicate()
		_dh_last_hunter = -1
	# A hunter just spawned: take them off our list of who still has to hunt.
	var h = mg.get("hunter_player")
	if app.g.valid(h):
		var hid := int(app.g.gv(h, "player_presence.network_id", -1))
		if hid != _dh_last_hunter and hid > 0:
			_dh_last_hunter = hid
			if _dh_pool.has(hid):
				_dh_pool.erase(hid)
			elif not _dh_pool.is_empty():
				_dh_pool.pop_front()
			if int(app.cfg.val("sess.hunter", -1)) == hid and not bool(app.cfg.val("sess.hunter_every", false)):
				app.cfg.put("sess.hunter", -1)
	# Drop players who left.
	var pres: Dictionary = app.g.presences()
	for id in _dh_pool.duplicate():
		if not pres.has(id):
			_dh_pool.erase(id)
	var want := int(app.cfg.val("sess.hunter", -1))
	var target: Array = []
	if want > 0 and pres.has(want):
		for i in _dh_pool.size():
			target.append(want)
	else:
		target = _dh_pool.duplicate()
	if ph != target:
		ph.clear()
		ph.append_array(target)


# ==== UI ===================================================================================

func build_ui(ui, page) -> void:
	_ui = ui
	ui.note(page, "Host tools. Everything here goes through the game's own functions, so friends on the vanilla game see the changes.")

	ui.header(page, "Scores")
	_score_box = VBoxContainer.new()
	_score_box.add_theme_constant_override("separation", 4)
	page.add_child(_score_box)
	ui.slider(page, "Step", "sess.step", 1, 500, 1, "How much the - / + buttons change a score. One minigame point is worth 85 by default.")
	ui.slider(page, "Points multiplier", "sess.mult", 1, 5, 1, "Multiplies every point scored from now on (x2 = double points).")
	ui.buttons(page, [["Reset all scores to 0", reset_scores]])

	ui.header(page, "Skip, restart or end")
	ui.buttons(page, [
		["Skip round", skip.bind(false), "Ends the current round now; the next round starts as normal."],
		["Skip minigame", skip.bind(true), "Ends the minigame now, with the scores so far."],
		["Restart minigame", restart, "Reloads the current minigame from round 1."],
	])
	ui.buttons(page, [
		["End after this minigame", end_session.bind(false), "Clears the rest of the rotation and your queue."],
		["End session now", end_session.bind(true), "Skips to the final results."],
	])
	ui.live(page, func() -> String:
		var gm: Node = app.g.game()
		if gm == null:
			return "Not in a game session."
		return "State: %s   |   Round %d of %d" % [_game_state(gm), int(app.g.gv(gm, "session_current_minigame_round", 0)), int(app.g.gv(gm, "session_current_minigame_max_rounds", 0))], ui.MUTED)

	ui.header(page, "Duck Hunt hunter")
	ui.option_dynamic(page, "Next hunter", "sess.hunter", _hunter_items,
		"Who gets the rifle next round. Random keeps the game's normal rotation.")
	ui.check(page, "Keep them as hunter every round", "sess.hunter_every",
		"Off: only the next round, then back to the normal rotation.")
	ui.live(page, func() -> String:
		if app.g.minigame_cls() != "DuckHuntMinigame":
			return "Takes effect when Duck Hunt starts (set it before or during the game)."
		var names: Array = []
		for id in _dh_pool:
			names.append(app.g.player_name(int(id)))
		return "Still due to hunt: " + (", ".join(names) if not names.is_empty() else "nobody (last round)"), ui.MUTED)
	_rebuild_scores()


func _hunter_items() -> Array:
	var out: Array = [[-1, "Random (normal)"]]
	for id in app.g.presences().keys():
		out.append([int(id), app.g.player_name(int(id))])
	return out


func _physics_process(_delta: float) -> void:
	if _score_box == null or not app.ui.is_open or app.ui.current_tab != "Session":
		return
	var parts: Array = []
	var sc := scores()
	for id in sc.keys():
		parts.append("%s:%s" % [id, sc[id]])
	var sig := ",".join(parts) + str(app.g.is_host())
	if sig != _score_sig:
		_score_sig = sig
		_rebuild_scores()


func _rebuild_scores() -> void:
	if _score_box == null or not is_instance_valid(_score_box) or _ui == null:
		return
	_ui.clear(_score_box)
	var sc := scores()
	if sc.is_empty():
		_ui.note(_score_box, "Scores show up once a game session starts.")
		return
	var ids: Array = sc.keys()
	ids.sort_custom(func(a, b) -> bool: return int(sc[a]) > int(sc[b]))
	for id in ids:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		_score_box.add_child(h)
		var l := Label.new()
		l.text = app.g.player_name(int(id))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		h.add_child(l)
		var v := Label.new()
		v.text = str(sc[id])
		v.custom_minimum_size = Vector2(70, 0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(v)
		if app.g.is_host():
			_ui.button(h, "  -  ", func() -> void: add_score(int(id), -int(app.cfg.val("sess.step", 85))))
			_ui.button(h, "  +  ", func() -> void: add_score(int(id), int(app.cfg.val("sess.step", 85))))
			_ui.button(h, "0", set_score.bind(int(id), 0), "Set to 0")
