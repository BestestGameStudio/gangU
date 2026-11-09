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
