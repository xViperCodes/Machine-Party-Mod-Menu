extends Node

## Game helpers. Everything is looked up dynamically (by autoload name, script
## class name and property name) so the mod has no compile-time dependency on
## the game's scripts and keeps loading if a class is renamed in an update.

var app = null

var _chars: Dictionary = {}
var _chars_time: float = -1.0
var _scan_interval := 0.25
var _chars_root: Node = null


# --- autoloads & safe access -------------------------------------------------

func al(autoload_name: String) -> Node:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)


func valid(o) -> bool:
	return o != null and is_instance_valid(o)


## Read a property, following dotted paths ("timer.time_left").
## Supports a few pseudo-properties: size (Array/Dictionary), length (Vector).
func gv(obj, path: String, fallback = null):
	var cur = obj
	for part in path.split("."):
		if cur == null:
			return fallback
		if cur is Object:
			if not is_instance_valid(cur):
				return fallback
			if part in cur:
				cur = cur.get(part)
				continue
			if part == "class":
				cur = cls(cur)
				continue
			return fallback
		if (cur is Array or cur is Dictionary) and part == "size":
			cur = cur.size()
			continue
		if (cur is Vector3 or cur is Vector2) and part == "length":
			cur = cur.length()
			continue
		if cur is Dictionary and cur.has(part):
			cur = cur[part]
			continue
		return fallback
	return fallback if cur == null else cur


func sv(obj, prop: String, value) -> bool:
	if not valid(obj) or not (prop in obj):
		return false
	obj.set(prop, value)
	return true


func call_safe(obj, method: String, args: Array = []):
	if not valid(obj) or not obj.has_method(method):
		return null
	return obj.callv(method, args)


## Script class name of a node ("DuckHuntHunterPlayer"), or the script file
## name for scripts without class_name ("hatch").
func cls(node) -> String:
	if not valid(node):
		return ""
	var s = node.get_script()
	if s == null:
		return ""
	if s.has_method("get_global_name"):
		var gname = s.get_global_name()
		if gname != null and str(gname) != "":
			return str(gname)
	var p: String = s.resource_path
	if p.is_empty():
		return "Script"
	return p.get_file().get_basename()


func script_consts(obj) -> Dictionary:
	if not valid(obj):
		return {}
	var s = obj.get_script()
	if s == null:
		return {}
	return s.get_script_constant_map()


## Dictionary of enum NAME -> value from an autoload, e.g. Globals.MinigameIdentifier.
func autoload_enum(autoload_name: String, enum_name: String) -> Dictionary:
	var c := script_consts(al(autoload_name))
	var e = c.get(enum_name, {})
	return e if e is Dictionary else {}


# --- session / scene ----------------------------------------------------------

func scene() -> Node:
	var tree := get_tree()
	return tree.current_scene if tree != null else null


## The online Game scene (scripts/scenes/game/game.gd) or the local couch game.
func game() -> Node:
	var s := scene()
	if valid(s) and ("session_minigame_list" in s):
		return s
	return null


func minigame() -> Node:
	var gm := game()
	if gm != null:
		var m = gm.get("minigame")
		if valid(m):
			return m
	return null


func minigame_cls() -> String:
	return cls(minigame())


func lobby_scene() -> Node:
	var s := scene()
	if valid(s) and s.has_method("start_game_rpc"):
		return s
	return null


func has_peer() -> bool:
	return multiplayer != null and multiplayer.has_multiplayer_peer()


func my_id() -> int:
	if has_peer():
		return multiplayer.get_unique_id()
	return 1


func is_host() -> bool:
	if multiplayer == null:
		return true
	return multiplayer.is_server()


func online() -> bool:
	var nm := al("NetworkManager")
	if nm != null and nm.has_method("is_active"):
		return bool(nm.is_active())
	return false


func local_game() -> bool:
	return bool(gv(al("GameManager"), "local_game", false))


func backend():
	return gv(al("NetworkManager"), "active_backend", null)


# --- players ------------------------------------------------------------------

func presences() -> Dictionary:
	var pm := al("PlayerManager")
	var p = gv(pm, "player_presences", {})
	return p if p is Dictionary else {}


## Every known player: lobby members (backend) plus in-game presences.
func player_ids() -> Array:
	var ids: Array = []
	for id in presences().keys():
		if not ids.has(int(id)):
			ids.append(int(id))
	var be = backend()
	var cp = gv(be, "connected_players", {})
	if cp is Dictionary:
		for id in cp.keys():
			if not ids.has(int(id)):
				ids.append(int(id))
	ids.sort()
	return ids


func player_name(id: int) -> String:
	var bots = app.mod("bots") if app != null else null
	if bots != null and bots.has_method("is_bot") and bots.is_bot(id):
		return bots.bot_name(id)
	var be = backend()
	var cp = gv(be, "connected_players", {})
	if cp is Dictionary and cp.has(id):
		var info = cp[id]
		if info is Dictionary and info.has("name"):
			return str(info["name"])
	var pres = presences().get(id, null)
	if valid(pres):
		var n = gv(pres, "network_name", "")
		if str(n) != "":
			return str(n)
	return "Player %d" % id


