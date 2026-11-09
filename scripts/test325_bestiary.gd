extends SceneTree
## #325 harness: hub bestiary. Enemies that enter the tree are recorded by
## type in the cross-run Bestiary record (static + saved to disk), the hub
## carries a walk-up BestiaryStation, and the panel lists encountered types
## with name/sprite/count and unseen catalog types as "???". The record must
## survive a run restart (scene reload) and a fresh process (disk reload).

const TEST_SAVE := "user://test325_bestiary.cfg"

var failures := 0
var check_count := 0
var panel: BestiaryPanel

func _check(cond: bool, name: String) -> void:
	check_count += 1
	if cond:
		print("[325] ", name, " -> PASS")
	else:
		failures += 1
		print("[325] ", name, " -> FAIL")

func _rows() -> VBoxContainer:
	return panel.get_node("Backdrop/Margin/VBox/Scroll/Rows") as VBoxContainer

func _row(id: StringName) -> Control:
	for r in _rows().get_children():
		if r.get_meta("bestiary_id", &"") == id:
			return r
	return null

func _row_name(id: StringName) -> String:
	var r := _row(id)
	if r == null:
		return ""
	return (r.find_children("NameLabel", "Label", true, false)[0] as Label).text

func _spawn(scene: PackedScene) -> Node:
	var e := scene.instantiate()
	e.set_physics_process(false)
	root.add_child(e)
	return e

var _ran := false
var _stage := 0

func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false

func _run() -> void:
	print("test325: hub bestiary (#325)")
	Bestiary.save_path = TEST_SAVE
	Bestiary.clear()

	## 1. Empty record.
	_check(Bestiary.seen_count() == 0, "fresh record has no encounters")
	_check(Bestiary.listed_ids().size() == Bestiary.CATALOG.size(), "catalog types listed even when unseen")

	## 2. Hub carries a walk-up station; Main mounts the panel.
	var hub: Node = preload("res://scenes/hub.tscn").instantiate()
	var station := hub.get_node_or_null("BestiaryStation") as BestiaryStation
	_check(station != null, "hub has a BestiaryStation")
	hub.free()
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_check(main_src.contains("bestiary_panel.tscn"), "Main mounts the BestiaryPanel")

	panel = preload("res://scenes/bestiary_panel.tscn").instantiate()
	root.add_child(panel)
	station = preload("res://scenes/bestiary_station.tscn").instantiate()
	root.add_child(station)
	_check(not panel.visible and not panel.is_in_group("modal_ui"), "panel hidden by default")

	## 3. Unseen panel: every catalog row is "???".
	var player: Player = preload("res://scenes/player.tscn").instantiate()
	player.set_physics_process(false)
	root.add_child(player)
	station._on_body_entered(player)
	_check(panel.visible and panel.is_in_group("modal_ui"), "walk-up opens the bestiary (visible + modal_ui)")
	_check(_row_name(&"mustache_warrior") == "???", "unseen enemy shows as ???")
	_check(panel.get_node("Backdrop/Margin/VBox/CountLabel").text == "0 / %d enemies encountered" % Bestiary.CATALOG.size(), "count label 0 / N")
	var icon := _row(&"mustache_warrior").find_children("Icon", "TextureRect", true, false)
	_check(not icon.is_empty() and (icon[0] as TextureRect).modulate == BestiaryPanel.UNSEEN_MODULATE, "unseen enemy icon is a dark silhouette")

	## 4. Spawning real enemy scenes records encounters by type.
	var e1 := _spawn(preload("res://scenes/enemy.tscn"))
	var e2 := _spawn(preload("res://scenes/enemy.tscn"))
	var boss := _spawn(preload("res://scenes/mustache_warlord.tscn"))
	_check(Bestiary.encounter_count(&"mustache_warrior") == 2, "two warriors recorded (count 2)")
	_check(Bestiary.has_seen(&"mustache_warlord"), "warlord boss recorded")
	_check(not Bestiary.has_seen(&"head_boss"), "head boss not met yet")
	_check(Bestiary.seen_count() == 2, "two distinct types seen")

	## 5. Open panel refreshes live.
	_process_panel()
	_check(_row_name(&"mustache_warrior") == "Mustache Warrior", "seen enemy row shows its name")
	_check(_row_name(&"head_boss") == "???", "unseen boss still ???")
	var detail := _row(&"mustache_warrior").find_children("DetailLabel", "Label", true, false)[0] as Label
	_check(detail.text == "Encountered 2 times", "row shows encounter count")
	_check(not _row(&"mustache_warlord").find_children("BossTag", "Label", true, false).is_empty(), "boss row carries a BOSS tag")
	icon = _row(&"mustache_warrior").find_children("Icon", "TextureRect", true, false)
	_check(not icon.is_empty() and (icon[0] as TextureRect).texture != null and (icon[0] as TextureRect).modulate == Color.WHITE, "seen enemy shows its sprite")
	_check(_rows().find_children("*", "Button", true, false).is_empty(), "bestiary is read-only (no buttons)")
	for e in [e1, e2, boss]:
		e.free()

	## 6. Enemies freed (area swap / run restart) - the record stays, and a
	## code-built enemy with no scene is not recorded as junk.
	_check(Bestiary.encounter_count(&"mustache_warrior") == 2, "record outlives the freed enemies")
	var bare := Enemy.new()
	root.add_child(bare)
	_check(Bestiary.seen_count() == 2, "scene-less enemy is not recorded")
	bare.free()

	## 7. Survives a fresh process: drop memory, reload from disk.
	_check(FileAccess.file_exists(TEST_SAVE), "record saved to disk")
	Bestiary.reload_from_disk()
	_check(Bestiary.encounter_count(&"mustache_warrior") == 2 and Bestiary.has_seen(&"mustache_warlord"), "record reloads from disk (cross-run/session)")
	_check(not Bestiary.has_seen(&"head_boss"), "reload does not invent encounters")

	## 8. An enemy scene outside the catalog is still listed.
	Bestiary.record(&"slime_king")
	_check(Bestiary.listed_ids().has(&"slime_king") and Bestiary.display_name(&"slime_king") == "Slime King", "uncatalogued type listed with derived name")

	## 9. Walk-away closes.
	station._on_body_exited(player)
	_check(not panel.visible and not panel.is_in_group("modal_ui"), "walk-away closes the bestiary")

	Bestiary.clear()
	Bestiary.save_path = Bestiary.DEFAULT_SAVE_PATH
	print("test325 done: %d checks, %d failures" % [check_count, failures])
	print("RESULT: ALL PASS" if failures == 0 else "RESULT: FAIL")
	quit(1 if failures > 0 else 0)

func _process_panel() -> void:
	panel._process(0.0)
