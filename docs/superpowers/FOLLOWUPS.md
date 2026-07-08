# Follow-ups

Tracked items that were deliberately deferred. Source: code reviews and task reports. Pull these into the appropriate plan when their layer is next touched.

## From AgentSession review (2026-07-08, Task 7)

Fixed in-task: trailing-event race (join read task before `.terminated`), undrained stderr deadlock, unfinished stream on launch failure.

Deferred:

- **Orphaned child on actor dealloc (I2).** No `deinit`; dropping an `AgentSession` without calling `terminate()` leaks a running `claude` process. Add `deinit { process?.terminate() }` + doc that `terminate()` is the intended path. → Plan 3 (ChatSession owns lifecycle; decide there).
- **SIGPIPE on writes after child death (I3).** `try?` swallows EPIPE but the signal itself can kill the host app. Add a `terminated` flag short-circuiting `write`, and `signal(SIGPIPE, SIG_IGN)` at app startup. → Plan 3 (app-level signal setup).
- **Unbounded AsyncStream buffer (M1).** Slow consumer grows the buffer for the session's life. Consider `.bufferingNewest(n)` or document drain-promptly requirement. → Plan 3, decided with the ChatSession consumer design.
- **SIGTERM-only terminate (M2).** No SIGKILL escalation; a stuck child never dies. Add kill-after-timeout. → Plan 4 (session management).
- **`events` before `start()` returns a dead placeholder stream; `alreadyStarted` is a misleading error after natural exit (M3).** Sharpen docs or API when ChatSession wraps it. → Plan 3.
- **Byte-by-byte stdout reads (M4).** Only if profiling shows it matters. → backlog.
- **Dead `Process` retained after termination (M5).** Harmless; tidy when touching the file. → backlog.
