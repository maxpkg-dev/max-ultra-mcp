# Tests

All automated verification code and test-only fixtures live in this directory.

## Suites

- `smoke-test.js` verifies the original tool surface, routing, lifecycle, packaging, documentation contracts, MaxScript structure, and examples.
- `v1-smoke-test.js` verifies tool profiles, structured envelopes, revisions, jobs, floor-plan generation, screenshots, and multi-client routing.
- `cli-integration-test.js` launches real daemon and STDIO child processes and verifies authenticated JSON-only MCP transport.
- `helpers/mock-max-client.js` simulates supported 3ds Max protocol endpoints without opening 3ds Max.
- `fixtures/ui-automation-rollout/` contains the MaxScript rollout used for real-Max UI Automation verification.

Run every automated suite from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-smoke.ps1
```

Run an individual suite with Node.js 22+:

```powershell
node .\tests\smoke-test.js
node .\tests\v1-smoke-test.js
node .\tests\cli-integration-test.js
```

The JavaScript suites use mock Max clients only. They must never open, modify, render, or save a real user scene. The UI Automation fixture requires an explicitly selected disposable 3ds Max test scene and is not executed by the automated runner.
