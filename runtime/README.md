# Bundled Node runtime

Release packages contain `win-x64/node.exe`, `NODE-LICENSE.txt`, `VERSION.txt`, and `SHA256.txt` here.

Maintainers prepare the pinned official Node.js 24 LTS runtime with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\prepare-portable-node.ps1
```

End users do not run that command and do not install Node.js. The runtime binary is intentionally not stored in the source repository; it is downloaded from `nodejs.org`, verified against the official `SHASUMS256.txt`, and added to release artifacts.
