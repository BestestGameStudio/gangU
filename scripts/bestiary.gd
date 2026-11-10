class_name Bestiary
extends RefCounted
## (#325) Encountered-enemy record that survives across runs.
##
## A run restart is a full scene reload (RunManager, #6), so anything
## mounted on Main is wiped. The record therefore lives in STATIC state on
## this script (kept for the life of the process) and is mirrored to
## SAVE_PATH on disk, so enemies seen in earlier runs - and earlier play
## sessions - stay in the hub bestiary.
##
## "Encountered" = an enemy of that type entered the tree in the player's
## current area (Enemy._ready calls record_enemy). Identity comes from the
## enemy's scene file, so placing a new instance of a known scene needs no
## extra wiring. Display data for known types lives in CATALOG; an enemy
## scene not in the catalog is still recorded and listed under a name
## derived from its file name.

const DEFAULT_SAVE_PATH := "user://bestiary.cfg"

## Known enemy types, in bestiary display order. Unseen entries render as
## "???" silhouettes so the player can see how much is left to find.
const CATALOG: Array[Dictionary] = [
	{
		"id": &"mustache_warrior",
		"name": "Mustache Warrior",
		"scene": "res://scenes/enemy.tscn",
		"frames": "res://resources/sprites/mustache_warrior_frames.tres",
		"boss": false,
	},
	{
		# #420: barricade-deploying Moustache variant (its own entry - Daniel:
		# "it should be a variant and a separate entry in the bestiary").
		"id": &"mustache_barricader",
		"name": "Mustache Barricader",
		"scene": "res://scenes/enemy_barricader.tscn",
		"frames": "res://resources/sprites/mustache_warrior_frames.tres",
		"boss": false,
	},
	{
		"id": &"slime",
		"name": "Slime",
		"scene": "res://scenes/enemy_slime.tscn",
		"frames": "res://resources/sprites/slime_frames.tres",
		"boss": false,
	},
	{
		# #464: rod-hooking support enemy.
		"id": &"fishy",
		"name": "Fishy",
		"scene": "res://scenes/enemy_fishy.tscn",
		"frames": "res://resources/sprites/fishy_frames.tres",
		"boss": false,
	},
	{
		"id": &"mustache_warlord",
		"name": "Mustache Warlord",
		"scene": "res://scenes/mustache_warlord.tscn",
		"frames": "res://resources/sprites/mustache_warrior_frames.tres",
		"boss": true,
	},
	{
		"id": &"head_boss",
		"name": "The Head",
		"scene": "res://scenes/head_boss.tscn",
		"frames": "res://resources/sprites/head_boss_frames.tres",
		"boss": true,
	},
	{
		"id": &"beast_boss",
		"name": "The Beast",
		"scene": "res://scenes/beast_boss.tscn",
		"frames": "res://resources/sprites/beast_boss_frames.tres",
		"boss": true,
	},
	{
		# #368: defense-mission boss wave enemy.
		"id": &"siege_brute",
		"name": "Siege Brute",
		"scene": "res://scenes/defense_wave_boss.tscn",
		"frames": "res://resources/sprites/mustache_warrior_frames.tres",
		"boss": true,
	},
]

## Where the record is persisted. Tests point this at their own file.
static var save_path: String = DEFAULT_SAVE_PATH
## id (StringName) -> encounter count (int). Insertion order = first seen.
static var _counts: Dictionary = {}
static var _loaded := false
## Bumped on every change so open panels can cheaply detect a refresh.
static var revision := 0

## Resolve an enemy's bestiary id from its scene file. Empty for enemies
## built in code with no scene (nothing stable to key them by).
static func id_for_scene(scene_path: String) -> StringName:
	if scene_path.is_empty():
		return &""
	for entry in CATALOG:
		if entry["scene"] == scene_path:
			return entry["id"]
	return StringName(scene_path.get_file().get_basename())

static func catalog_entry(id: StringName) -> Dictionary:
	for entry in CATALOG:
		if entry["id"] == id:
			return entry
	return {}

## Display name for an id: the catalog name, else a title-cased file name.
static func display_name(id: StringName) -> String:
	var entry := catalog_entry(id)
	if not entry.is_empty():
		return entry["name"]
	return String(id).capitalize()

static func record_enemy(enemy: Node) -> void:
	record(id_for_scene(enemy.scene_file_path))

static func record(id: StringName) -> void:
	if id == &"":
		return
	_ensure_loaded()
	_counts[id] = int(_counts.get(id, 0)) + 1
	revision += 1
	_save()

static func has_seen(id: StringName) -> bool:
	_ensure_loaded()
	return int(_counts.get(id, 0)) > 0

static func encounter_count(id: StringName) -> int:
	_ensure_loaded()
	return int(_counts.get(id, 0))

## Every id the bestiary should list: the catalog first (seen or not),
## then any seen enemy types the catalog does not know about.
static func listed_ids() -> Array[StringName]:
	_ensure_loaded()
	var ids: Array[StringName] = []
	for entry in CATALOG:
		ids.append(entry["id"])
	for id in _counts.keys():
		if not ids.has(id):
			ids.append(id)
	return ids

static func seen_count() -> int:
	_ensure_loaded()
	var n := 0
	for id in _counts.keys():
		if int(_counts[id]) > 0:
			n += 1
	return n

## Drop in-memory state and re-read from disk (simulates a fresh process).
## (Not named reload(): Bestiary.reload() would hit GDScript.reload().)
static func reload_from_disk() -> void:
	_counts.clear()
	_loaded = false
	revision += 1
	_ensure_loaded()

## Forget everything, on disk too. Used by tests; not wired to gameplay.
static func clear() -> void:
	_counts.clear()
	_loaded = true
	revision += 1
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	if not cfg.has_section("encountered"):
		return
	for key in cfg.get_section_keys("encountered"):
		_counts[StringName(key)] = int(cfg.get_value("encountered", key, 0))

static func _save() -> void:
	var cfg := ConfigFile.new()
	for id in _counts.keys():
		cfg.set_value("encountered", String(id), _counts[id])
	var err := cfg.save(save_path)
	if err != OK:
		push_warning("Bestiary: could not save %s (error %d)" % [save_path, err])
