# MaxPkg packaging

Max Ultra MCP is adapted for the standard [MaxPkg Packager](https://github.com/maxpkg-dev/max-dev-tool) workflow. The package keeps `01_START_MAX_ULTRA_MCP_FIRST.ms` as its single user-facing entry file and includes the portable Node.js runtime, MCP host, daemon, integration helper, optional agent skills, runtime documentation, and focused examples.

## Prepare the project

1. Prepare the pinned portable Node.js runtime:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\prepare-portable-node.ps1
   ```

2. Generate the project-local MaxPkg files:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\prepare-maxpkg.ps1 -License "<CONFIRMED LICENSE>"
   ```

   Replace the license placeholder with one supported by MaxPkg: `Free`, `Shareware`, `Commercial`, `Open source`, or `Trial`. The script intentionally leaves this legal field blank when it is omitted.

3. Run `maxpkg-packager.ms` in 3ds Max.
4. Review all four packager tabs and resolve every validation issue.
5. Choose **Build MZP** and test the archive in a clean 3ds Max profile.

## Publish the MZP to GitHub Releases

`dist/` is ignored by Git and remains the local MaxPkg output area. The project version in `core\package.json` is the release source of truth. MaxPkg embeds that version in both `manifest.json` and the filename `max-ultra-mcp@<VERSION>@c6977570-25a6-41b0-b9bb-b3be8101123c.mzp`.

After testing the generated package:

1. Commit the release source and push `main` to `origin`.
2. Run `RELEASE_MZP_TO_GITHUB.bat` from the repository root.
3. Review the displayed project, newest local MZP, and newest GitHub Release versions.
4. Type the exact requested confirmation only when the package and version are correct.

The launcher delegates to `scripts\publish-github-release.ps1`. It requires an authenticated GitHub CLI, validates the MZP filename and internal manifest, confirms the portable runtime is present, rejects duplicate/current/older versions, requires a clean `main` whose HEAD exactly matches `origin/main`, creates `v<VERSION>` with generated notes, uploads the MZP plus SHA-256 file, and verifies both release assets. Existing releases are never overwritten automatically. Use `RELEASE_MZP_TO_GITHUB.bat -CheckOnly` to perform all checks without publishing.

No separate `version.ini` is required on GitHub. The three compared sources are `core\package.json`, the version parsed from the newest MZP filename below `dist`, and stable GitHub Release tags.

`scripts/sync-maxpkg-tooling.ps1` downloads the MaxPkg Packager and standard hooks from pinned revision `93ceb0e018b44ca53546cf2c274b196160495699`. Every downloaded file is checked against a committed SHA-256 value before it replaces a local tooling file.

Pinned `maxpkg-packager.ms`, `_install.ms`, and `_uninstall.ms` live in the project root and are source controlled. Generated `maxpkg-packager.ini`, `maxpkg-changelog.ini`, `maxpkg-icon.svg`, and build output are machine-local release artifacts and are not committed.

## Package lifecycle

- MaxPkg extracts the package into its GUID-owned temporary package directory.
- The generated MaxPkg macro runs `01_START_MAX_ULTRA_MCP_FIRST.ms` directly from that directory.
- Runtime paths are resolved from the executing entry file; no developer-machine path is embedded in the archive.
- Native code is not required. A future managed helper DLL may be shipped package-relative and loaded explicitly, but it must remain optional and provide a tested Node.js/MaxScript fallback.
- Mutable authentication state stays under `runtime\state` inside the package root and is excluded from source control and the package input list.
- The standard MaxPkg installer and uninstaller own package files, generated macros, toolbar metadata, and the installed SVG icon.
- The focused custom uninstall hook unregisters the named MCP server through available official client CLIs and stops only Node processes whose command line contains the exact installed `core\server.js` path. MaxPkg then removes the package directory.

Close ChatGPT Desktop, Codex, Claude Code, and 3ds Max before uninstalling when practical. This prevents an AI client from immediately restarting its configured STDIO process while cleanup is running.

## Maintainer files

- `maxpkg-files.txt` is the reviewed production file allowlist.
- `skills\max-ultra-mcp`, `skills\max-ultra-camera-composition`, `skills\max-ultra-character-object-modeling`, `skills\max-ultra-renderer-settings`, `skills\max-ultra-spline-modeling`, `skills\max-ultra-floor-plan`, and `skills\max-ultra-maxpkg-packaging` are the optional file-based agent skills shipped with the package; MCP operation does not depend on installing them.
- The MaxPkg adaptation skill fetches the current official README, coding rules, both official prompts, `maxpkg-packager.ms`, `_install.ms`, and `_uninstall.ms` from one resolved `maxpkg-dev/max-dev-tool` commit. Prompt content is not embedded in Max Ultra MCP. Its stricter workflow requires both standard hooks in every adapted project.
- `assets/max-ultra-mcp.svg` is the square package icon source.
- `scripts/prepare-maxpkg.ps1` creates machine-local packager INI files with absolute source paths.
- `scripts/sync-maxpkg-tooling.ps1` provides reproducible MaxPkg tooling.
- `scripts/maxpkg-uninstall.ms` and `scripts/maxpkg-uninstall.ps1` implement focused package-specific cleanup.

Do not add test runners, mocks, source archives, logs, control tokens, ownership records, client configuration files, or developer-machine paths to the package file list.
