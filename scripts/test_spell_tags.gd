extends SceneTree
## #66 foundation harness: controlled tag vocabulary is sound and every spell
## resource's tags validate against it. Metadata-only foundation; no behavior
## is asserted or implied here.
var ok := true

func _initialize() -> void:
	# Vocabulary sanity: no duplicates.
	var seen := {}
	for t in SpellTags.ALL:
		if seen.has(t):
			print("[TAGS] FAIL duplicate vocabulary entry: ", t); ok = false
		seen[t] = true
	print("[TAGS] vocabulary entries: ", SpellTags.ALL.size())
	# Validators.
	if not SpellTags.is_valid(SpellTags.BURN):
		print("[TAGS] FAIL is_valid(burn)"); ok = false
	var unknown := SpellTags.unknown_tags([&"projectile", &"bogus_tag"])
	if unknown != [&"bogus_tag" as StringName]:
		print("[TAGS] FAIL unknown_tags detection: ", unknown); ok = false
	# Every spell resource validates.
	var paths := []
	var dir := DirAccess.open("res://resources/spells")
	for f in dir.get_files():
		if f.ends_with(".tres"):
			paths.append("res://resources/spells/" + f)
	for p in paths:
		var sp: Spell = load(p)
		if sp == null:
			print("[TAGS] FAIL load ", p); ok = false; continue
		var u := SpellTags.unknown_tags(sp.tags)
		if u.is_empty():
			print("[TAGS] ", sp.spell_name, " tags OK: ", sp.tags)
		else:
			print("[TAGS] FAIL ", sp.spell_name, " unknown tags: ", u); ok = false
	# Buff-match seam helpers: pure queries, no policy chosen.
	if not SpellTags.match_any([&"burn"], [&"projectile", &"burn"]):
		print("[TAGS] FAIL match_any"); ok = false
	if SpellTags.match_all([&"projectile", &"burn"], [&"projectile"]):
		print("[TAGS] FAIL match_all should be false"); ok = false
	if not SpellTags.match_all([&"projectile", &"burn"], [&"projectile", &"burn"]):
		print("[TAGS] FAIL match_all should be true"); ok = false
	print("[TAGS] match_any/match_all query helpers OK")
	# Effects field retired.
	var probe := Spell.new()
	if "effects" in probe:
		print("[TAGS] FAIL effects field still present on Spell"); ok = false
	else:
		print("[TAGS] effects field retired OK")
	print("[TAGS] ", "PASS" if ok else "FAIL")

func _process(_delta: float) -> bool:
	quit(0 if ok else 1)
	return true
