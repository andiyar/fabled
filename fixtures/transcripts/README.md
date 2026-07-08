# Transcript fixtures

Real Claude Code session files copied from Ben's `~/.claude/projects` on
2026-07-08, plus one hand-written synthetic file. Ben approved **local use
only**: do not publish this repository, quote fixture content in commit
messages, or copy these files elsewhere.

| file | lines | purpose |
|---|---|---|
| real-titled-session.jsonl | 28 | custom-title lines (6 of them — last-wins), mode/last-prompt metadata, a system line |
| real-tooluse-session.jsonl | 141 | tool_result user lines (24), assistant turns (60), 15 custom-titles |
| real-untitled-session.jsonl | 11 | no title lines — first-prompt fallback ("Reply with exactly: pong") |
| synthetic-edge-cases.jsonl | 22 | hand-written: legacy summary, ai-title, sidechain/meta/compact prompts, image blocks, result-cache line, unknown type |

The real files are byte-exact snapshots; tests assert their exact line
counts and titles. Never edit them. Extend `synthetic-edge-cases.jsonl`
instead (and update the census constants in TranscriptDecoderTests).
