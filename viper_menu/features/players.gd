extends Node

## Players: list, teleports, shove / freeze / smite, kick.
## Teleports use each minigame player's own teleport_rpc (any_peer, call_local),
## so moving other people works even though they run the vanilla game.

var app = null

var _list_box: VBoxContainer = null
var _list_sig := ""
var _blocked_steam_ids: Array = []
var _nm_connected := false

## Objects worth moving with "teleport items / entities" (by script class).
const ENTITY_CLASSES := [
	"ExplodingCollarRaceMine", "ExplodingCollarRaceHarvester",
	"ManufactureGunItem", "JunkCubeRigidbody", "ForkliftCertifiedCrate",
	"KnifeAtTheOfficeSearchable", "SpineBreakerDevice", "DvdRoombaRoomba",
	"ChiselGauntletCubeSegment",
]

## Smite = each minigame's own death call (all are any_peer RPCs that report
## the death to the host's game logic). [method, argument kind]
const SMITE := {
	"DuckHuntDuckPlayer": ["shot_rpc", "dmg"],
	"DiscoDodgePlayer": ["fall_rpc", ""],
	"DvdRoombaPlayer": ["kill_rpc", ""],
	"TrainRacePlayer": ["kill_rpc", ""],
	"ExplodingCollarRacePlayer": ["explode_rpc", "dmg"],
	"JunkPlatformPlayer": ["fall_rpc", ""],
	"KnifeAtTheOfficePlayer": ["kill_rpc", "me"],
	"ScavangerChairsPlayer": ["kill_rpc", "chairs"],
	"ManufactureGunPlayer": ["kill_rpc", "me"],
	"GreenPeaPlayer": ["execute_rpc", ""],
	"MemorizePathPlayer": ["damage_rpc", "instant"],
	"EscalatorPitPlayer": ["kill_rpc", ""],
}

var _frozen: Dictionary = {}     # network id -> Vector3 freeze point
var _freeze_t := 0.0
var _freeze_mg: Node = null


func setup() -> void:
	app.cfg.def("pl.target", -1)
	app.cfg.def("pl.block_rejoin", true)
	app.cfg.def("pl.kick_target", -1)
	app.cfg.def("pl.entity_radius", 2.0)
	app.hk.register("tp_all_to_me", "Teleport all players to me", app.hk.kb(KEY_HOME), "Players")
	app.hk.register("tp_items_to_target", "Teleport items & entities to chosen player", app.hk.kb(KEY_PAGEUP), "Players")
	app.hk.register("shove_target", "Shove chosen player", app.hk.unbound(), "Players")
	app.hk.register("freeze_target", "Freeze / unfreeze chosen player", app.hk.unbound(), "Players")
	app.hk.register("smite_target", "Smite chosen player", app.hk.unbound(), "Players")
	app.cfg.def("pl.shove_strength", 1.5)
	app.cfg.def("pl.shove_dist", 5.0)
	app.hk.pressed.connect(_on_hotkey)


func _on_hotkey(id: String) -> void:
	match id:
		"tp_all_to_me":
			tp_all_to_me()
		"tp_items_to_target":
			tp_entities_to(target_id())
		"shove_target", "freeze_target", "smite_target":
			var t := int(app.cfg.val("pl.target", -1))
			if t <= 0 or t == app.g.my_id():
				app.note("pick a target player first (Players > Chosen player)")
				return
			match id:
				"shove_target":
					shove(t)
				"freeze_target":
					toggle_freeze(t)
				"smite_target":
					smite(t)


func target_id() -> int:
	var t := int(app.cfg.val("pl.target", -1))
	return t if t > 0 else app.g.my_id()


func _process(_delta: float) -> void:
	if not _nm_connected:
		var nm: Node = app.g.al("NetworkManager")
		if nm != null and nm.has_signal("on_peer_connected"):
			nm.on_peer_connected.connect(_on_peer_connected)
			_nm_connected = true
	_tick_freeze(_delta)
	if app.ui.is_open and app.ui.current_tab == "Players":
		var sig := _signature()
		if sig != _list_sig:
			_list_sig = sig
			_rebuild_list()


