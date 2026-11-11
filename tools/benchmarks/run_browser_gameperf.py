#!/usr/bin/env python3
"""Export isolated fixture from two public checkouts, serve ONLY localhost."""
import argparse
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import tempfile
import threading
import time
import urllib.request
import websocket

ROOT = Path(__file__).resolve().parents[2]
OVERLAY = ['tools/benchmarks/browser/benchmark.gd', 'tools/benchmarks/browser/benchmark.tscn',
           'game/core/game_perf_probe.gd']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(path, *args):
    return subprocess.check_output(['git', '-C', str(path), *args], text=True).strip()


class CDP:
    def __init__(self, port):
        for _ in range(100):
            try:
                with urllib.request.urlopen(f'http://127.0.0.1:{port}/json') as r:
                    tabs = json.load(r)
                self.ws = websocket.create_connection(next(t['webSocketDebuggerUrl'] for t in tabs if t['type'] == 'page'), timeout=30)
                self.n = 0
                self.events = []
                return
            except (OSError, StopIteration):
                time.sleep(.1)
        raise RuntimeError('Local Chrome debugger did not start')

    def call(self, method, params=None):
        self.n += 1
        self.ws.send(json.dumps({'id': self.n, 'method': method, 'params': params or {}}))
        while True:
            d = json.loads(self.ws.recv())
            if d.get('method') in ['Runtime.consoleAPICalled', 'Runtime.exceptionThrown']:
                self.events.append(d)
            if d.get('id') == self.n:
                if 'error' in d:
                    raise RuntimeError(d['error'])
                return d.get('result', {})

    def read(self, expression):
        return self.call('Runtime.evaluate', {'expression': expression, 'returnByValue': True}).get('result', {}).get('value')


