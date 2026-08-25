# Experimental Node SEA packaging

The supported v1 release uses the official portable Node.js runtime. `scripts\build-sea.ps1` prepares the next distribution step without changing MCP tools, schemas, `--stdio`, or `--daemon` behavior.

The maintainer-only script bundles the dependency-free CommonJS entrypoint with esbuild, asks the pinned portable Node 24 runtime to create a SEA blob, copies `node.exe`, and injects the blob with postject. `esbuild` and `postject` are downloaded through maintainer-side `npx`; they are not shipped to or executed by end users.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\prepare-portable-node.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-sea.ps1
```

Before SEA replaces the portable-runtime release channel, validate:

- Authenticated daemon/STDIO CLI integration and JSON-only stdout.
- Ownership shutdown with the renamed executable rather than `node.exe`.
- Resolution of external `scripts\max-ui-automation.ps1` and `scripts\resize-image.ps1` beside the installed executable.
- Windows Authenticode signing after blob injection.
- Clean Windows machines for Max 2022–2027, ChatGPT Desktop, and Codex.

Until those checks pass, the installer intentionally registers `runtime\win-x64\node.exe core\server.js --stdio`.
