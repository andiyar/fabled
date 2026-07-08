#!/usr/bin/env python3
"""Probe 5: does a --resume'd stream-json session replay prior events?"""
import json, subprocess, sys, threading, time, os

cwd = sys.argv[1]
os.makedirs(cwd, exist_ok=True)

BASE = [
    "claude", "-p", "--verbose",
    "--input-format", "stream-json",
    "--output-format", "stream-json",
    "--model", "haiku",
    "--setting-sources", "",
    "--permission-prompt-tool", "stdio",
    "--include-partial-messages",
]

def run(cmd, prompt, label):
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, bufsize=1, cwd=cwd)
    def send(obj):
        proc.stdin.write(json.dumps(obj) + "\n")
        proc.stdin.flush()
    send({"type": "control_request", "request_id": "init-1",
          "request": {"subtype": "initialize", "hooks": {}}})
    send({"type": "user", "message": {"role": "user", "content": prompt}})
    deadline = time.time() + 90
    def watchdog():
        while time.time() < deadline:
            time.sleep(1)
        proc.kill()
    threading.Thread(target=watchdog, daemon=True).start()

    session_id = None
    pre_result_events = []
    for line in proc.stdout:
        line = line.strip()
        if not line: continue
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        t = e.get("type")
        if t == "system" and e.get("subtype") == "init":
            session_id = e.get("session_id")
        marker = t
        if t == "stream_event": marker = "stream_event"
        if e.get("isReplay"): marker += "+isReplay"
        pre_result_events.append(marker)
        if t == "assistant":
            texts = [c.get("text","")[:60] for c in e["message"].get("content", []) if c.get("type")=="text"]
            if texts: print(f"[{label}] assistant: {texts}", flush=True)
        if t == "result":
            proc.stdin.close()
            break
    proc.wait(timeout=15)
    print(f"[{label}] session={session_id} events: {pre_result_events}", flush=True)
    return session_id

sid = run(BASE, "Remember the codeword ZEBRA-42. Confirm with just: OK", "first")
print("--- resuming ---", flush=True)
run(BASE + ["--resume", sid], "What is the codeword? Reply with just the codeword.", "resumed")
