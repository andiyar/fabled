#!/usr/bin/env python3
"""Probe (4b plan-writing): slash commands over stream-json + --effort spawn.

Answers, on the live CLI:
  1. Is --effort accepted at spawn alongside the stream-json flags?
  2. Does the 2.1.206 initialize catalog list remote-control? What effort
     fields ride the catalog/init?
  3. What does sending "/effort low" as user text produce on the wire?
  4. What does "/remote-control" produce (QR/link/system events)?
  5. What does an unknown "/no-such-command-xyz" produce?
  6. Does the session still take a normal turn afterwards?

Usage: probe_slashfx.py <fixture-out.jsonl> <cwd>
"""
import json, subprocess, sys, threading, time, os

fixture_path = sys.argv[1]
cwd = sys.argv[2]
os.makedirs(cwd, exist_ok=True)

CMD = [
    "claude", "-p", "--verbose",
    "--input-format", "stream-json",
    "--output-format", "stream-json",
    "--model", "haiku",
    "--effort", "low",
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

def user(text):
    send({"type": "user", "message": {"role": "user", "content": text}})

send({"type": "control_request", "request_id": "init-1",
      "request": {"subtype": "initialize", "hooks": {}}})

deadline = time.time() + 240
def watchdog():
    while time.time() < deadline:
        time.sleep(1)
    print("!!! watchdog kill", flush=True)
    proc.kill()
threading.Thread(target=watchdog, daemon=True).start()

# stderr drain (never block the child)
def drain_err():
    for line in proc.stderr:
        print(f"[stderr] {line.rstrip()[:200]}", flush=True)
threading.Thread(target=drain_err, daemon=True).start()

lines = []
# Step machine: each step is (name, action). We advance on `result` events
# (slash commands may or may not produce one — also advance on a 12s lull).
steps = [
    ("turn1",      lambda: user("Reply with exactly the word: READY-OK")),
    ("effort",     lambda: user("/effort medium")),
    ("turn2",      lambda: user("Reply with exactly the word: EFFORT-OK")),
    ("remote",     lambda: user("/remote-control")),
    ("unknown",    lambda: user("/no-such-command-xyz")),
    ("turn3",      lambda: user("Reply with exactly the word: STILL-OK")),
]
step = -1
last_event = time.time()

def advance():
    global step, last_event
    step += 1
    last_event = time.time()
    if step < len(steps):
        name, action = steps[step]
        print(f"--- step {name}", flush=True)
        action()
    else:
        print("--- done, terminating", flush=True)
        try:
            proc.stdin.close()
        except Exception:
            pass

def lull_monitor():
    while proc.poll() is None and time.time() < deadline:
        time.sleep(1)
        # Slash commands may produce no result event; a 12 s lull advances.
        if 0 <= step < len(steps) and time.time() - last_event > 12:
            print(f"--- lull after {steps[step][0]}, advancing", flush=True)
            advance()
threading.Thread(target=lull_monitor, daemon=True).start()

got_init = False
for line in proc.stdout:
    line = line.strip()
    if not line:
        continue
    lines.append(line)
    last_event = time.time()
    try:
        e = json.loads(line)
    except json.JSONDecodeError:
        continue
    t = e.get("type")
    if t == "control_response" and not got_init:
        got_init = True
        cmds = (e.get("response", {}).get("response", {}) or {}).get("commands", [])
        names = [c.get("name") for c in cmds if isinstance(c, dict)]
        print(f"=== catalog commands ({len(names)}): "
              f"remote-related={[n for n in names if 'remote' in str(n)]} "
              f"effort={'effort' in names}", flush=True)
        advance()   # start turn1
    summary = json.dumps(e)[:220]
    print(f"<<< {t}/{e.get('subtype','')}: {summary}", flush=True)
    if t == "result":
        advance()

proc.wait()
with open(fixture_path, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"=== wrote {len(lines)} lines to {fixture_path}; exit={proc.returncode}", flush=True)
