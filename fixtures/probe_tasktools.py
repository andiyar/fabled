#!/usr/bin/env python3
"""Probe (4b plan-writing): TaskCreate/TaskUpdate/TaskList wire shapes.

TodoWrite is gone from this CLI config (FOLLOWUPS 2026-07-10); the pinned
checklist card must feed from the task tools instead. Capture on the live
wire: tool_use inputs, tool_result content, and whether the rich
tool_use_result rides `user` events (it does for AskUserQuestion).

Usage: probe_tasktools.py <fixture-out.jsonl> <cwd>
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
send({"type": "user", "message": {"role": "user", "content":
      "Use TaskCreate to create exactly three tasks: subjects 'Alpha task', "
      "'Beta task', 'Gamma task' (descriptions: anything short; give Alpha an "
      "activeForm of 'Alpha running'). Then use TaskUpdate to set Alpha to "
      "in_progress, then TaskUpdate Alpha to completed, then TaskUpdate to "
      "DELETE Gamma (status deleted). Then call TaskList. Then reply DONE-OK. "
      "If any tool is missing, reply MISSING:<toolname>."}})

deadline = time.time() + 240
def watchdog():
    while time.time() < deadline:
        time.sleep(1)
    print("!!! watchdog kill", flush=True)
    proc.kill()
threading.Thread(target=watchdog, daemon=True).start()

def drain_err():
    for line in proc.stderr:
        print(f"[stderr] {line.rstrip()[:200]}", flush=True)
threading.Thread(target=drain_err, daemon=True).start()

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
    # Auto-allow any permission request (task tools shouldn't need one, but
    # keep the turn moving if they do).
    if t == "control_request":
        req = e.get("request", {})
        if req.get("subtype") == "can_use_tool":
            send({"type": "control_response", "response": {
                "subtype": "success", "request_id": e.get("request_id"),
                "response": {"behavior": "allow",
                             "updatedInput": req.get("input", {})}}})
    interesting = ("tool_use" in line and "Task" in line) or t in ("result", "user")
    if interesting:
        print(f"<<< {t}: {json.dumps(e)[:260]}", flush=True)
    if t == "result":
        try:
            proc.stdin.close()
        except Exception:
            pass
        break

proc.wait()
with open(fixture_path, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"=== wrote {len(lines)} lines to {fixture_path}; exit={proc.returncode}", flush=True)