# --- actions -----------------------------------------------------------------------

func tp_me_to(id: int) -> void:
	var me: Node3D = app.g.my_char()
	var them: Node3D = app.g.char_of(id)
	if me == null or them == null:
		app.note("teleport: both characters need to be in the current minigame")
		return
	app.g.teleport(me, them.global_position + Vector3(0.8, 0.0, 0.0))


func tp_to_me(id: int) -> void:
	var me: Node3D = app.g.my_char()
	var them: Node3D = app.g.char_of(id)
	if me == null or them == null:
		app.note("teleport: both characters need to be in the current minigame")
		return
	if not them.has_method("teleport_rpc") and not app.g.is_mine(them):
		app.note("this minigame has no teleport for other players")
		return
	app.g.teleport(them, me.global_position + Vector3(0.8, 0.0, 0.0))


func tp_all_to_me() -> void:
	var me: Node3D = app.g.my_char()
	if me == null:
		app.note("teleport: you have no character in this minigame")
		return
	var others: Array = []
	var chars: Dictionary = app.g.characters()
	for id in chars.keys():
		if int(id) != app.g.my_id():
			others.append(chars[id])
	for i in others.size():
		app.g.teleport(others[i], app.g.ring(me.global_position, i, others.size(), 1.4))
	app.note("pulled %d player(s) to you" % others.size())


func tp_entities_to(id: int) -> void:
	var target: Node3D = app.g.char_of(id)
	if target == null:
		app.note("teleport items: that player has no character here")
		return
	var root: Node = app.g.minigame()
	var things: Array = []
	for n in app.g.descendants(root):
		if not (n is Node3D) or n == target or target.is_ancestor_of(n):
			continue
		if ENTITY_CLASSES.has(app.g.cls(n)) or n is RigidBody3D:
			if "player_presence" in n:
				continue
			things.append(n)
	var r := float(app.cfg.val("pl.entity_radius", 2.0))
	for i in things.size():
		app.g.teleport(things[i], app.g.ring(target.global_position + Vector3.UP * 0.5, i, things.size(), r))
	if not app.g.is_host():
		app.note("moved %d object(s) locally - only the host's moves stick for objects the host owns" % things.size())
	else:
		app.note("moved %d object(s) to %s" % [things.size(), app.g.player_name(id)])


# --- shove / freeze / smite -----------------------------------------------------------

func _dir_from_me(target: Node3D) -> Vector3:
	var me: Node3D = app.g.my_char()
	var d := Vector3.ZERO
	if me != null and me != target:
		d = target.global_position - me.global_position
	d.y = 0.0
	if d.length() < 0.05:
		var a := randf() * TAU
		d = Vector3(cos(a), 0.0, sin(a))
	return d.normalized()


## Knock a player away from you with the minigame's own shove / bump / hit.
## Minigames without one get a short teleport "launch" instead.
func shove(id: int) -> void:
	var t: Node3D = app.g.char_of(id)
	if t == null:
		app.note("shove: that player has no character in this minigame")
		return
	var dir := _dir_from_me(t)
	var me: Node3D = app.g.my_char()
	var tp: Vector3 = t.global_position
	var from: Vector3 = me.global_position if me != null and me != t else tp - dir * 1.5
	var strength := float(app.cfg.val("pl.shove_strength", 1.5))
	var done := true
	match app.g.cls(t):
		"DiscoDodgePlayer":
			t.set("shoved", false)
			app.g._rpc(t, "shoved_rpc", [tp, from, dir])
		"DvdRoombaPlayer":
			t.set("shoved", false)
			app.g._rpc(t, "shoved_rpc", [tp, from, dir, me.get_path() if me != null else t.get_path(), app.g.my_id(), strength])
		"TrainRacePlayer":
			if me is PhysicsBody3D and me != t:
				t.set("shoved", false)
				app.g._rpc(t, "shoved_rpc", [tp, from, dir, me.get_path(), strength])
			else:
				done = false
		"ScavangerChairsPlayer":
			t.set("shoved", false)
			app.g._rpc(t, "shoved_rpc", [from])
		"JunkPlatformPlayer":
			t.set("is_hit", false)
			app.g._rpc(t, "hit_by_junk_rpc", [from, true, app.g.my_id()])
		"DuckHuntDuckPlayer", "MemorizePathPlayer", "ExplodingCollarRacePlayer":
			for i in int(ceil(strength * 2.0)):
				app.g._rpc(t, "bump_rpc", [dir])
		_:
			done = false
	if not done:
		if t.has_method("teleport_rpc"):
			app.g.teleport(t, tp + dir * float(app.cfg.val("pl.shove_dist", 5.0)))
		else:
			app.note("shove: this minigame has no way to move other players")
			return
	app.note("shoved " + app.g.player_name(id))


