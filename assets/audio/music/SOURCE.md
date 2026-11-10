# Boss music (#359)

Both tracks come from the two attachments on issue #359 (opened by
`Mitravasu`, text: "I got two boss themes here, use them for any red bosses!
... dampen them quite a bit before using!"). Nothing further about their origin
is recorded here.

| File | Source attachment | Source format (ffprobe) | Processing |
|------|-------------------|-------------------------|------------|
| `boss1.ogg` | `boss1.mp3` - https://github.com/user-attachments/files/34565547/boss1.mp3 | MP3, 44.1 kHz stereo, 160 kb/s, 24.07 s | `ffmpeg -i boss1.mp3 -af volume=-15dB -c:a libvorbis -q:a 5 boss1.ogg` |
| `boss2.ogg` | `boss2.wav` - https://github.com/user-attachments/files/34565548/boss2.wav | PCM s24le WAV, 44.1 kHz stereo, 48.00 s | `ffmpeg -i boss2.wav -af volume=-17dB -c:a libvorbis -q:a 5 boss2.ogg` |

No other edits (no trimming, EQ, compression or resampling).

Levels (`ffmpeg -af volumedetect`):

| File | mean | peak |
|------|------|------|
| `boss1.mp3` (source) | -7.3 dB | 0.0 dB |
| `boss2.wav` (source) | -4.6 dB | 0.0 dB |
| `boss1.ogg` (committed) | -21.7 dB | -8.1 dB |
| `boss2.ogg` (committed) | -21.5 dB | -14.6 dB |

Re-running the two commands above on the attachments reproduces the committed
files' decoded audio exactly (matching `ffmpeg -f md5` of the decoded PCM).

At runtime `BossMusic.MUSIC_VOLUME_DB` (`scripts/boss_music.gd`) applies a
further -6 dB. Looping is set in code (`BossMusic.start`), not in the import.

# Overworld ambience (#477)

`overworld_ambience_loop.ogg` is the overworld ambience Colin approved on
2026-11-09 (iMessage: add it as the overworld sound). It is an original
nature-only loop synthesized locally by Instinct: mostly silence, sparse quiet
birds and brief leaf rustles. No music, no wind bed, no water or rain sound and
no continuous noise. 45.714 s, 44.1 kHz stereo. No samples and no third-party
audio.

The committed file is the delivered OGG unchanged (no trimming, no gain edit).
It is quiet on purpose. Levels (`ffmpeg -af volumedetect` on the WAV master):
mean -44.6 dB, peak -13.3 dB. **Do not normalize or loudness-match it up.**
`OverworldAmbience` (`scripts/overworld_ambience.gd`) plays it at 0 dB, with no
trim. Looping is set in code, not in the import. The lossless WAV master is not
committed.

Checksums of the delivered files: OGG md5 `40bfc5d8447dcf5d6e95ddba7c29f4e2`,
WAV master md5 `d8c4dba127824d732916d98fa3cd90d4`.

# Dungeon music (#471)

`dungeon_battle_loop.ogg` is the default dungeon loop Colin approved on
2026-11-09 (iMessage: "Make that the default dungeon music"). It is an original
composition synthesized locally by Instinct (retro square-wave lead with echo,
saw bass, chiptune drums, quiet low drone; D minor, 140 BPM, 32 bars, 54.857 s,
44.1 kHz stereo). No samples and no third-party music.

The committed file is the delivered OGG unchanged (no trimming, no gain edit).
Levels (`ffmpeg -af volumedetect`): mean -14.9 dB, peak -0.1 dB. At runtime
`DungeonMusic.MUSIC_VOLUME_DB` (`scripts/dungeon_music.gd`, -13 dB) brings it
near the boss themes' effective level (about -21.5 dB mean, then their -6 dB).
Looping is set in code (`DungeonMusic.start`), not in the import. The lossless
WAV master is not committed.
