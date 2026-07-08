#!/usr/bin/env python3
"""Probe 4: interrupt mid-turn — ack shape and resulting event sequence."""
import json, subprocess, sys, threading, time, os

fixture_path = sys.argv[1]
cwd = sys.argv[2]
os.makedirs(cwd, exist_ok=True)

CMD = [
    "claude", "-p", "--verbose",
    "--input-format", "stream-json",
    "--output-format", "stream-json",
    "--model", "haiku",
    "--setting-sources", "",
    "--permission-prompt-tool", "stdio",
    "--include-partial-messages",
]

proc = subprocess.Popen(CMD, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, text=True, bufsize=1, cwd=cwd)

def send(obj):
    proc.stdin.write(json.dumps(obj) + "\n")
    proc.stdin.flush()
    print(f">>> sent: {json.dumps(obj)[:160]}", flush=True)

send({"type": "control_request", "request_id": "init-1",
      "request": {"subtype": "initialize", "hooks": {}}})
send({"type": "user", "message": {"role": "user",
      "content": "Write a 500-word essay about rivers."}})

deadline = time.time() + 120
def watchdog():
    while time.time() < deadline:
        time.sleep(1)
    proc.kill()
threading.Thread(target=watchdog, daemon=True).start()

lines = []
interrupted = False
deltas_seen = 0
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
    if t == "stream_event":
        if e["event"].get("type") == "content_block_delta":
            deltas_seen += 1
            if deltas_seen == 3 and not interrupted:
                interrupted = True
                send({"type": "control_request", "request_id": "int-1",
                      "request": {"subtype": "interrupt"}})
    elif t == "control_response":
        resp = e.get("response", {})
        if resp.get("request_id") != "init-1":
            print(f"<<< CONTROL_RESPONSE: {json.dumps(e)}", flush=True)
    elif t == "result":
        print(f"<<< RESULT: {json.dumps({k: e.get(k) for k in ['subtype', 'is_error', 'result']})[:300]}", flush=True)
        proc.stdin.close()
        break
    else:
        print(f"<<< {t} {e.get('subtype', '')}", flush=True)

proc.wait(timeout=15)
with open(fixture_path, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"=== wrote {len(lines)} lines to {fixture_path}")
print(f"exit code: {proc.returncode}")
