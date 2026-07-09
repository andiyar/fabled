#!/usr/bin/env python3
"""Probe 7 (Plan 4): ExitPlanMode shapes and approve/deny semantics.
mode=approve -> allow the first ExitPlanMode; auto-allow everything after and
                watch whether implementation tools still arrive as can_use_tool
                (reveals the post-approval permission mode).
mode=deny    -> deny the first ExitPlanMode with feedback; approve the revised
                one; then close after result.
Session runs with --permission-mode plan.
"""
import json, subprocess, sys, threading, time, os

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
    "--permission-mode", "plan",
]

proc = subprocess.Popen(CMD, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, text=True, bufsize=1, cwd=cwd)

def send(obj):
    proc.stdin.write(json.dumps(obj) + "\n")
    proc.stdin.flush()
    print(f">>> sent: {json.dumps(obj)[:400]}", flush=True)

send({"type": "control_request", "request_id": "init-1",
      "request": {"subtype": "initialize", "hooks": {}}})
send({"type": "user", "message": {"role": "user", "content":
      "Plan how to add a README.md with one short paragraph describing this "
      "(empty) project. When your plan is ready, request approval. If approved, "
      "implement it."}})

deadline = time.time() + 180
def watchdog():
    while time.time() < deadline:
        time.sleep(1)
    proc.kill()
threading.Thread(target=watchdog, daemon=True).start()

exit_plan_count = 0
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
        sub = req.get("subtype")
        if sub == "can_use_tool":
            name = req.get("tool_name")
            print(f"<<< CAN_USE_TOOL (full): {json.dumps(e)[:2000]}", flush=True)
            if name == "ExitPlanMode":
                exit_plan_count += 1
                if mode == "deny" and exit_plan_count == 1:
                    resp = {"behavior": "deny",
                            "message": "Please add a licence section to the plan, then request approval again."}
                else:
                    resp = {"behavior": "allow", "updatedInput": req.get("input")}
            else:
                resp = {"behavior": "allow", "updatedInput": req.get("input")}
            send({"type": "control_response",
                  "response": {"subtype": "success",
                               "request_id": e.get("request_id"),
                               "response": resp}})
        else:
            print(f"<<< control_request subtype={sub}: {json.dumps(e)[:800]}", flush=True)
    elif t == "system":
        print(f"<<< system subtype={e.get('subtype')}: {json.dumps(e)[:400]}", flush=True)
    elif t == "user":
        print(f"<<< tool_result: {json.dumps(e)[:800]}", flush=True)
    elif t == "assistant":
        for b in ((e.get("message") or {}).get("content") or []):
            if b.get("type") == "tool_use":
                print(f"<<< assistant tool_use: {b.get('name')} input={json.dumps(b.get('input'))[:500]}", flush=True)
            elif b.get("type") == "text":
                print(f"<<< assistant text: {b.get('text')[:200]}", flush=True)
    elif t == "result":
        print(f"<<< RESULT: subtype={e.get('subtype')} is_error={e.get('is_error')} denials={json.dumps(e.get('permission_denials'))[:300]}", flush=True)
        proc.stdin.close()
        break

proc.wait(timeout=15)
with open(fixture_path, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"=== wrote {len(lines)} lines to {fixture_path}")
print(f"exit code: {proc.returncode}")
print(f"=== README created: {os.path.isfile(os.path.join(cwd, 'README.md'))}")
