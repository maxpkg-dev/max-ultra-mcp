# MaxPkg packaging

Max Ultra MCP is adapted for the standard [MaxPkg Packager](https://github.com/maxpkg-dev/max-dev-tool) workflow. The package keeps `01_START_MAX_ULTRA_MCP_FIRST.ms` as its single user-facing entry file and includes the portable Node.js runtime, MCP host, daemon, integration helper, optional agent skills, runtime documentation, and focused examples.

## Prepare the project

1. Prepare the pinned portable Node.js runtime:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\prepare-portable-node.ps1
   ```

2. Generate the project-local MaxPkg files:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\prepare-maxpkg.ps1
   ```

   The project license is permanently set to `Free` and is written to generated MaxPkg settings automatically.

3. Run `maxpkg-packager.ms` in 3ds Max.
4. Review all four packager tabs and resolve every validation issue.
5. Choose **Build MZP**, or call the public `MaxPkgPackerApi.validate()` and `MaxPkgPackerApi.build()` methods through Max Ultra MCP, then test the archive in a clean 3ds Max profile.

MaxPkg Packager 1.2.0 exposes `MaxPkgPackerApi` specifically for AI-agent automation. Max Ultra MCP loads the project-local packager with `max_run_script_file`, invokes the API with `max_run_script`, and parses the inner JSON response after every operation. Automated builds require successful `ping()`, `reload()`, `validate()`, and `build()` calls, plus `data.exists == true` and a verified `data.outputFile`. Process-scoped UI automation is retained only as a compatibility fallback for older packager versions without the API.

## Prepare a versioned release

`version.ini` is the canonical version/channel source. Set its `Version` to the intended release, keep user-facing changes under `## Unreleased` in `CHANGELOG.md`, and use the supported Added, Changed, Improved, Fixed, or Removed prefixes. Run `PREPARE_RELEASE.bat` (or `scripts\prepare-release.ps1`) to read that version, synchronize `core\package.json`, promote the dated changelog section, regenerate MaxPkg inputs with the permanent `Free` license, and run the full suite. `-Version <VERSION>` remains an optional override. The installed Qt UI reads its version from `manifest.ini`; a source checkout falls back to `version.ini`. The command never builds an MZP, commits, pushes, tags, or publishes.

The generated `maxpkg-changelog.ini` is derived from the tracked current-version section in `CHANGELOG.md`; release notes are no longer a hard-coded placeholder.

## Publish the MZP to GitHub Releases

`dist/` is ignored by Git and remains the local MaxPkg output area. The project version in `version.ini` is the release source of truth and `core\package.json` must match it. MaxPkg embeds that version in `manifest.ini`, `manifest.json`, and the filename `max-ultra-mcp@<VERSION>@c6977570-25a6-41b0-b9bb-b3be8101123c.mzp`. The installed UI displays the embedded manifest version.

After testing the generated package:

1. Commit the release source and push `main` to `origin`.
2. Run `RELEASE_MZP_TO_GITHUB.bat` from the repository root.
3. Review the displayed project, newest local MZP, and newest GitHub Release versions.
4. Type the exact requested confirmation only when the package and version are correct.

The launcher delegates to `scripts\publish-github-release.ps1`. It requires an authenticated GitHub CLI, validates the MZP filename and internal manifest, confirms the portable runtime is present, rejects duplicate/current/older versions, requires a clean `main` whose HEAD exactly matches `origin/main`, creates `v<VERSION>` with generated notes, uploads the MZP plus SHA-256 file, and verifies both release assets. Existing releases are never overwritten automatically. Use `RELEASE_MZP_TO_GITHUB.bat -CheckOnly` to perform all checks without publishing.

The three compared sources are `version.ini` (cross-checked against `core\package.json`), the version parsed from the newest MZP filename below `dist`, and stable GitHub Release tags.

`scripts/sync-maxpkg-tooling.ps1` uses pinned revision `3727cfd6fe98f8fa6bfd31b900f44ee0c37d9417` only as a verified bootstrap for missing tooling files. Existing MaxPkg Packager and hook files are preserved because the official packager may update itself. Every downloaded bootstrap file is checked against a committed SHA-256 value; replacing an existing file requires the explicit `-Force` option.

`maxpkg-packager.ms`, `_install.ms`, and `_uninstall.ms` live in the project root and are source controlled. Existing files are never replaced by normal release preparation, so official MaxPkg self-updates persist. The reviewed `maxpkg-icon.svg` is also source controlled and is the package icon source of truth. Generated `maxpkg-packager.ini`, `maxpkg-changelog.ini`, and build output are machine-local release artifacts and are not committed.

## Automatic update lifecycle

The bootstrap starts `scripts\update-manager.ps1` as a hidden detached process and polls only its bounded INI result from the Max main thread. That helper starts hidden Windows `curl.exe` processes for both release metadata and assets, requires the exact package filename and GUID, downloads the MZP and adjacent checksum into the per-user Max Ultra MCP update staging directory, and verifies SHA-256 before reporting readiness. The bootstrap then disposes the active bridge, opens the verified MZP through MaxPkg, and restarts `01_START_MAX_ULTRA_MCP_FIRST.ms` from the updated package. Failed checks, downloads, installer launches, or restarts leave a retryable package status and never report success. No update code rewrites the package directory directly.

## Package lifecycle

The Python client revalidates a pending package and its SHA-256 on the next explicit launch, including legacy pending records without a separate version field. If installation fails or is cancelled, it restarts the surviving entry point and retains the pending package and error status. That recovery launch skips both the pending installation and its automatic update check to prevent a retry loop. A subsequent explicit launch or manual update check can retry. Recovery still requires an intact entry point and a transport worker that can stop; failures to restart are shown explicitly.

- MaxPkg extracts the package into its GUID-owned temporary package directory.
- The generated MaxPkg macro runs `01_START_MAX_ULTRA_MCP_FIRST.ms` directly from that directory.
- Runtime paths are resolved from the executing entry file; no developer-machine path is embedded in the archive.
- Python and Qt come from 3ds Max. The bundled Node.js server remains external; no separate user installation of these runtimes is required.
- Mutable authentication state stays in the stable per-user `%LOCALAPPDATA%\3DGROUND\MaxUltraMCP\runtime\state` directory, survives package-root replacement, and is never bundled.
- Imported skills and their durable registry live separately in `%LOCALAPPDATA%\3DGROUND\MaxUltraMCP\user-skills`. Neither updates nor standard uninstall delete this store. Native discovery adapters contain only metadata and a reference to this store; they are removed by the explicit Skills manager Delete action. User source folders and client configurations are never bundled or rewritten. The package includes the manager code, original book icon, creation prompt, and standalone HTML help/submission pages.
- Folder selection uses the Qt file dialog; the legacy C# folder-picker source is no longer shipped.
- The standard MaxPkg installer and uninstaller own package files, generated macros, toolbar metadata, and the installed SVG icon.
- The focused custom uninstall hook unregisters the named MCP server through available official client CLIs and stops only Node processes whose command line contains the exact installed `core\server.js` path. MaxPkg then removes the package directory.

Close ChatGPT Desktop, Codex, Claude Code, and 3ds Max before uninstalling when practical. This prevents an AI client from immediately restarting its configured STDIO process while cleanup is running.

## Maintainer files

The production allowlist includes Python modules, editable theme JSON, original SVG icons, client logos and the portable Node.js runtime. Exclude Python caches and machine-local state.

- `maxpkg-files.txt` is the reviewed production file allowlist.
- `.agents\plugins\marketplace.json` and `plugins\max-ultra-mcp` provide the installable ChatGPT/Codex workflow plugin; its copied skill tree must remain byte-for-byte synchronized with canonical `skills\` sources.
- `skills\max-ultra-mcp`, `skills\max-ultra-camera-composition`, `skills\max-ultra-character-object-modeling`, `skills\max-ultra-armchair-modeling`, `skills\max-ultra-renderer-settings`, `skills\max-ultra-spline-modeling`, `skills\max-ultra-floor-plan`, `skills\max-ultra-small-house-detailing`, and `skills\max-ultra-maxpkg-packaging` are the optional file-based agent skills shipped with the package; MCP operation does not depend on installing them.
- The MaxPkg adaptation skill fetches the current official README, coding rules, both official prompts, API documentation, `maxpkg-packager.ms`, `_install.ms`, and `_uninstall.ms` from one resolved `maxpkg-dev/max-dev-tool` commit. Prompt content is not embedded in Max Ultra MCP. Its stricter workflow requires both standard hooks in every adapted project.
- `maxpkg-icon.svg` is the reviewed square package icon used by MaxPkg Packager.
- `scripts/prepare-maxpkg.ps1` creates machine-local packager INI files with absolute source paths.
- `scripts/sync-maxpkg-tooling.ps1` provides reproducible MaxPkg tooling.
- `scripts/maxpkg-uninstall.ms` and `scripts/maxpkg-uninstall.ps1` implement focused package-specific cleanup.

Do not add test runners, mocks, source archives, logs, control tokens, ownership records, client configuration files, or developer-machine paths to the package file list.

## Transition from 1.4.7 to 1.5.0

The package identity and entry filename are unchanged. `scripts/maxpkg-install.ms` is a focused custom hook invoked by the original MaxPkg installer after confirmation. It removes only the 11 obsolete packaged files listed in `assets/obsolete-1.4.7.json`, using SHA-256 hashes verified against the published 1.4.7 MZP. Modified files are preserved. Cleanup validates the installed GUID directory under Max's temporary directory and rejects links; it never recursively deletes the package or touches user settings, imported skills or client configuration.

The hook writes an installation-completion receipt for the installed version. The Python bootstrap waits for that receipt when launched by the old updater before the standard installer has been confirmed. Python updates also wait before reporting completion. The original MaxPkg tooling is not modified.

The original standalone MaxPkg installer removes its extracted package directory when cancelled. A cancelled installation can therefore require reinstalling the MZP; the completion receipt prevents reporting that cancellation as success, but does not provide a transactional rollback of MaxPkg extraction. Do not describe this release as a guaranteed seamless update until the real migration acceptance checks pass.
