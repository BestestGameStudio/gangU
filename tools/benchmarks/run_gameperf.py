#!/usr/bin/env python3
"""Run the same opt-in diagnostic overlay on two local revisions, no serving."""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefold', required=True, type=Path)
    parser.add_argument('--current', required=True, type=Path)
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--seed', type=int, default=548)
    args = parser.parse_args()
    probe = ROOT / 'game/core/game_perf_probe.gd'
    bench = HERE / 'gameperf_benchmark.gd'
    tool_hashes = {p.name: digest(p) for p in (probe, bench, Path(__file__))}
    version = subprocess.check_output([args.godot, '--version'], text=True).strip()
    bundle = {'tool_sha256': tool_hashes, 'runs': [], 'limitations': [
        'Local headless fixed-step callback cadence, not browser/render duration or FPS.',
        'A is unequal natural arrival, not matched combat.',
        'B is identical isolated common systems, not folded activation/browser acceptance.',
        'No calibration, regression threshold or completion of548/550/551.']}
    # Check the common production dependency directories rather than assume B equality.
    dep_roots = ['game/player', 'game/enemies', 'game/spells', 'game/combat',
                 'game/terrain', 'data/enemies', 'data/spells', 'data/sprites']
    def manifest(root):
        return {str(p.relative_to(root)): digest(p)
                for d in dep_roots for p in sorted((root / d).rglob('*'))
                if p.is_file() and not p.name.endswith(('.import', '.uid'))}
    before, after = manifest(args.prefold.resolve()), manifest(args.current.resolve())
    bundle['common_dependency_differences'] = sorted(
        k for k in before.keys() | after.keys() if before.get(k) != after.get(k))
    for label, source in [('prefold', args.prefold), ('current', args.current)]:
        source = source.resolve()
        revision = git(source, 'rev-parse', 'HEAD')
        dirty = git(source, 'status', '--porcelain', '--untracked-files=normal')
        with tempfile.TemporaryDirectory(prefix='gangu-gameperf-') as tmp:
            tmp = Path(tmp)
            project = tmp / 'project'
            shutil.copytree(source, project, ignore=shutil.ignore_patterns('.git', '.godot'))
            (project / 'tools/benchmarks').mkdir(parents=True, exist_ok=True)
            shutil.copy2(probe, project / 'game/core/game_perf_probe.gd')
            shutil.copy2(bench, project / 'tools/benchmarks/gameperf_benchmark.gd')
            env = dict(os.environ, XDG_DATA_HOME=str(tmp / 'data'),
                       XDG_CONFIG_HOME=str(tmp / 'config'), XDG_CACHE_HOME=str(tmp / 'cache'))
            imported = subprocess.run([args.godot, '--headless', '--path', str(project),
                                       '--editor', '--import'], env=env,
                                      capture_output=True, text=True, timeout=45)
            if imported.returncode or 'SCRIPT ERROR:' in imported.stderr:
                raise RuntimeError(f'{label} import failed: {imported.stderr}')
            for workload in (['OFF', 'A', 'B'] if label == 'prefold' else ['OFF', 'ON', 'A', 'B']):
                # Isolated user state per run; no saved output can pass OFF inspection.
                env['XDG_DATA_HOME'] = str(tmp / ('data-' + workload))
                command = [
                    args.godot, '--headless', '--path', str(project), '--fixed-fps', '60',
                    '--quit-after', '360', '--script', 'res://tools/benchmarks/gameperf_benchmark.gd', '--',
                    '--gameperf-sha=' + revision, '--workload=' + workload,
                    '--seed=' + str(args.seed)]
                if workload == 'ON':
                    command.append('--gameperf')
                result = subprocess.run(command, env=env, capture_output=True,
                    text=True, timeout=45)
                marker = {'OFF': 'GAMEPERF_OFF_JSON ', 'ON': 'GAMEPERF_ON_JSON '}.get(workload, 'GAMEPERF_JSON ')
                lines = [s[len(marker):] for s in result.stdout.splitlines() if s.startswith(marker)]
                meta = {'commit_sha': revision, 'godot_version': version,
                        'backend': 'headless/dummy renderer', 'seed': args.seed,
                        'frame_schedule': 'fixed-fps60; boot3/warm30/capture180 physics ticks',
                        'source_label': label, 'workload': workload, 'source_dirty': dirty,
                        'machine': platform.uname()._asdict(),
                        'tool_sha256': tool_hashes}
                payload = json.loads(lines[-1]) if lines else None
                entry = {'metadata': meta, 'returncode': result.returncode,
                         'result': payload, 'engine_stdout': result.stdout,
                         'engine_stderr': result.stderr}
                bundle['runs'].append(entry)
                args.output.parent.mkdir(parents=True, exist_ok=True)
                args.output.write_text(json.dumps(bundle, indent=2) + '\n')
                print(json.dumps({'metadata': meta, 'export': str(args.output),
                                  'returncode': result.returncode,
                                  'captured': payload is not None}))
                if result.returncode or payload is None or 'SCRIPT ERROR:' in result.stderr:
                    raise RuntimeError('Diagnostic failed; details retained in output envelope')
    # OFF is a structural default-off check, not a visual or timing equivalence claim.
    off = [r['result'] for r in bundle['runs'] if r['metadata']['workload'] == 'OFF']
    bundle['default_off_same_main_child_names'] = off[0]['main_child_names'] == off[1]['main_child_names']
    args.output.write_text(json.dumps(bundle, indent=2) + '\n')


if __name__ == '__main__':
    run()