func can_smite(id: int) -> bool:
	var t: Node3D = app.g.char_of(id)
	return t != null and SMITE.has(app.g.cls(t))


func smite(id: int) -> void:
	var t: Node3D = app.g.char_of(id)
	if t == null:
		app.note("smite: that player has no character in this minigame")
		return
	var c: String = app.g.cls(t)
	if not SMITE.has(c):
		app.note("smite: no kill in %s (its eliminations are decided by the game itself)" % app.g.minigame_cls())
		return
	var spec: Array = SMITE[c]
	var args: Array = []
	match str(spec[1]):
		"dmg":
			args = [99]
		"me":
			args = [app.g.my_id()]
		"chairs":
			args = [true, true]
		"instant":
			args = [true]
	if t.has_method(spec[0]):
		app.g._rpc(t, spec[0], args)
		app.note("smote " + app.g.player_name(id))


func smite_all_others() -> void:
	for id in app.g.characters().keys():
		if int(id) != app.g.my_id():
			smite(int(id))


func is_frozen(id: int) -> bool:
	return _frozen.has(id)


func toggle_freeze(id: int) -> void:
	if _frozen.has(id):
		_frozen.erase(id)
		app.note("unfroze " + app.g.player_name(id))
		return
	var t: Node3D = app.g.char_of(id)
	if t == null:
		app.note("freeze: that player has no character in this minigame")
		return
	if not t.has_method("teleport_rpc") and not app.g.is_mine(t):
		app.note("freeze: this minigame has no way to move other players")
		return
	_frozen[id] = t.global_position
	app.note("froze " + app.g.player_name(id))


func freeze_all_others() -> void:
	for id in app.g.characters().keys():
		if int(id) != app.g.my_id() and not _frozen.has(int(id)):
			toggle_freeze(int(id))


func unfreeze_all() -> void:
	_frozen.clear()
	app.note("unfroze everyone")


## Pull frozen players back to their spot whenever they drift. Throttled so we
## don't flood the network with teleports.
func _tick_freeze(delta: float) -> void:
	var mg: Node = app.g.minigame()
	if mg != _freeze_mg:
		_freeze_mg = mg
		_frozen.clear()
	if _frozen.is_empty():
		return
	_freeze_t += delta
	if _freeze_t < 0.1:
		return
	_freeze_t = 0.0
	for id in _frozen.keys():
		var t: Node3D = app.g.char_of(int(id))
		if t == null:
			continue
		var p: Vector3 = _frozen[id]
		if t.global_position.distance_to(p) > 0.3:
			app.g.teleport(t, p)


func disable_all() -> void:
	_frozen.clear()


