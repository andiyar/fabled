#!/usr/bin/env python3
"""Probe 1: --include-partial-messages stream_event shapes + initialize
response (slash-command catalog). Records every raw stdout line to a fixture
file passed as argv[1]."""
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

send({"type": "control_request", "request_id": "init-1",
      "request": {"subtype": "initialize", "hooks": {}}})
send({"type": "user", "message": {"role": "user",
      "content": "Reply with exactly: The quick brown fox jumps over the lazy dog."}})

deadline = time.time() + 90
def watchdog():
    while time.time() < deadline:
        time.sleep(1)
    proc.kill()
threading.Thread(target=watchdog, daemon=True).start()

lines = []
subtype_census = {}
for line in proc.stdout:
    line = line.strip()
    if not line:
        continue
    lines.append(line)
    try:
        e = json.loads(line)
    except json.JSONDecodeError:
        print(f"RAW(non-json): {line[:200]}", flush=True)
        continue
    t = e.get("type")
    if t == "stream_event":
        ev = e.get("event", {})
        key = f"stream_event/{ev.get('type')}"
        subtype_census[key] = subtype_census.get(key, 0) + 1
    else:
        subtype_census[t] = subtype_census.get(t, 0) + 1
    if t == "control_response":
        resp = e.get("response", {})
        if resp.get("request_id") == "init-1":
            inner = resp.get("response") or {}
            print("=== INIT RESPONSE keys:", sorted(inner.keys()), flush=True)
            cmds = inner.get("commands")
            if isinstance(cmds, list) and cmds:
                print("=== first command entry:", json.dumps(cmds[0])[:400], flush=True)
                print("=== command count:", len(cmds), flush=True)
            print("=== INIT RESPONSE (truncated):", json.dumps(resp)[:600], flush=True)
    if t == "result":
        proc.stdin.close()
        break

proc.wait(timeout=15)
with open(fixture_path, "w") as f:
    f.write("\n".join(lines) + "\n")
print("=== line-type census:", json.dumps(subtype_census, indent=None), flush=True)
print(f"=== wrote {len(lines)} lines to {fixture_path}")
print(f"exit code: {proc.returncode}")

# Show the first few stream_event lines verbatim for shape inspection
shown = 0
for line in lines:
    e = json.loads(line)
    if e.get("type") == "stream_event":
        print("STREAM_EVENT:", line[:500])
        shown += 1
        if shown >= 6:
            break
