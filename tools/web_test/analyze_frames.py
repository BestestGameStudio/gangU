#!/usr/bin/env python3
"""gangU web_test frame analysis: contact sheets, burst extraction, localized event flagging.

Usage:
  python3 analyze_frames.py take.webm --sheet            # 1 fps tiled overview sheet(s)
  python3 analyze_frames.py take.webm --burst 4.0 6.5    # every frame from t=4.0..6.5
  python3 analyze_frames.py take.webm --flag             # localized brightness-jump flags

Outputs land next to the video, named after it:
  <stem>_sheet1.png [, <stem>_sheet2.png for takes > 64s]
  <stem>_burst/f%05d.png

Requires: ffmpeg on PATH. Pillow only for --flag (pip install pillow).
"""
import argparse, os, subprocess, sys, tempfile

def run(cmd):
    print('+', ' '.join(cmd))
    subprocess.run(cmd, check=True)

def main():
    p = argparse.ArgumentParser()
    p.add_argument('video')
    p.add_argument('--sheet', action='store_true')
    p.add_argument('--burst', nargs=2, type=float, metavar=('T0', 'T1'))
    p.add_argument('--flag', action='store_true')
    a = p.parse_args()

    stem = os.path.splitext(os.path.basename(a.video))[0]
    outdir = os.path.dirname(os.path.abspath(a.video))
    sheet = os.path.join(outdir, stem + '_sheet%d.png')
    burstdir = os.path.join(outdir, stem + '_burst')

    if a.sheet:
        run(['ffmpeg', '-y', '-i', a.video, '-vf', 'fps=1,scale=320:180,tile=8x8',
             '-frames:v', '2', sheet])
        print(f'wrote {stem}_sheet1.png (and {stem}_sheet2.png for takes > 64s)')
    if a.burst:
        os.makedirs(burstdir, exist_ok=True)
        run(['ffmpeg', '-y', '-i', a.video,
             '-vf', f"select='between(t,{a.burst[0]},{a.burst[1]})'", '-vsync', '0',
             os.path.join(burstdir, 'f%05d.png')])
        print(f'frames in {burstdir}/')
    if a.flag:
        # Localized frame-diff flagger. STATUS [OPEN]: on the 2026-11-07 build this flagged
        # both real hit flashes and unrelated motion/floor artifacts; treat flags as
        # candidates to eyeball with --burst, never as automated proof.
        from PIL import Image, ImageChops
        import glob, statistics
        frames = sorted(glob.glob(os.path.join(burstdir, 'f*.png')))
        tmp = None
        if not frames:
            # No burst extracted yet: sample the take at 4 fps into a temp dir.
            tmp = tempfile.mkdtemp(prefix='flag_')
            run(['ffmpeg', '-y', '-i', a.video, '-vf', 'fps=4',
                 os.path.join(tmp, 'f%05d.png')])
            frames = sorted(glob.glob(os.path.join(tmp, 'f*.png')))
            print(f'no burst found; analyzing {len(frames)} sampled frames at 4 fps')
        if len(frames) < 2:
            sys.exit('need at least 2 frames to diff')
        cells = (8, 4)
        scores = []
        prev = None
        for f in frames:
            im = Image.open(f).convert('L')
            w, h = im.size
            if prev is not None:
                diff = ImageChops.difference(im, prev)
                px = diff.load()
                cell_scores = []
                for cy in range(cells[1]):
                    for cx in range(cells[0]):
                        vals = [px[x, y] for y in range(cy*h//cells[1], (cy+1)*h//cells[1], 6)
                                       for x in range(cx*w//cells[0], (cx+1)*w//cells[0], 6)]
                        cell_scores.append(statistics.mean(vals))
                scores.append((os.path.basename(f), max(cell_scores),
                               cell_scores.index(max(cell_scores))))
            prev = im
        if scores:
            thresh = statistics.mean(s for _, s, _ in scores) + 3 * statistics.pstdev(s for _, s, _ in scores)
            flagged = [(f, round(s, 1), c) for f, s, c in scores if s > thresh]
            print('flagged (frame, score, cell):', flagged if flagged else 'none above threshold')

if __name__ == '__main__':
    main()
