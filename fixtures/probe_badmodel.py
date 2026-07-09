#!/usr/bin/env python3
"""Probe 10 (Plan 4): error-ack shape for a rejected control op.
Sends set_model with a garbage model id and a bogus set_permission_mode,
captures the ack shapes (success vs error), then verifies with a normal turn
which model actually runs.
Usage: probe_badmodel.py <fixture_path> <cwd>
"""
import json, subprocess, sys, threading, time, os

fixture_path = sys.argv[1]
cwd = sys.argv[2]
os.makedirs(cwd, exist_ok=True)

CMD = ["claude", "-p", "--verbose",
       "--input-format", "stream-json",
       "--output-format", "stream-json",
       "--model", "haiku",
       "--setting-sources", "",
       "--permission-prompt-tool", "stdio"]

proc = subprocess.Popen(CMD, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, text=True, bufsize=1, cwd=cwd)

def send(obj):
    proc.stdin.write(json.dumps(obj) + "\n")
    proc.stdin.flush()
    print(f">>> sent: {json.dumps(obj)[:200]}", flush=True)

send({"type": "control_request", "request_id": "init-1",
      "request": {"subtype": "initialize", "hooks": {}}})
send({"type": "control_request", "request_id": "badmodel-1",
      "request": {"subtype": "set_model", "model": "totally-bogus-model-9000"}})
send({"type": "control_request", "request_id": "badmode-1",
      "request": {"subtype": "set_permission_mode", "mode": "notARealMode"}})
send({"type": "user", "message": {"role": "user",
      "content": "Reply with just the word: PING"}})

deadline = time.time() + 90
def watchdog():
    while time.time() < deadline:
        time.sleep(1)
    proc.kill()
threading.Thread(target=watchdog, daemon=True).start()

lines = []
for line in proc.stdout:
    line = line.strip()
    if not line:
        continue
    lines.append(line)
    try:
        e = json.loads(line)
    except json.JSONDecodeError:
        continue
    t = e.get("type")
    if t == "control_response":
        resp = e.get("response", {})
        if resp.get("request_id") != "init-1":
            print(f"<<< CONTROL_RESPONSE: {json.dumps(e)}", flush=True)
    elif t == "assistant":
        model = (e.get("message") or {}).get("model")
        texts = [c.get("text", "")[:60] for c in (e.get("message") or {}).get("content", [])
                 if c.get("type") == "text"]
        print(f"<<< assistant (model={model}): {texts}", flush=True)
    elif t == "system" and e.get("subtype") not in ("thinking_tokens",):
        print(f"<<< system/{e.get('subtype')}: {json.dumps(e)[:250]}", flush=True)
    elif t == "result":
        print(f"<<< RESULT subtype={e.get('subtype')} is_error={e.get('is_error')}", flush=True)
        proc.stdin.close()
        break

proc.wait(timeout=15)
with open(fixture_path, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"=== wrote {len(lines)} lines to {fixture_path}")
