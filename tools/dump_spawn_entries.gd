extends SceneTree
## Prints every spawn entry an area scene carries, one line per entry, so two
## checkouts can be diffed to prove a spawn-data change kept spawns identical.
##   godot --headless --path . --script res://tools/dump_spawn_entries.gd
## Lines start with "SPAWN ". Covers AreaSpawnData carriers (authored, or
## filled in _ready like the generated dungeon) and AmbushEvent entries on
## LocationTriggers (built in _ready like the abandoned village).
## Reads entries through Object/Dictionary .get, so it works on both the
## Dictionary and the SpawnEntry shape.

const KNOWN := ["position", "enemy", "reward_table", "definition", "route"]

func _initialize() -> void:
	var scenes: Array[String] = []
	_collect("res://scenes", scenes)
	scenes.sort()
	for path in scenes:
		await _dump_scene(path)
	quit(0)

func _collect(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".tscn"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(d), out)

func _dump_scene(path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var root := packed.instantiate()
	if not _has_spawn_source(root):
		root.free()
		return
	# _ready fills generated carriers and ambush events.
	get_root().add_child(root)
	await process_frame
	var lines: Array[String] = []
	for node in _walk(root):
		var label := "%s :: %s" % [path, root.get_path_to(node)]
		if node is AreaSpawnData:
			_dump_entries(label, (node as AreaSpawnData).entries, lines)
		elif node is LocationTrigger:
			var ev := (node as LocationTrigger).event
			if ev is AmbushEvent:
				_dump_entries(label + " (ambush)", (ev as AmbushEvent).entries, lines)
	for l in lines:
		print("SPAWN ", l)
	root.queue_free()
	await process_frame

func _has_spawn_source(root: Node) -> bool:
	for node in _walk(root):
		if node is AreaSpawnData or node is LocationTrigger:
			return true
	return false

func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	for c in root.get_children():
		out.append_array(_walk(c))
	return out

func _dump_entries(label: String, entries: Array, lines: Array[String]) -> void:
	lines.append("%s count=%d" % [label, entries.size()])
	for i in entries.size():
		var entry: Variant = entries[i]
		var fields: Array[String] = []
		for key: String in KNOWN:
			fields.append("%s=%s" % [key, _fmt(key, _field(entry, key))])
		fields.append("extra=%s" % [_extra_keys(entry)])
		lines.append("%s [%d] %s" % [label, i, " ".join(fields)])

func _field(entry: Variant, key: String) -> Variant:
	if entry is Dictionary:
		return (entry as Dictionary).get(key)
	if entry is Object:
		return (entry as Object).get(key)
	return null

func _fmt(key: String, v: Variant) -> String:
	if v is Resource:
		var res := v as Resource
		return res.resource_path if not res.resource_path.is_empty() else "<inline %s>" % res.get_class()
	if key == "route":
		var pts: Array[String] = []
		if v != null:
			for p: Vector2 in v:
				pts.append(var_to_str(p))
		return "[%s]" % ", ".join(pts)
	return var_to_str(v)

## Keys outside KNOWN, so a dropped or added field shows up in the diff.
func _extra_keys(entry: Variant) -> String:
	var extra: Array[String] = []
	if entry is Dictionary:
		for k: Variant in (entry as Dictionary).keys():
			if not str(k) in KNOWN:
				extra.append(str(k))
	elif entry is Object:
		for p: Dictionary in (entry as Object).get_property_list():
			var usage: int = p["usage"]
			if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not str(p["name"]) in KNOWN:
				extra.append(str(p["name"]))
	extra.sort()
	return ",".join(extra)
