#!/usr/bin/env python3
"""Probe 2: set_model/set_permission_mode ack shapes, mid-turn behavior,
and a second user message while a turn is in flight."""
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
      "content": "Count from 1 to 15, one number per line. No other text."}})

deadline = time.time() + 180
def watchdog():
    while time.time() < deadline:
        time.sleep(1)
    proc.kill()
threading.Thread(target=watchdog, daemon=True).start()

lines = []
state = "turn1"           # -> "between" -> "turn2" -> done
midturn_sent = False
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

    if t == "stream_event" and not midturn_sent and state == "turn1":
        midturn_sent = True
        # mid-turn: a second user message + a set_permission_mode control op
        send({"type": "user", "message": {"role": "user",
              "content": "Reply with exactly the word: QUEUED-OK"}})
        send({"type": "control_request", "request_id": "perm-1",
              "request": {"subtype": "set_permission_mode", "mode": "acceptEdits"}})

    if t == "control_response":
        resp = e.get("response", {})
        rid = resp.get("request_id")
        if rid != "init-1":
            print(f"<<< CONTROL_RESPONSE ({rid}): {json.dumps(e)}", flush=True)

    if t == "assistant":
        model = (e.get("message") or {}).get("model")
        texts = [c.get("text", "")[:60] for c in (e.get("message") or {}).get("content", [])
                 if c.get("type") == "text"]
        print(f"<<< assistant (model={model}): {texts}", flush=True)

    if t == "result":
        result_count += 1
        print(f"<<< RESULT #{result_count}: subtype={e.get('subtype')} num_turns={e.get('num_turns')} is_error={e.get('is_error')}", flush=True)
        if state == "turn1":
            # NOTE: if the queued message auto-runs as its own turn, we'll see
            # another result without sending anything.
            state = "between"
            send({"type": "control_request", "request_id": "model-1",
                  "request": {"subtype": "set_model", "model": "sonnet"}})
            # give the queued message a chance to produce its own result
        elif state == "between":
            state = "turn2"
            send({"type": "user", "message": {"role": "user",
                  "content": "What is 2+2? Reply with just the number."}})
        elif state == "turn2":
            proc.stdin.close()
            break

proc.wait(timeout=15)
with open(fixture_path, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"=== wrote {len(lines)} lines to {fixture_path}; results seen: {result_count}")
print(f"exit code: {proc.returncode}")
