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

At runtime `MusicDirector.BOSS_VOLUME_DB` (`game/audio/music_director.gd`) applies a
further -6 dB. Looping is set in code (`MusicDirector.start_boss`), not in the import.

# Overworld soft piano (#487)

`overworld_soft_piano_loop.ogg` is the overworld music Colin approved on
2026-11-09 (iMessage: "make this the new overworld music and keep the volume
low"). It replaces the #477 nature ambience, which is removed. The Ogg Vorbis
(q5, 48 kHz stereo, 81.778 s) is the file delivered with the approved v2 mix,
unchanged (no trimming, no gain edit). The approved sample was an AAC copy of
the same mix; the Ogg was encoded by its creator and is not the exact bytes
Colin heard.

Composition: original melody and arrangement written 2026-11-09 for this game;
no existing musical work was sampled, quoted or adapted. Sparse, very soft
piano with long rests, light room reverb, no ambience bed (no wind, water or
bush rustling).

Piano sound (third party, attribution required): "Salamander Grand Piano V3"
by Alexander Holm, licensed CC BY 3.0
(https://creativecommons.org/licenses/by/3.0/). Source:
https://github.com/sfzinstruments/SalamanderGrandPiano (recording also at
https://archive.org/details/SalamanderGrandPianoV3). Yamaha C5, only the soft
sustain layers (v3 to v6 of 16) were used, no hammer, pedal or resonance
samples. Required credit line: "Piano sound: Salamander Grand Piano V3 by
Alexander Holm, licensed CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/)".
Add this to any in-game credits screen if one is added.

The track is quiet on purpose. Levels (`ffmpeg -af volumedetect` on the Ogg):
mean -37.3 dB, peak -15.1 dB. **Do not normalize or loudness-match it up.**
It starts from silence and fades to silence over the last 4 s, so the loop
restarts after a short natural pause. `MusicDirector`
(`game/audio/music_director.gd`, `start_overworld`) plays it at 0 dB, with no trim. Looping is set
in code, not in the import. The lossless WAV master is not committed.

Checksums of the delivered files: OGG md5 `31a6a511540334b7109de61b73fa2bcc`,
WAV master md5 `48ebb0b80daedb89edb84f39b1991315`.

# Dungeon music (#471)

`dungeon_battle_loop.ogg` is the default dungeon loop Colin approved on
2026-11-09 (iMessage: "Make that the default dungeon music"). It is an original
composition synthesized locally by Instinct (retro square-wave lead with echo,
saw bass, chiptune drums, quiet low drone; D minor, 140 BPM, 32 bars, 54.857 s,
44.1 kHz stereo). No samples and no third-party music.

The committed file is the delivered OGG unchanged (no trimming, no gain edit).
Levels (`ffmpeg -af volumedetect`): mean -14.9 dB, peak -0.1 dB. At runtime
`MusicDirector.DUNGEON_VOLUME_DB` (`game/audio/music_director.gd`, -13 dB) brings it
near the boss themes' effective level (about -21.5 dB mean, then their -6 dB).
Looping is set in code (`MusicDirector.start_dungeon`), not in the import. The lossless
WAV master is not committed.

## #597 overworld remix preview (not integrated)

Candidate percussion source: **"Loop - Night Run.mp3" by McChaffe**, Freesound sound330411, published2015-12-07.
- Source: https://freesound.org/people/McChaffe/sounds/330411/
- License: Creative Commons Attribution3.0 Unported, https://creativecommons.org/licenses/by/3.0/ . Remixing and redistribution are permitted with attribution, a license link and a description of changes. No endorsement is implied.
- Preview source: the page's public HQ MP3 preview, https://cdn.freesound.org/previews/330/330411_4263416-hq.mp3 . This is not the login-required original download.
- Planned processing: blend a quieter percussion bed with the existing original overworld piano, align phrase timing and preserve a soft ending. A listening preview must be approved before replacing the in-game asset. This attribution entry alone changes no game audio.
