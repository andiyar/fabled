#!/usr/bin/env python3
"""Probe 6 (Plan 4): AskUserQuestion request/response shapes.
mode=answer -> allow with updatedInput = {questions, answers:{<question text>: <label(s)>}}
               (bundle-derived hypothesis: answers keyed by exact question text,
                multi-select comma-separated)
mode=echo   -> allow with updatedInput = input verbatim (no answers) — what does
               the tool_result look like when nothing was selected?
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
      "Use the AskUserQuestion tool right now to ask me two questions: "
      "(1) 'Which color do you prefer?' with options Red and Blue; "
      "(2) 'Which sizes do you want?' with options Small, Medium, Large, "
      "with multiSelect enabled. Do not answer the questions yourself. "
      "After the tool returns, reply with exactly one line summarizing my answers."}})

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
            if req.get("tool_name") == "AskUserQuestion":
                questions = (req.get("input") or {}).get("questions", [])
                if mode == "answer":
                    answers = {}
                    for q in questions:
                        opts = [o.get("label") for o in q.get("options", [])]
                        if q.get("multiSelect"):
                            answers[q["question"]] = ", ".join(opts[:2])
                        else:
                            answers[q["question"]] = opts[-1] if opts else "?"
                    updated = dict(req.get("input") or {})
                    updated["answers"] = answers
                else:
                    updated = req.get("input")
                resp = {"behavior": "allow", "updatedInput": updated}
            else:
                resp = {"behavior": "allow", "updatedInput": req.get("input")}
            send({"type": "control_response",
                  "response": {"subtype": "success",
                               "request_id": e.get("request_id"),
                               "response": resp}})
    elif t == "user":
        print(f"<<< tool_result (full): {json.dumps(e)[:1500]}", flush=True)
    elif t == "assistant":
        blocks = ((e.get("message") or {}).get("content") or [])
        for b in blocks:
            if b.get("type") == "tool_use":
                print(f"<<< assistant tool_use: {b.get('name')} input={json.dumps(b.get('input'))[:600]}", flush=True)
            elif b.get("type") == "text":
                print(f"<<< assistant text: {b.get('text')[:300]}", flush=True)
    elif t == "result":
        print(f"<<< RESULT: subtype={e.get('subtype')} is_error={e.get('is_error')} denials={json.dumps(e.get('permission_denials'))[:300]}", flush=True)
        proc.stdin.close()
        break

proc.wait(timeout=15)
with open(fixture_path, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"=== wrote {len(lines)} lines to {fixture_path}")
print(f"exit code: {proc.returncode}")
