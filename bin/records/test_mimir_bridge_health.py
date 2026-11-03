import importlib.util,json,subprocess,sys,tempfile,threading,unittest
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
ROOT=Path(__file__).resolve().parents[2]
POLICY=ROOT/'bin/records/mimir-policy.py'
class BridgeHealth(unittest.TestCase):
 def test_owner_health_and_fail_closed(self):
  row=dict(episodes=7,voided=0,stores={'episodic':7},healthy=False,why='grading overdue',last_observe=None,last_recall=None,last_daily=None,last_prune=None)
  class Handler(BaseHTTPRequestHandler):
   def do_GET(self):
    self.send_response(200); self.end_headers(); self.wfile.write(json.dumps(row).encode())
   def log_message(self,*a): pass
  server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
  thread=threading.Thread(target=server.serve_forever,daemon=True); thread.start()
  try:
   args=[sys.executable,str(POLICY),'memory','--bridge',f'http://127.0.0.1:{server.server_port}','--json','--check']
   result=subprocess.run(args,capture_output=True,text=True)
   self.assertEqual(result.returncode,1)
   data=json.loads(result.stdout); self.assertEqual(data['episodes'],7); self.assertEqual(data['measurement'],'bridge')
   row['healthy']=True
   self.assertEqual(subprocess.run(args,capture_output=True).returncode,0)
   row.clear()
   result=subprocess.run(args,capture_output=True,text=True)
   self.assertEqual(result.returncode,1); self.assertIn('does not provide memory health',result.stdout)
  finally: server.shutdown(); server.server_close(); thread.join()
  result=subprocess.run(args,capture_output=True,text=True)
  self.assertEqual(result.returncode,1); self.assertIn('unavailable',result.stdout)
if __name__=='__main__': unittest.main()
