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
`game/enemies/mustache_voice.gd` (`ALIASES`); `combat/combat_spotted` plays once
per engagement, the other combat cues are random chatter.

At runtime `MustacheVoice.VOLUME_DB` applies a further -6 dB, with a small
random pitch wobble per play.


# Fire Ball cast and impact (#584)

Colin chose the v3 soft cast and the latest collision sample over iMessage on
2026-11-10, then requested implementation. Both are original procedural audio,
not recorded flame or external foley. The source samples were synthesized from
shaped noise, turbulence and short transients, with no paid service or samples.

- `fireball_cast_soft.ogg`: approved v3 soft, 0.65 s, 44.1 kHz stereo.
- `fireball_impact.ogg`: realistic collision, 1.0 s, 44.1 kHz stereo.

Encoded directly from 16-bit lossless WAV originals with Vorbis quality 6.
No normalization, gain, pitch, trimming or looping. Runtime gain is 0 dB and
pitch 1.0; the existing Master volume setting still applies. Lossy encoding can
slightly change measured peaks, but no loudness boost is applied. Cast WAV peak
-9.9 dBFS, mean -22.5 dB; impact peak -1.4 dBFS, mean -15.6 dB.

Source WAV SHA-256:
- Cast: `b473ba4830de39da64b7f289f619124ae67a7fec7dd5189127a7ff73e8d4d874`
- Impact: `2107cfe0a847fa6ffdd0c708f91b19a9af15c458b4709005b739c940db471c1f`

Shipped OGG SHA-256:
- Cast: `d9852f7e0b7fb91d2f792ff366e8dee33f585598f6f520d606134a8c925c8bdd`
- Impact: `01bf58ebb4d3b05ef4ddeb47e71b94771333cee2aedd3be0e27929a1a7585e01`

Headless tests verify stream wiring and playback state, not perceived loudness
or by-ear in-game sound. The samples were approved before integration; the
in-game mix has not been auditioned by ear here.


# Player death (#591)

Approved v7: one human scream at 0.00s and one single-contact church bell
at 0.45s, with natural fade ending inside the existing 1.50s death screen.
No gameplay timer change, pitch randomization or looping. Master peak -6dBFS.
Sources (CC0): Dorian Clair https://bigsoundbank.com/cry-of-pain-s2361.html
and Joseph Sardin https://bigsoundbank.com/1-church-bell-s0830.html .
Bell pitched down 14 semitones in the approved master. Encoded from the
approved 44.1kHz 16-bit stereo WAV with Vorbis q6, no added processing.
The presentation owns playback and stops/frees it on expiry or scene exit.