func is_bot_id(id: int) -> bool:
	var bots = app.mod("bots")
	return bots != null and bots.has_method("is_bot") and bots.is_bot(id)


# --- characters in the current minigame -------------------------------------

## network_id -> character node for the current minigame. A "character" is any
## Node3D with a valid player_presence (that's how every minigame player works).
func characters() -> Dictionary:
	var now := Time.get_ticks_msec() / 1000.0
	var root := minigame()
	if root != _chars_root:
		# New minigame (or none): don't serve the previous one's list.
		_chars_root = root
		_chars_time = -1.0
	var wait := _scan_interval if not _chars.is_empty() else 0.1
	if now - _chars_time < wait:
		var ok := true
		for c in _chars.values():
			if not valid(c):
				ok = false
				break
		if ok:
			return _chars
	_chars_time = now
	_chars = {}
	if root == null:
		return _chars
	for n in descendants(root):
		if not (n is Node3D):
			continue
		if not ("player_presence" in n):
			continue
		var pres = n.get("player_presence")
		if not valid(pres):
			continue
		var id := int(gv(pres, "network_id", -1))
		if id < 0:
			continue
		# Several nodes can reference the same presence (e.g. Firearm Factory
		# workstations); prefer the one that is actually the player character.
		if _chars.has(id) and _char_score(_chars[id]) >= _char_score(n):
			continue
		_chars[id] = n
	return _chars


func _char_score(n: Node) -> int:
	var s := 0
	if cls(n).ends_with("Player"):
		s += 2
	if n is CharacterBody3D:
		s += 1
	return s


func char_of(id: int) -> Node3D:
	var c = characters().get(id, null)
	return c if valid(c) else null


func my_char() -> Node3D:
	return char_of(my_id())


func camera() -> Camera3D:
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null


# --- tree walking --------------------------------------------------------------

func descendants(root: Node, include_root: bool = false) -> Array:
	var out: Array = []
	if not valid(root):
		return out
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n != root or include_root:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func find_cls(root: Node, names: Array) -> Array:
	var out: Array = []
	for n in descendants(root):
		if names.has(cls(n)):
			out.append(n)
	return out


func first_cls(root: Node, cls_name: String) -> Node:
	for n in descendants(root):
		if cls(n) == cls_name:
			return n
	return null


# --- movement -------------------------------------------------------------------

func is_mine(node) -> bool:
	return valid(node) and node.get_multiplayer_authority() == my_id()


## Move a character/object. Uses the game's own teleport_rpc when the node has
## one (runs on every peer, so it works on vanilla clients); otherwise moves the
## node directly, which only sticks if we own it (our player, or host objects).
func teleport(node, pos: Vector3) -> bool:
	if not valid(node) or not (node is Node3D):
		return false
	if node.has_method("teleport_rpc"):
		var argc := 1
		if node.has_method("get_method_argument_count"):
			argc = node.get_method_argument_count("teleport_rpc")
		if argc >= 2:
			var rot: Vector3
			if cls(node) == "ChiselGauntletPlayer":
				rot = node.global_rotation_degrees
			else:
				var vis = gv(node, "visuals", null)
				rot = vis.global_rotation if (valid(vis) and vis is Node3D) else node.global_rotation
			_rpc(node, "teleport_rpc", [pos, rot])
		else:
			_rpc(node, "teleport_rpc", [pos])
		return true
	if node is RigidBody3D:
		node.linear_velocity = Vector3.ZERO
		node.angular_velocity = Vector3.ZERO
		var t: Transform3D = node.global_transform
		t.origin = pos
		PhysicsServer3D.body_set_state(node.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, t)
	node.global_position = pos
	if node is CharacterBody3D:
		node.velocity = Vector3.ZERO
	return is_mine(node) or is_host()


func _rpc(node: Node, method: String, args: Array) -> void:
	if has_peer():
		node.callv("rpc", [method] + args)
	else:
		node.callv(method, args)


## Points spread in a ring so teleported things don't stack on one spot.
func ring(center: Vector3, index: int, count: int, radius: float = 1.5) -> Vector3:
	if count <= 1:
		return center
	var a := TAU * float(index) / float(count)
	return center + Vector3(cos(a), 0.0, sin(a)) * radius


# --- formatting -------------------------------------------------------------------

func fmt_value(v) -> String:
	if v == null:
		return "-"
	match typeof(v):
		TYPE_BOOL:
			return "yes" if v else "no"
		TYPE_FLOAT:
			return "%.2f" % v
		TYPE_VECTOR3:
			return "%.1f" % v.length()
		TYPE_VECTOR2:
			return "%.1f" % v.length()
		TYPE_OBJECT:
			if not is_instance_valid(v):
				return "-"
			if v is Node:
				return str(v.name)
			return v.get_class()
	return str(v)
