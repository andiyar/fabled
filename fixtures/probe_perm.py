#!/usr/bin/env python3
"""Probe 3: permission round-trip variants.
mode=noinput  -> allow with NO updatedInput field (tests .allow(updatedInput: nil))
mode=persist  -> allow with updatedPermissions echoing the CLI's suggestions;
                 afterwards inspect .claude/settings.local.json in the cwd.
"""
import json, subprocess, sys, threading, time, os, glob

mode = sys.argv[1]
fixture_path = sys.argv[2]
cwd = sys.argv[3]
os.makedirs(cwd, exist_ok=True)

CMD = [
    "claude", "-p", "--verbose",
    "--input-format", "stream-json",
    "--output-format", "stream-json",
    "--model", "haiku",
    "--permission-prompt-tool", "stdio",
    "--include-partial-messages",
]
if mode == "noinput":
    CMD += ["--setting-sources", ""]

proc = subprocess.Popen(CMD, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, text=True, bufsize=1, cwd=cwd)

def send(obj):
    proc.stdin.write(json.dumps(obj) + "\n")
    proc.stdin.flush()
    print(f">>> sent: {json.dumps(obj)[:300]}", flush=True)

send({"type": "control_request", "request_id": "init-1",
      "request": {"subtype": "initialize", "hooks": {}}})
send({"type": "user", "message": {"role": "user",
      "content": "Run exactly this bash command: git init"}})

deadline = time.time() + 120
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
    if t == "control_request":
        req = e.get("request", {})
        if req.get("subtype") == "can_use_tool":
            print(f"<<< CAN_USE_TOOL (full): {json.dumps(e)}", flush=True)
            resp = {"behavior": "allow"}
            if mode == "persist":
                resp["updatedInput"] = req.get("input")
                resp["updatedPermissions"] = req.get("permission_suggestions") or []
            send({"type": "control_response",
                  "response": {"subtype": "success",
                               "request_id": e.get("request_id"),
                               "response": resp}})
    elif t == "user":
        print(f"<<< tool_result: {str((e.get('message') or {}).get('content'))[:250]}", flush=True)
    elif t == "result":
        print(f"<<< RESULT: subtype={e.get('subtype')} is_error={e.get('is_error')} denials={json.dumps(e.get('permission_denials'))[:300]}", flush=True)
        proc.stdin.close()
        break

proc.wait(timeout=15)
with open(fixture_path, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"=== wrote {len(lines)} lines to {fixture_path}")
print(f"exit code: {proc.returncode}")
print(f"=== git dir created: {os.path.isdir(os.path.join(cwd, '.git'))}")
if mode == "persist":
    for p in glob.glob(os.path.join(cwd, ".claude", "*")):
        print(f"=== {p}:")
        print(open(p).read())
