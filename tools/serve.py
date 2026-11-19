"""Short Circuit development host: serves the preview and optionally a compiled C++ core.
Uses only the Python standard library. The no-library mode is explicitly reported as
a browser reference adapter; it never claims that JavaScript is the native core.
"""
import argparse, ctypes, json, os, secrets, threading
from pathlib import Path
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
ROOT = Path(__file__).resolve().parents[1]
LOCK = threading.Lock()
TOKEN = secrets.token_urlsafe(24)
LIB = None
STORE = ROOT / "projects"
STORE.mkdir(exist_ok=True)
def native_request(payload):
    with LOCK:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        ptr = LIB.sc_request(data)
        if not ptr:
            raise RuntimeError("Native allocation failed")
        try:
            return json.loads(ctypes.string_at(ptr).decode("utf-8"))
        finally:
            LIB.sc_free(ptr)
class Handler(SimpleHTTPRequestHandler):
    def __init__(self,*args,**kwargs):
        super().__init__(*args,directory=str(ROOT),**kwargs)
    def end_headers(self):
        self.send_header("X-Content-Type-Options","nosniff")
        self.send_header("Cache-Control","no-store")
        super().end_headers()
    def json_response(self,data,status=200):
        data=json.dumps(data,ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type","application/json; charset=utf-8")
        self.send_header("Content-Length",str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def do_GET(self):
        if self.path=="/api/status":
            return self.json_response({"native":LIB is not None,"token":TOKEN})
        if self.path=="/":
            self.send_response(302);self.send_header("Location","/preview/");self.end_headers();return
        super().do_GET()
    def do_POST(self):
        if self.path!="/api/request":
            return self.json_response({"ok":False,"error":"Not found"},404)
        if self.headers.get("X-SC-Token")!=TOKEN:
            return self.json_response({"ok":False,"error":"Invalid request token"},403)
        if LIB is None:
            return self.json_response({"ok":False,"error":"Native core is not compiled"},503)
        try:
            n=int(self.headers.get("Content-Length","0"))
            if not 0<n<=2097152: raise ValueError("Request exceeds 2 MB")
            payload=json.loads(self.rfile.read(n))
            if payload.get("op") not in {"simulate","transient","validate","save","load","list"}:
                raise ValueError("Unknown operation")
            payload["directory"]=str(STORE)
            self.json_response(native_request(payload))
        except Exception as e:
            self.json_response({"ok":False,"error":str(e)},400)
    def log_message(self,fmt,*args):
        if args and str(args[0]).startswith(("GET /api","POST")): return
        super().log_message(fmt,*args)
def main():
    global LIB
    parser=argparse.ArgumentParser()
    parser.add_argument("--port",type=int,default=8765)
    parser.add_argument("--library",type=Path)
    args=parser.parse_args()
    candidates=[args.library] if args.library else [ROOT/"build"/"Release"/"short_circuit_core.dll",ROOT/"build"/"short_circuit_core.dll",ROOT/"build"/"libshort_circuit_core.so",ROOT/"build"/"libshort_circuit_core.dylib"]
    for p in candidates:
        if p and p.exists():
            LIB=ctypes.CDLL(str(p))
            LIB.sc_request.argtypes=[ctypes.c_char_p];LIB.sc_request.restype=ctypes.c_void_p
            LIB.sc_free.argtypes=[ctypes.c_void_p];LIB.sc_free.restype=None
            break
    print("Native C++ core connected" if LIB else "Browser reference preview (native C++ not compiled)",flush=True)
    print(f"Open http://127.0.0.1:{args.port}/preview/",flush=True)
    ThreadingHTTPServer(("127.0.0.1",args.port),Handler).serve_forever()
if __name__=="__main__": main()

