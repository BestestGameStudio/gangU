# Boss music (#359)

Supplied by Mitravasu in issue #359 ("use them for any red bosses", made with LMMS).

| File | Source | Processing |
|------|--------|------------|
| `boss1.ogg` | `boss1.mp3` (24 s, 160 kb/s) | `ffmpeg -af volume=-15dB -c:a libvorbis -q:a 5` |
| `boss2.ogg` | `boss2.wav` (48 s, 24-bit PCM) | `ffmpeg -af volume=-17dB -c:a libvorbis -q:a 5` |

The originals were mastered hot (mean -7.3 / -4.6 dB, peaks at 0 dBFS); after the
gain cut both sit around -21.5 dB mean. `BossMusic.MUSIC_VOLUME_DB`
(`scripts/boss_music.gd`) trims a further -6 dB at runtime - tweak that by ear.
Looping is enabled in code (`BossMusic.start`).
