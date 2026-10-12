extends Node

## Settings store. Modules register defaults with def() during setup(), then
## main.gd loads config.json on top. Values keep the type of their default
## (JSON turns ints into floats and Colors into strings, so we convert back).

var app = null
var data: Dictionary = {}
var defaults: Dictionary = {}
var path: String = ""
var fallback_path: String = "user://viper_menu_config.json"

signal changed(key: String, value)
signal reloaded


func setup() -> void:
	path = app.dir.path_join("config.json")


func def(key: String, value) -> void:
	defaults[key] = _copy(value)
	if not data.has(key):
		data[key] = _copy(value)


func has_key(key: String) -> bool:
	return data.has(key) or defaults.has(key)


func val(key: String, fallback = null):
	if data.has(key):
		return data[key]
	if defaults.has(key):
		return defaults[key]
	return fallback


func put(key: String, value) -> void:
	if defaults.has(key):
		value = _coerce(value, defaults[key])
	data[key] = value
	changed.emit(key, value)


func reset() -> void:
	data.clear()
	for k in defaults.keys():
		data[k] = _copy(defaults[k])
	reloaded.emit()
	app.note("settings reset to defaults")


func save_file() -> bool:
	var out := {}
	for k in data.keys():
		out[k] = _encode(data[k])
	var text := JSON.stringify(out, "\t", true)
	for p in [path, fallback_path]:
		if p.is_empty():
			continue
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
			app.note("settings saved to " + ProjectSettings.globalize_path(p))
			return true
	app.note("could not save settings")
	return false


func load_file() -> bool:
	for p in [path, fallback_path]:
		if p.is_empty() or not FileAccess.file_exists(p):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
		if typeof(parsed) != TYPE_DICTIONARY:
			app.note("config.json is not valid JSON - using defaults")
			return false
		for k in parsed.keys():
			var v = _decode(parsed[k])
			if defaults.has(k):
				v = _coerce(v, defaults[k])
			data[k] = v
		reloaded.emit()
		return true
	return false


func _copy(v):
	if v is Dictionary or v is Array:
		return v.duplicate(true)
	return v


func _encode(v):
	if v is Color:
		return {"__color": v.to_html(true)}
	if v is Vector2:
		return {"__v2": [v.x, v.y]}
	if v is Dictionary:
		var d := {}
		for k in v.keys():
			d[k] = _encode(v[k])
		return d
	if v is Array:
		var a := []
		for x in v:
			a.append(_encode(x))
		return a
	return v


func _decode(v):
	if v is Dictionary:
		if v.has("__color"):
			return Color.html(str(v["__color"]))
		if v.has("__v2") and v["__v2"] is Array and v["__v2"].size() == 2:
			return Vector2(float(v["__v2"][0]), float(v["__v2"][1]))
		var d := {}
		for k in v.keys():
			d[k] = _decode(v[k])
		return d
	if v is Array:
		var a := []
		for x in v:
			a.append(_decode(x))
		return a
	return v


## Match a loaded value to the type of its default.
func _coerce(v, def_v):
	match typeof(def_v):
		TYPE_BOOL:
			return bool(v)
		TYPE_INT:
			if v is float or v is int or v is bool:
				return int(v)
			return def_v
		TYPE_FLOAT:
			if v is float or v is int:
				return float(v)
			return def_v
		TYPE_STRING:
			return str(v)
		TYPE_COLOR:
			if v is Color:
				return v
			if v is String:
				return Color.html(v)
			return def_v
		TYPE_DICTIONARY:
			if not (v is Dictionary):
				return _copy(def_v)
			var d: Dictionary = v.duplicate(true)
			for k in def_v.keys():
				if d.has(k):
					d[k] = _coerce(d[k], def_v[k])
				else:
					d[k] = _copy(def_v[k])
			return d
		TYPE_ARRAY:
			if v is Array:
				return v
			return _copy(def_v)
		TYPE_VECTOR2:
			if v is Vector2:
				return v
			return def_v
	return v
