# Moustache warrior voice SFX (#480)

State vocal cues for the Mustache Warrior (idle / combat / attacking /
receiving-damage / dying), requested by Colin on 2026-11-09 ("make sure there
are idle sounds, combat sounds, attacking sounds, receiving damage sounds and
dying sounds, and play those sound effects according to the relevant state
that each moustache warrior is in"). Both auditioned voices were approved with
"Both are good, randomize it".

All cues were generated with Instinct's speech tool as gibberish warrior
vocals for this project (no external source audio), then split into one-shot
cues, trimmed with short edge fades and peak-normalized to -3 dBFS
(`ffmpeg -af volumedetect` max about -3 dB per file). Exported as OGG Vorbis
q5 44.1 kHz mono for the web build. No other processing.

Two voices:

- `gravelly/` - low, gravelly warrior voice (10 cues).
- `excitable/` - higher, excitable warrior voice (9 cues). Its
  `combat_laugh` take had possible source clipping in the audition and was
  deliberately not shipped.

Each state folder of the source pack maps to a cue family in
`scripts/mustache_voice.gd` (`ALIASES`); `combat/combat_spotted` plays once
per engagement, the other combat cues are random chatter.

At runtime `MustacheVoice.VOLUME_DB` applies a further -6 dB, with a small
random pitch wobble per play.
