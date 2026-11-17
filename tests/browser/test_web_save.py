"""Real exported WebGL integration test. Requires matching Godot web templates,
Python playwright, and Chrome. Uses an isolated project/profile, never a user save.
The mutation/readback bridge exists only in this throwaway fixture export.
Usage: python tests/browser/test_web_save.py --godot /path/to/godot --chrome /path/to/chrome
"""
import argparse,functools,http.server,json,pathlib,shutil,subprocess,tempfile,threading
from playwright.sync_api import sync_playwright

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--godot',required=True);ap.add_argument('--chrome',required=True);ap.add_argument('--output',default='/tmp/gangu-web-save-evidence');args=ap.parse_args()
 root=pathlib.Path(__file__).resolve().parents[2];out=pathlib.Path(args.output);out.mkdir(parents=True,exist_ok=True)
 with tempfile.TemporaryDirectory(prefix='gangu-web-test-') as temp:
  stage=pathlib.Path(temp)/'project';shutil.copytree(root,stage,ignore=shutil.ignore_patterns('.git','.godot','build','__pycache__'))
  probe=stage/'game/core/__web_save_probe.gd';shutil.copy(root/'tests/browser/web_save_probe.gd',probe)
  entry=stage/'game/core/main.gd';entry.write_text(entry.read_text().replace('web_save.start.call_deferred(self)','web_save.start.call_deferred(self)\n\t\tvar test_probe=preload("res://game/core/__web_save_probe.gd").new()\n\t\tadd_child.call_deferred(test_probe)'))
  web=pathlib.Path(temp)/'web';web.mkdir()
  with (out/'export.log').open('w') as log:
   for flags in [['--editor','--import'],['--export-debug','Web',str(web/'index.html')]]:
    subprocess.run([args.godot,'--headless','--path',str(stage),*flags],stdout=log,stderr=log,check=True)
  (web/'blank.html').write_text('<!doctype html><title>Storage test</title>')
  class Quiet(http.server.SimpleHTTPRequestHandler):
   def log_message(self,*args):pass
  server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=str(web)))
  threading.Thread(target=server.serve_forever,daemon=True).start();url=f'http://127.0.0.1:{server.server_port}'
  results={};console=[]
  with sync_playwright() as pw:
   browser=pw.chromium.launch(executable_path=args.chrome,headless=True,args=['--no-sandbox','--enable-unsafe-swiftshader'])
   context=browser.new_context(viewport={'width':1152,'height':648})
   def boot(page):
    page.on('console',lambda m:console.append(m.type+': '+m.text));page.on('pageerror',lambda e:console.append('PAGEERROR '+str(e)))
    page.goto(url+'/index.html');page.wait_for_function('typeof window.ganguTest === "function"',timeout=60000)
   def cmd(page,name):
    page.evaluate('(c)=>window.ganguTest(c)',name);return json.loads(page.evaluate('window.ganguTestResult'))
   def reload(page):
    page.reload();page.wait_for_function('typeof window.ganguTest === "function"',timeout=60000);return cmd(page,'state')
   page=context.new_page();boot(page);assert cmd(page,'state')['wallet']==0
   cmd(page,'seed');r=reload(page);results['refresh']=r
   assert (r['wallet'],r['tokens'],r['relics'],r['revives'],r['paid'],r['cleared'],r['hp'])==(321,3,1,2,4,True,100)
   assert r['slots'][0].endswith('hook_shot_rock.tres')
   page.screenshot(path=str(out/'restored.png'))
   cmd(page,'silent');r=reload(page);results['beforeunload']=r;assert r['wallet']==334
   cmd(page,'silent')
   page.evaluate("Object.defineProperty(document,'visibilityState',{get:()=> 'hidden',configurable:true});document.dispatchEvent(new Event('visibilitychange'))")
   page.close();page=context.new_page();boot(page);r=cmd(page,'state');results['hidden_and_reopen']=r;assert r['wallet']==347
   # Prevent writes to simulate quota exhaustion. Last successful save survives.
   page.evaluate("Storage.prototype.setItem=function(){throw new DOMException('quota','QuotaExceededError')};true")
   cmd(page,'add');r=cmd(page,'save');results['quota']=r;assert 'failed' in r['status']
   r=reload(page);assert r['wallet']==347
   cmd(page,'death');r=reload(page);results['death_during_pause']=r
   assert (r['wallet'],r['cleared'],r['paid'],r['revives'],r['relics'],r['tokens'])==(0,False,0,0,1,3)
   for name,raw in [('corrupt','{oops'),('future',json.dumps({'version':999}))]:
    page.goto(url+'/blank.html');page.evaluate('(s)=>localStorage.setItem("gangu.run.v1",s)',raw);boot(page)
    r=cmd(page,'state');results[name]=r;assert r['wallet']==0 and r['tokens']==0 and 'unreadable' in r['status']
   context.close()
   blocked=browser.new_context();blocked.add_init_script("const get=Storage.prototype.getItem;Storage.prototype.getItem=function(k){if(k==='gangu.run.v1')throw new DOMException('blocked','SecurityError');return get.call(this,k)};Storage.prototype.setItem=function(){throw new DOMException('blocked','SecurityError')}")
   page=blocked.new_page();boot(page);r=cmd(page,'state');results['blocked']=r;assert 'blocked' in r['status'] and r['hp']==100
   page.screenshot(path=str(out/'storage-blocked.png'));blocked.close();browser.close()
  server.shutdown()
  (out/'results.json').write_text(json.dumps(results,indent=2));(out/'console.log').write_text('\n'.join(console))
  assert not any('SCRIPT ERROR' in line or 'PAGEERROR' in line for line in console),console
  print('PASS: refresh, beforeunload, visibilitychange, tab close/reopen, quota, death pause, corrupt/future, blocked storage')
if __name__=='__main__':main()
