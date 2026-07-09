#!/usr/bin/env python3
"""Probe 9 (Plan 4): turn-finished signal on a long autonomous turn.
Drives one user turn with many sequential tool uses (auto-allowing all
permissions) and logs the ORDER of every event type — verifying that `result`
fires exactly once per user turn and observing post_turn_summary cadence.
Usage: probe_longturn.py <fixture_path> <cwd>
"""
import json, subprocess, sys, threading, time, os

fixture_path = sys.argv[1]
cwd = sys.argv[2]
os.makedirs(cwd, exist_ok=True)

CMD = ["claude", "-p", "--verbose",
       "--input-format", "stream-json",
       "--output-format", "stream-json",
       "--model", "haiku",
       "--permission-prompt-tool", "stdio"]

proc = subprocess.Popen(CMD, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, text=True, bufsize=1, cwd=cwd)

def send(obj):
    proc.stdin.write(json.dumps(obj) + "\n")
    proc.stdin.flush()

send({"type": "control_request", "request_id": "init-1",
      "request": {"subtype": "initialize", "hooks": {}}})
send({"type": "user", "message": {"role": "user", "content":
      "Do all of the following in order, one tool call at a time, without "
      "asking me anything: create files n1.txt through n8.txt each containing "
      "its own number; then run `ls`; then run `cat n1.txt n8.txt`; then "
      "delete n3.txt; then run `ls` again; then summarize what you did in one "
      "sentence."}})
print(">>> sent long multi-tool task", flush=True)

deadline = time.time() + 240
def watchdog():
    while time.time() < deadline:
        time.sleep(1)
    proc.kill()
threading.Thread(target=watchdog, daemon=True).start()

t0 = time.time()
lines = []
counts = {}
result_count = 0
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
    sub = e.get("subtype") or (e.get("request", {}) or {}).get("subtype")
    key = f"{t}/{sub}" if sub else t
    counts[key] = counts.get(key, 0) + 1
    stamp = f"{time.time()-t0:6.1f}s"
    if t == "control_request" and sub == "can_use_tool":
        req = e.get("request", {})
        print(f"{stamp} can_use_tool {req.get('tool_name')}", flush=True)
        send({"type": "control_response",
              "response": {"subtype": "success",
                           "request_id": e.get("request_id"),
                           "response": {"behavior": "allow",
                                        "updatedInput": req.get("input")}}})
    elif t == "assistant":
        kinds = [b.get("type") for b in ((e.get("message") or {}).get("content") or [])]
        print(f"{stamp} assistant {kinds}", flush=True)
    elif t == "system" and sub not in ("thinking_tokens", "hook_started", "hook_response"):
        print(f"{stamp} system/{sub}: {json.dumps(e)[:250]}", flush=True)
    elif t == "result":
        result_count += 1
        print(f"{stamp} RESULT #{result_count} subtype={e.get('subtype')} num_turns={e.get('num_turns')}", flush=True)
        proc.stdin.close()
        break

proc.wait(timeout=15)
with open(fixture_path, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"=== event counts: {json.dumps(counts, indent=1, sort_keys=True)}")
print(f"=== result events: {result_count}")
print(f"=== wrote {len(lines)} lines to {fixture_path}")