def freeport():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def run():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--prefold', required=True, type=Path)
    p.add_argument('--current', required=True, type=Path)
    p.add_argument('--godot', default='godot')
    p.add_argument('--chrome', default='google-chrome')
    p.add_argument('--output', required=True, type=Path)
    a = p.parse_args()
    version = subprocess.check_output([a.godot, '--version'], text=True).strip()
    browser_version = subprocess.check_output([a.chrome, '--version'], text=True).strip()
    bundle = {'runs': [], 'limitations': 'Isolated common systems on same local software browser. NOT production34vs51 matched combat, folded activation, ordinary laptop FPS or threshold calibration.'}
    dependencies = ['game/player', 'game/enemies', 'game/spells', 'game/combat', 'game/terrain', 'data/enemies', 'data/spells', 'data/sprites']
    def manifest(root):
        return {str(x.relative_to(root)): sha(x) for d in dependencies for x in (root/d).rglob('*') if x.is_file() and not x.name.endswith(('.uid','.import'))}
    left, right = manifest(a.prefold), manifest(a.current)
    bundle['common_dependency_differences'] = sorted(k for k in left.keys() | right.keys() if left.get(k) != right.get(k))
    a.output.parent.mkdir(parents=True, exist_ok=True)
    for label, source in [('prefold', a.prefold), ('current', a.current)]:
        source = source.resolve()
        meta = {'commit_sha': git(source, 'rev-parse', 'HEAD'), 'source_dirty': git(source, 'status', '--porcelain'),
                'godot_version': version, 'browser_version': browser_version, 'seed': 548,
                'backend': 'Chrome ANGLE SwiftShader (software); actual engine renderer details in result',
                'frame_schedule': 'explicit Start;warm30/capture180 physics ticks at60Hz; raw process callbacks and browser RAF observed separately',
                'overlay_sha256': {x: sha(ROOT/x) for x in OVERLAY}, 'source_label': label,
                'viewport': [1152,648], 'opt_in_only': True}
        with tempfile.TemporaryDirectory(prefix='gangu-browser-perf-') as tmp:
            tmp = Path(tmp)
            project, build = tmp/'project', tmp/'web'
            shutil.copytree(source, project, ignore=shutil.ignore_patterns('.git','.godot','__pycache__'))
            for x in OVERLAY:
                (project/x).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT/x, project/x)
            shutil.copy2(ROOT/'tools/benchmarks/browser/export_presets.cfg', project/'export_presets.cfg')
            config = project/'project.godot'
            s = config.read_text().replace('run/main_scene="res://game/core/main.tscn"', 'run/main_scene="res://tools/benchmarks/browser/benchmark.tscn"')
            config.write_text(s)
            (project/'tools/benchmarks/browser/provenance.json').write_text(json.dumps(meta))
            env = dict(os.environ, XDG_DATA_HOME=str(tmp/'data'), XDG_CONFIG_HOME=str(tmp/'config'))
            templates = Path.home()/'.local/share/godot/export_templates'
            (tmp/'data/godot').mkdir(parents=True,exist_ok=True)
            (tmp/'data/godot/export_templates').symlink_to(templates, target_is_directory=True)
            for cmd in [[a.godot,'--headless','--path',str(project),'--editor','--import'],
                        [a.godot,'--headless','--path',str(project),'--export-release','BrowserBenchmark',str(build/'index.html')]]:
                build.mkdir(exist_ok=True)
                completed = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=90)
                if completed.returncode or 'SCRIPT ERROR:' in completed.stderr:
                    raise RuntimeError('Normal local export failed, no bypass: '+completed.stderr)
            handler = functools.partial(QuietHandler, directory=str(build))
            server = http.server.ThreadingHTTPServer(('127.0.0.1',0),handler)
            thread = threading.Thread(target=server.serve_forever)
            thread.start()
            port = freeport()
            log = open(tmp/'chrome.log','w')
            chrome = subprocess.Popen([a.chrome,'--headless=new','--no-sandbox','--disable-dev-shm-usage',
                '--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader',
                '--remote-allow-origins=http://127.0.0.1:'+str(port), '--remote-debugging-port='+str(port),
                '--user-data-dir='+str(tmp/'chrome-profile'),'--window-size=1152,648','about:blank'],stdout=log,stderr=log,start_new_session=True)
            c = None
            try:
                c = CDP(port)
                c.call('Page.enable')
                c.call('Runtime.enable')
                downloads = tmp/'downloads'
                downloads.mkdir()
                c.call('Browser.setDownloadBehavior',{'behavior':'allow','downloadPath':str(downloads)})
                c.call('Emulation.setDeviceMetricsOverride',{'width':1152,'height':648,'deviceScaleFactor':1,'mobile':False})
                c.call('Page.navigate',{'url':f'http://127.0.0.1:{server.server_port}/index.html'})
                deadline = time.monotonic()+60
                while time.monotonic()<deadline:
                    text = c.read('document.body.innerText') or ''
                    # Canvas accessibility is not a readiness signal; inspect actual render frames.
                    loaded = c.read('!!document.querySelector("canvas") && document.querySelector("canvas").width>0 && !document.querySelector("#status:not([style*=none])")')
                    if loaded:
                        break
                    time.sleep(.25)
                time.sleep(2) # one bounded settling window, not account polling
                import base64
                off = c.call('Page.captureScreenshot',{'format':'png'})['data']
                (a.output.parent/(label+'-benchmark-off.png')).write_bytes(base64.b64decode(off))
                # Normal browser pointer events on explicit benchmark-only Start button.
                c.call('Input.dispatchMouseEvent',{'type':'mousePressed','x':130,'y':31,'button':'left','clickCount':1})
                c.call('Input.dispatchMouseEvent',{'type':'mouseReleased','x':130,'y':31,'button':'left','clickCount':1})
                deadline = time.monotonic()+45
                result = None
                while time.monotonic()<deadline:
                    result = c.read('window.ganguBrowserPerf || null')
                    if result:
                        break
                    time.sleep(.2)
                if not result:
                    raise RuntimeError('Benchmark did not complete after normal Start; no input/security workaround')
                image = c.call('Page.captureScreenshot',{'format':'png'})['data']
                (a.output.parent/(label+'-benchmark-done.png')).write_bytes(base64.b64decode(image))
                renderer = c.read("(()=>{let c=document.querySelector('canvas');let g=c.getContext('webgl2')||c.getContext('webgl');if(!g)return null;let e=g.getExtension('WEBGL_debug_renderer_info');return {renderer:g.getParameter(e?e.UNMASKED_RENDERER_WEBGL:g.RENDERER),vendor:g.getParameter(e?e.UNMASKED_VENDOR_WEBGL:g.VENDOR)};})()")
                c.call('Input.dispatchMouseEvent',{'type':'mousePressed','x':130,'y':103,'button':'left','clickCount':1})
                c.call('Input.dispatchMouseEvent',{'type':'mouseReleased','x':130,'y':103,'button':'left','clickCount':1})
                deadline=time.monotonic()+5
                while not (downloads/'browser-gameperf.json').exists() and time.monotonic()<deadline:
                    time.sleep(.1)
                downloaded=json.loads((downloads/'browser-gameperf.json').read_text())
                if downloaded != result:
                    raise RuntimeError('Downloaded JSON differs from console result')
                bundle['runs'].append({'metadata':meta,'result':result,'actual_browser_gl':renderer,'download_matches_console':True,'console_events':c.events})
                a.output.write_text(json.dumps(bundle,indent=2)+'\n')
                print(json.dumps({'metadata':meta,'captured':True,'export':str(a.output)}))
            finally:
                if c:
                    c.ws.close()
                os.killpg(chrome.pid, signal.SIGTERM)
                try:
                    chrome.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(chrome.pid, signal.SIGKILL); chrome.wait()
                log.close()
                server.shutdown(); server.server_close(); thread.join()
    a.output.write_text(json.dumps(bundle,indent=2)+'\n')


if __name__ == '__main__':
    run()
