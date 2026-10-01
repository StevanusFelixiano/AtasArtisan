#!/usr/bin/env python3
"""Live WhatsApp login QR for the VPS bridge. Run, open http://127.0.0.1:8765, scan.

Tunnels the bridge's loopback port over ssh, follows its SSE stream, and redraws
qr.png on every new code (each code lives ~20 s). Stops once WhatsApp reports `connected`.
"""
import json, os, subprocess, threading, http.server, urllib.request, time

DIR = "/tmp/ataste-qr"
os.makedirs(DIR, exist_ok=True)
token = subprocess.check_output(["security", "find-generic-password", "-s", "ataste.bridge-token", "-a", "ataste", "-w"], text=True).strip()
tunnel = subprocess.Popen(["ssh", "-N", "-L", "18090:127.0.0.1:8090", "vps"])
time.sleep(3)
open(f"{DIR}/index.html", "w").write("""<!doctype html><title>Ataste WhatsApp login</title>
<body style="font:16px system-ui;text-align:center;background:#FBF3EA;color:#2B1A12">
<h2>Link 0819-3610-0819</h2><p>WhatsApp → Settings → Linked devices → Link a device</p>
<img id=q width=360><p id=s></p>
<script>setInterval(()=>{fetch('state.txt?'+Date.now()).then(r=>r.text()).then(t=>s.textContent=t);q.src='qr.png?'+Date.now()},1500)</script>""")
open(f"{DIR}/state.txt", "w").write("waiting for a code…")

def follow():
    while True:  # the bridge restarts itself after WhatsApp removes a device; reconnect and keep going
        try:
            if stream():
                return
        except OSError:
            pass
        open(f"{DIR}/state.txt", "w").write("bridge restarting…")
        time.sleep(3)

def stream():
    req = urllib.request.Request("http://127.0.0.1:18090/api/events", headers={"Authorization": f"Bearer {token}"})
    for raw in urllib.request.urlopen(req):
        line = raw.decode().strip()
        if not line.startswith("data: "):
            continue
        ev = json.loads(line[6:])
        if ev.get("kind") == "qr":
            subprocess.run(["qrencode", "-s", "10", "-m", "3", "-o", f"{DIR}/qr.png"], input=ev["data"]["code"].encode())
            open(f"{DIR}/state.txt", "w").write(f"new code, valid {ev['data'].get('expires_in')} s")
        elif ev.get("kind") == "connected":
            open(f"{DIR}/state.txt", "w").write(f"Linked ✅ {ev['data'].get('phone')} — you can close this page.")
            os.remove(f"{DIR}/qr.png") if os.path.exists(f"{DIR}/qr.png") else None
            return True
        elif ev.get("kind") == "logged_out":
            open(f"{DIR}/state.txt", "w").write("WhatsApp removed the link right after pairing. Wait before scanning again.")

threading.Thread(target=follow, daemon=True).start()
os.chdir(DIR)
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 8765), lambda *a: http.server.SimpleHTTPRequestHandler(*a, directory=DIR))
try:
    srv.serve_forever()
finally:
    tunnel.terminate()
