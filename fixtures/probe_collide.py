#!/usr/bin/env python3
"""Probe 8 (Plan 4): deliberately violate the one-process-per-session-ID
invariant. Session A runs live with --session-id; while A is alive, session B
spawns with --resume <A's id>. Observe B's behavior, then confirm A still
works, then inspect what landed on disk.
Writes one raw JSONL fixture per child process (suffix -A / -B) so the
fixture guard tests can parse them.
Usage: probe_collide.py <fixture_path_base> <cwd>   (base without .jsonl)
"""
import json, subprocess, sys, threading, time, os, uuid, glob

fixture_base = sys.argv[1].removesuffix(".jsonl")
cwd = sys.argv[2]
os.makedirs(cwd, exist_ok=True)
session_id = str(uuid.uuid4())
print(f"=== session A id: {session_id}")

BASE = ["claude", "-p", "--verbose",
        "--input-format", "stream-json",
        "--output-format", "stream-json",
        "--model", "haiku",
        "--permission-prompt-tool", "stdio"]

per_child_lines = {"A": [], "B": []}

class Child:
    def __init__(self, tag, extra):
        self.tag = tag
        self.proc = subprocess.Popen(BASE + extra, stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     text=True, bufsize=1, cwd=cwd)
        self.stderr_lines = []
        threading.Thread(target=self._drain_stderr, daemon=True).start()

    def _drain_stderr(self):
        for line in self.proc.stderr:
            self.stderr_lines.append(line.rstrip())

    def send(self, obj):
        try:
            self.proc.stdin.write(json.dumps(obj) + "\n")
            self.proc.stdin.flush()
            print(f">>> [{self.tag}] sent: {json.dumps(obj)[:200]}", flush=True)
        except BrokenPipeError:
            print(f">>> [{self.tag}] BROKEN PIPE on send", flush=True)

    def read_until_result(self, timeout=90):
        """Read stdout lines until a result event or timeout; returns events."""
        deadline = time.time() + timeout
        events = []
        def reader():
            for line in self.proc.stdout:
                line = line.strip()
                if not line:
                    continue
                per_child_lines[self.tag].append(line)
                try:
                    e = json.loads(line)
                except json.JSONDecodeError:
                    continue
                events.append(e)
                t = e.get("type")
                if t == "system":
                    print(f"<<< [{self.tag}] system/{e.get('subtype')} session_id={e.get('session_id')}", flush=True)
                elif t == "assistant":
                    for b in ((e.get("message") or {}).get("content") or []):
                        if b.get("type") == "text":
                            print(f"<<< [{self.tag}] assistant: {b.get('text')[:120]}", flush=True)
                elif t == "control_request":
                    req = e.get("request", {})
                    if req.get("subtype") == "can_use_tool":
                        self.send({"type": "control_response",
                                   "response": {"subtype": "success",
                                                "request_id": e.get("request_id"),
                                                "response": {"behavior": "allow",
                                                             "updatedInput": req.get("input")}}})
                elif t == "result":
                    print(f"<<< [{self.tag}] RESULT subtype={e.get('subtype')} is_error={e.get('is_error')} session_id={e.get('session_id')}", flush=True)
                    return
        th = threading.Thread(target=reader, daemon=True)
        th.start()
        th.join(timeout=max(0, deadline - time.time()))
        if th.is_alive():
            print(f"<<< [{self.tag}] TIMEOUT waiting for result (alive={self.proc.poll() is None})", flush=True)
        return events

# --- Session A: fixed session id, first turn ---
A = Child("A", ["--session-id", session_id])
A.send({"type": "control_request", "request_id": "init-1",
        "request": {"subtype": "initialize", "hooks": {}}})
A.send({"type": "user", "message": {"role": "user",
        "content": "Remember the code word ALPHA. Reply with just: OK"}})
A.read_until_result()
print(f"=== A alive after turn 1: {A.proc.poll() is None}")

# --- Session B: resume A's id while A is still alive ---
B = Child("B", ["--resume", session_id])
B.send({"type": "control_request", "request_id": "init-1",
        "request": {"subtype": "initialize", "hooks": {}}})
B.send({"type": "user", "message": {"role": "user",
        "content": "What is the code word? Reply with just the word."}})
b_events = B.read_until_result()
print(f"=== B alive after its turn: {B.proc.poll() is None}, exit={B.proc.poll()}")
print(f"=== B stderr: {B.stderr_lines[:10]}")
b_session_ids = {e.get("session_id") for e in b_events if e.get("session_id")}
print(f"=== B session_ids seen: {b_session_ids}")

# --- Back to A: does it still work? ---
A.send({"type": "user", "message": {"role": "user",
        "content": "Now reply with just: GAMMA"}})
A.read_until_result()
print(f"=== A alive after turn 2: {A.proc.poll() is None}")
print(f"=== A stderr: {A.stderr_lines[:10]}")

for c in (A, B):
    try:
        c.proc.stdin.close()
    except Exception:
        pass
    try:
        c.proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        c.proc.kill()

# --- Disk inspection ---
proj_dir = os.path.expanduser("~/.claude/projects/" + cwd.replace("/", "-"))
print(f"=== project dir: {proj_dir}")
for p in sorted(glob.glob(os.path.join(proj_dir, "*.jsonl"))):
    n_lines = sum(1 for _ in open(p))
    bad = 0
    sids = set()
    for line in open(p):
        try:
            d = json.loads(line)
            if d.get("sessionId"):
                sids.add(d["sessionId"])
        except json.JSONDecodeError:
            bad += 1
    print(f"    {os.path.basename(p)}: {n_lines} lines, {bad} unparseable, sessionIds={sids}")

for tag, chunk in per_child_lines.items():
    path = f"{fixture_base}-{tag}.jsonl"
    with open(path, "w") as f:
        f.write("\n".join(chunk) + "\n")
    print(f"=== wrote {len(chunk)} lines to {path}")
