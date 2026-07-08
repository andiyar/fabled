#!/usr/bin/env python3
"""Test the CLI control-protocol handshake: initialize with canUseTool,
then verify permission requests arrive as control_request events and
that an 'allow' control_response lets the tool run."""
import json, subprocess, sys, threading, time

CMD = [
    "claude", "-p", "--verbose",
    "--input-format", "stream-json",
    "--output-format", "stream-json",
    "--model", "haiku",
    "--setting-sources", "",
    "--permission-prompt-tool", "stdio",
]

proc = subprocess.Popen(CMD, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, text=True, bufsize=1,
                        cwd="/private/tmp/claude-504/-Users-andiyar-Developer/1cccabcb-f249-49ae-8924-06e6b0f39c68/scratchpad/protocol-test")

def send(obj):
    proc.stdin.write(json.dumps(obj) + "\n")
    proc.stdin.flush()
    print(f">>> sent: {json.dumps(obj)[:160]}", flush=True)

# 1. initialize handshake declaring we handle permission prompts
send({"type": "control_request", "request_id": "init-1",
      "request": {"subtype": "initialize", "hooks": {}}})

# 2. the actual user message
send({"type": "user", "message": {"role": "user",
      "content": "Run exactly this bash command: git init"}})

deadline = time.time() + 90
def watchdog():
    while time.time() < deadline:
        time.sleep(1)
    proc.kill()
threading.Thread(target=watchdog, daemon=True).start()

for line in proc.stdout:
    line = line.strip()
    if not line:
        continue
    try:
        e = json.loads(line)
    except json.JSONDecodeError:
        print(f"RAW: {line[:200]}", flush=True)
        continue
    t = e.get("type")
    if t == "control_response":
        print(f"<<< control_response: {json.dumps(e)[:400]}", flush=True)
    elif t == "control_request":
        req = e.get("request", {})
        print(f"<<< CONTROL_REQUEST subtype={req.get('subtype')}: {json.dumps(e)[:500]}", flush=True)
        if req.get("subtype") == "can_use_tool":
            # approve it
            send({"type": "control_response",
                  "response": {"subtype": "success",
                               "request_id": e.get("request_id"),
                               "response": {"behavior": "allow",
                                            "updatedInput": req.get("input")}}})
    elif t == "assistant":
        for c in e["message"].get("content", []):
            if c["type"] == "text":
                print(f"<<< assistant: {c['text'][:200]}", flush=True)
            elif c["type"] == "tool_use":
                print(f"<<< tool_use: {c['name']} {json.dumps(c.get('input', {}))[:120]}", flush=True)
    elif t == "user":
        print(f"<<< tool_result: {str(e['message'].get('content'))[:250]}", flush=True)
    elif t == "result":
        print(f"<<< result: {e.get('subtype')} denials={json.dumps(e.get('permission_denials'))[:200]}", flush=True)
        proc.stdin.close()
        break
    else:
        print(f"<<< {t} {e.get('subtype', '')}", flush=True)

proc.wait(timeout=10)
print(f"exit code: {proc.returncode}")
