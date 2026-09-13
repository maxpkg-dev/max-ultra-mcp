# Bridge stability acceptance

The transport and lifecycle changes address identifiable blocking, framing, admission, and reload risks. They do not establish the cause of reported native crashes. Historical Windows event stacks alone do not identify a particular script, timer, or loaded bridge version.

## Automated evidence

- `tests/bridge-lifecycle-test.js` exercises the actual Node request admission, deadline field, timeout cancellation, late response handling, no replay, and fragmented/coalesced frame parser. MAXScript assertions in that file are source contracts only.
- `tests/transport-stream-test.ps1` exercises real .NET Framework loopback streams with partial and coalesced frames, read timeout, close during read, and a non-reading peer. It verifies the platform assumptions without executing the bootstrap or loading Max.
- The full smoke runner includes those fixtures and the existing protocol, CLI, UI and lifecycle tests. Mock Max endpoints cover 2022 and 2027, not their native runtimes.

## Required real-Max acceptance

### Runtime attempt on 2026-09-13

A Max 2022 process with an empty, unsaved scene initially ran the older main-project bootstrap. A controlled transition to the worktree exposed two MAXScript/.NET interop failures that the C# and source fixtures did not detect:

- `No 'BeginConnect' method found which matched argument list`: the callback/state `undefined` arguments did not bind. The source now uses `ConnectAsync` with a bounded `Wait(2000)`.
- The replacement connected, then its first request failed with `Value cannot be null. Parameter name: buffer`. .NET Framework reflection confirms that `NetworkStream.Read` marks the buffer `[In, Out]`, unlike the modern .NET signature. A direct Max 2022 probe reproduced the failure with both ordinary and by-reference array arguments. The source now uses `BinaryReader.ReadBytes`, limited to the available socket bytes (at most 8192), avoiding the mutable-array argument. The same diagnostic endpoint returned `CONTROL_RESPONSE` through this API in Max 2022. Full corrected-bootstrap read/dispatch remains pending a coordinated user load.

No geometry was created or saved during these checks. The earlier process was later replaced and the user reported rebooting; causality for that replacement and reported input behavior is not established. Keyboard/focus automation and autonomous reloads have stopped. Further runtime steps are coordinated individually with the user. No test distribution has been built, and no native-stability success is claimed.

Subsequent read-only checks in the replacement Max 2022 process still identify the older main-project bootstrap: both new lifecycle fields are absent. The process can read the corrected candidate file and its `BinaryReader` implementation, and no staged update is pending. The reason the candidate has not become the active facade remains unresolved. Successful health calls against this older facade do not count as acceptance of the corrected bootstrap; another load requires individual user coordination.

Use a fresh synthetic test scene in a dedicated process, never a customer scene. When upgrading from an older running bootstrap, start with a clean Max process: the old instance does not have the new lifetime guard.

1. On Max 2022 and 2027, verify bootstrap compilation, managed API overload binding, distinct transport/main thread ids, and owner-thread UI callbacks. Record exact bridge commit, Max build and CLR version locally. Exercise normal startup, reconnect, panel hide/expand, close and repeated entry-point reload.
2. Use a controlled fake daemon to send a partial request, two complete requests in one write, CRLF, an oversized frame, and a peer that stops reading. Check bounded failure, no silent request loss, worker completion and stable memory. Stop/reload while connecting, reading and writing; check that the old handler remains alive until DoWork returns and that no second worker overlaps it.
3. Run a harmless synthetic script that pumps messages or opens a modal dialog. Queue read-only work and cancellation behind it. Check that no nested execution occurs, expired work never starts, and a started command is neither aborted unsafely nor retried. Request reload while the modal callback is active; it must wait until the callback returns.
4. Exercise a staged test update through MaxPkg, including installation failure and worker-stop timeout. Verify that reload occurs after the polling callback has returned, that the deferred timer is retired, and that the panel/update status remains usable on failure.
5. Repeat with explicit MAXScript and .NET garbage collection between lifecycle operations. Inspect retained worker/argument references, retired timer/handler counts, socket count and memory after repeated reconnect/reload. No managed fixture substitutes for this host check.
6. Run matching A/B windows longer than one hour: bridge off, bridge on idle, and bridge on with periodic read-only requests. Keep host/plugins/scene identical and use multiple runs. A clean run is evidence for that configuration, not proof that all crashes are fixed.

Capture hang/crash dumps locally with Sysinternals ProcDump when an incident occurs. Include the actual loaded bridge version and reproduction steps; sanitize any shared report and do not commit raw dumps, logs or scene data. Compare managed/native stacks and timer/worker lifetime evidence before assigning causality.

## Primary API references

- [NetworkStream.Read](https://learn.microsoft.com/en-us/dotnet/api/system.net.sockets.networkstream.read): reads available bytes without requiring a newline.
- [NetworkStream.ReadTimeout](https://learn.microsoft.com/en-us/dotnet/api/system.net.sockets.networkstream.readtimeout): bounds synchronous reads.
- [MAXScript .NET lifetime control](https://help.autodesk.com/cloudhelp/2023/ENU/MAXScript-Help/files/Interaction-with-Other/DotNet-In-MAXScript/GUID-99E3B658-D86C-4FD6-9B37-753AEF05FB74.html): wrapper/event-handler collection and explicit lifetime ownership.
- [MAXScript Windows message processing](https://help.autodesk.com/cloudhelp/2026/ENU/MAXScript-Help/files/Interaction-With-The-Operating/GUID-282F32AC-5A80-4FDB-B8C0-275D2CC15845.html): message pumping can dispatch user interaction during script execution.
- [ProcDump](https://learn.microsoft.com/en-us/sysinternals/downloads/procdump): local hang and exception dump capture.

### Active-directory follow-up

The fixes were transferred to the active main checkout. A coordinated manual load in Max 2022 then confirmed the new lifecycle facade and successful BinaryReader request dispatch on main thread 1, with an empty unsaved scene. A normal five-second request exposed a third interop issue: decimal text coerced with `as integer64` lost tens of seconds of Unix-millisecond precision. A direct read-only probe reproduced a 43,360 ms difference; `System.Int64.Parse` preserved the original exactly. The deadline parser now uses that API, with a source regression assertion. Acceptance of normal short deadlines awaits the next coordinated manual load. Earlier copy-selection uncertainty is not treated as a proven cause of the reported hangs.

### Final short acceptance and private build

After the next coordinated manual load, normal five-second requests and health checks passed in approximately 200 ms in Max 2022. The lifecycle facade executed on main thread 1, its worker remained active, the deferred timer was retired, and the empty unsaved scene was unchanged. The complete synthetic suite passed in the active main checkout. Official MaxPkg validation/build created a private 1.3.4 beta archive; archive content hashes and manifests were verified. See PRIVATE_TEST_1.3.4.md for exact scope and outstanding installation, runtime-version, and soak checks. The earlier pending statuses above are historical checkpoints.