func kick(id: int) -> void:
	if not app.g.is_host():
		app.note("kick: host only")
		return
	if id == app.g.my_id() or id <= 1:
		return
	if app.g.is_bot_id(id):
		app.mod("bots").remove_bot(id)
		return
	if bool(app.cfg.val("pl.block_rejoin", true)):
		var sid = _steam_id(id)
		if sid != null and not _blocked_steam_ids.has(sid):
			_blocked_steam_ids.append(sid)
	var pname: String = app.g.player_name(id)
	var be = app.g.backend()
	app.note("kicking " + pname + "...")
	# 1) The game's own "room disbanded" refusal: in the lobby, their game
	#    leaves by itself and lands on the main menu with a message.
	if app.g.valid(be) and be.has_method("refuse_client_rpc"):
		be.rpc_id(id, "refuse_client_rpc", id, 3)
	# 2) MachineParty+'s kick message, so players running it leave cleanly
	#    even mid-match (same packet format, channel 11).
	_send_mpplus_kick(id)
	# 3) Give them a few seconds to leave on their own before forcing it -
	#    a forced disconnect is the last resort.
	for i in 12:
		await get_tree().create_timer(0.25).timeout
		if not multiplayer.has_multiplayer_peer() or not multiplayer.get_peers().has(id):
			app.note("kicked " + pname)
			return
	if multiplayer.has_multiplayer_peer():
		var peer = multiplayer.multiplayer_peer
		if peer != null and multiplayer.get_peers().has(id):
			peer.disconnect_peer(id)
	app.note("kicked " + pname + " (forced)")


func _send_mpplus_kick(id: int) -> void:
	var sid = _steam_id(id)
	var br = app.mod("browser")
	var steam = br.steam() if br != null else null
	if sid == null or steam == null or not steam.has_method("sendP2PPacket"):
		return
	var bytes := JSON.stringify({"t": "kick"}).to_utf8_buffer()
	steam.sendP2PPacket(int(sid), bytes, 2, 11)


func kick_target() -> void:
	var id := int(app.cfg.val("pl.kick_target", -1))
	if id <= 0 or not app.g.player_ids().has(id):
		app.note("kick: pick a player first")
		return
	kick(id)


func _steam_id(id: int):
	var cp = app.g.gv(app.g.backend(), "connected_players", {})
	if cp is Dictionary and cp.has(id) and cp[id] is Dictionary:
		return cp[id].get("id", null)
	return null


func _on_peer_connected(id) -> void:
	if not app.g.is_host() or _blocked_steam_ids.is_empty():
		return
	await get_tree().create_timer(0.3).timeout
	var sid = _steam_id(int(id))
	if sid != null and _blocked_steam_ids.has(sid):
		app.note("blocked a kicked player from rejoining")
		kick(int(id))


func clear_blocks() -> void:
	_blocked_steam_ids.clear()
	app.note("rejoin blocks cleared")


# --- UI -------------------------------------------------------------------------------

func build_ui(ui, page) -> void:
	ui.header(page, "Players")
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 4)
	page.add_child(_list_box)
	ui.note(page, "Teleport to: moves you to them. Teleport to me: pulls them to you (uses the game's own teleport, so it works on friends without the mod). Kick is host only.")

	ui.header(page, "Chosen player")
	ui.option_dynamic(page, "Target", "pl.target", _player_items,
		"Used by the 'teleport items & entities' hotkey and Misc > Teleport loose objects.")
	ui.slider(page, "Spread radius", "pl.entity_radius", 0.5, 6.0, 0.25)
	ui.buttons(page, [
		["Teleport all players to me", tp_all_to_me],
		["Teleport items & entities to target", func() -> void: tp_entities_to(target_id())],
	])

	ui.header(page, "Shove, freeze, smite")
	ui.slider(page, "Shove strength", "pl.shove_strength", 0.5, 5.0, 0.1, "How hard Lethal Rebound shoves and how many bumps in Duck Hunt / Minefield.", "x%.1f")
	ui.slider(page, "Launch distance", "pl.shove_dist", 1.0, 20.0, 0.5, "Minigames with no shove move the player this far instead.", "%.1f m")
	ui.buttons(page, [
		["Freeze everyone else", freeze_all_others],
		["Unfreeze all", unfreeze_all],
		["Smite everyone else", smite_all_others],
	])
	ui.note(page, "These use each minigame's own shove and death functions, so they work on friends without the mod and count in the game's scoring. Freezes clear when the minigame changes. Smite isn't available in Chisel Gauntlet or Smoke Break - those games decide eliminations themselves.")

	ui.header(page, "Kick")
	ui.option_dynamic(page, "Player", "pl.kick_target", _kick_items)
	var kb: HBoxContainer = ui.buttons(page, [["Kick player", kick_target, "Removes them from your lobby. Host only."]])
	(kb.get_child(0) as Button).add_theme_color_override("font_color", ui.BAD)
	ui.check(page, "Block kicked players from rejoining (this session)", "pl.block_rejoin",
		"They also stop seeing your lobby in the server browser.")
	ui.buttons(page, [["Clear rejoin blocks", clear_blocks]])
	ui.live(page, func() -> String:
		if not app.g.is_host():
			return "You're not the host - only the host can kick."
		return "Kick also sits on each player's row above. Kicking in the lobby is cleanest; mid-match, players without a mod get disconnected if they don't leave on their own.", ui.MUTED)
	_rebuild_list()


