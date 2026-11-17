# Player launch duration bug (#849)

Base caffec2054b80e1dd718ccd8a0e4411bf3016964. Spirit Punch's authored700px/s x0.12s means84px on flat ground. Before:8 full ticks at60Hz move93.333px. After: last tick uses remaining0.003333s,84px. End tick/signal ordering unchanged. Only player.gd launch velocity computation changes, no authored speed/duration, spell mechanics, terrain, enemy, light or audio changes.

Regression checks velocity integral across30/60/120Hz deltas, fractional/integral durations, actual Player displacement at60Hz, single end signal at final position, zero delta finiteness, death cancellation. Non60Hz tests validate velocity integral rather than manual move_and_slide displacement because that engine call uses actual engine physics delta.

Demo is scripted native Godot4.5.1, actual bare Player+SpellCaster casting Spirit Punch, automatic player processing disabled and physics stepped at60Hz by driver. Before93.333px/after84px, green expected endpoint, gray start, camera3x. Not interactive gameplay, no terrain/collision scenario, no browser/real-GPU qualification. Bare player uses existing blue debug body, no new art. Actual video and screenshots directly inspected. Deferred punch still spawns after movement. Driver reproducible with CASE=before/after, --fixed-fps60 (separate flag value by a space); write-movie optional. No copied external assets.