func _kick_items() -> Array:
	var out: Array = [[-1, "Pick a player"]]
	for id in app.g.player_ids():
		if id != app.g.my_id() and id > 1:
			out.append([id, app.g.player_name(id)])
	return out


func _player_items() -> Array:
	var out: Array = [[-1, "Me (default)"]]
	for id in app.g.player_ids():
		var tag := " (you)" if id == app.g.my_id() else ""
		out.append([id, app.g.player_name(id) + tag])
	return out


func _signature() -> String:
	var parts: Array = []
	for id in app.g.player_ids():
		parts.append("%d:%s:%s" % [id, app.g.player_name(id), "c" if app.g.char_of(id) != null else "-"])
	return ",".join(parts) + "|" + str(app.g.is_host()) + "|" + str(_frozen.keys()) + "|" + app.g.minigame_cls()


func _rebuild_list() -> void:
	if _list_box == null or not is_instance_valid(_list_box):
		return
	app.ui.clear(_list_box)
	var ids: Array = app.g.player_ids()
	if ids.is_empty():
		app.ui.note(_list_box, "No players yet - host or join a lobby.")
		return
	var me: int = app.g.my_id()
	for id in ids:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		_list_box.add_child(h)
		var l := Label.new()
		var tags: Array = []
		if id == 1:
			tags.append("host")
		if id == me:
			tags.append("you")
		if app.g.is_bot_id(id):
			tags.append("bot")
		if app.g.char_of(id) == null:
			tags.append("no character")
		l.text = "%s  [%s]" % [app.g.player_name(id), ", ".join(tags)] if not tags.is_empty() else app.g.player_name(id)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		h.add_child(l)
		if id != me:
			app.ui.button(h, "Teleport to", tp_me_to.bind(id))
			app.ui.button(h, "Teleport to me", tp_to_me.bind(id))
			var h2 := HBoxContainer.new()
			h2.add_theme_constant_override("separation", 6)
			_list_box.add_child(h2)
			var pad := Control.new()
			pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h2.add_child(pad)
			app.ui.button(h2, "Shove", shove.bind(id), "Knocks them away from you.")
			var fz: Button = app.ui.button(h2, "Unfreeze" if is_frozen(id) else "Freeze", func() -> void:
				toggle_freeze(id)
				_list_sig = ""
			, "Pins them where they stand.")
			if is_frozen(id):
				fz.add_theme_color_override("font_color", Color("#40c8ff"))
			var sm: Button = app.ui.button(h2, "Smite", smite.bind(id), "Eliminates them using this minigame's own death.")
			sm.add_theme_color_override("font_color", app.ui.WARN)
			if app.g.char_of(id) != null and not can_smite(id):
				sm.disabled = true
				sm.tooltip_text = "This minigame decides eliminations itself - no smite here."
			if app.g.is_host():
				var k: Button = app.ui.button(h2, "Kick", kick.bind(id))
				k.add_theme_color_override("font_color", app.ui.BAD)
