# Max Ultra MCP Release Rules

Read this file completely whenever the user asks to prepare, build, publish, or otherwise create a Max Ultra MCP release.

## Authorization boundary

A request to "release" authorizes local release preparation, verification, and release commits. It does not authorize a push, tag, GitHub Release, asset upload, or modification of an existing remote release. Ask for explicit confirmation immediately before the first remote mutation unless the user already requested that exact mutation.

Never publish from a dirty tree, an unreviewed archive, a branch other than `main`, or a commit that does not match `origin/main`. Never overwrite an existing tag or GitHub Release.

## Release source of truth

- `version.ini` is the canonical product version and channel.
- `maxpkg-packager.ini` is generated, ignored, and machine-local. It receives the canonical version during package preparation and must never become a release source of truth.
- `scripts/prepare-release.ps1` updates `version.ini`, `core/package.json`, the MaxScript main-window title, the About version, and `CHANGELOG.md` as one checked operation.
- The main title must be `3DGROUND - Max Ultra MCP <VERSION>` and must not contain `First Step`.
- `CHANGELOG.md` is the human-readable release history. Keep `## Unreleased` at the top and use factual entries formatted as `- Added:`, `- Changed:`, `- Improved:`, `- Fixed:`, or `- Removed:`.
- `scripts/prepare-maxpkg.ps1` converts the current tracked changelog section to machine-local `maxpkg-changelog.ini` for MaxPkg Packager.

Do not manually bump only one version-bearing file. Do not invent compatibility, test results, dates, features, or fixes.

## Local preparation workflow

1. Read `AGENTS.md`, `.agents/coding-rules.md`, this file, `docs/PRIVACY.md`, and `docs/MAXPKG.md` completely.
2. Inspect `git status`, all changes since the latest stable version commit or tag, and the current `CHANGELOG.md` Unreleased section. Separate unrelated user work; never include it silently.
3. Determine the next stable semantic version from the actual compatibility impact. Ask the user only when the intended version cannot be inferred safely.
4. Rewrite the Unreleased entries so they are concise, factual, English-only, privacy-safe, and user-facing. Do not include raw logs, local paths, credentials, machine data, or internal speculation.
5. Run `scripts/prepare-release.ps1 -Version <VERSION>`. Supply the confirmed MaxPkg license when preparation needs to regenerate packager settings. Do not use `-SkipTests` for a real release.
6. Prepare the portable Node.js runtime if it is absent or not the pinned release version. Network download is a separate external action and may require user approval.
7. Run the complete verification suite, syntax checks, `git diff --check`, Cyrillic/privacy scans, and inspect the staged diff.
8. Create a concise local release-preparation commit such as `Prepare Max Ultra MCP 1.2.0 release`. Do not push.
9. Build the MZP with the original `maxpkg-packager.ms` in a supported real 3ds Max. Inspect its manifest, bundled runtime, filename, size, and SHA-256. A mock or static test is not proof that MaxPkg installation works.
10. Install or update the MZP in a clean 3ds Max profile. Verify startup, agent onboarding, automatic update settings, scene-safe connection checks, and focused uninstall behavior.
11. If build or acceptance work changes tracked release files, create a second focused local commit and repeat applicable verification.

Stop before claiming the release is ready when the real-Max MZP build/install/update fixture has not passed. Report the exact missing fixture.

## Publishing workflow

Only after the user explicitly authorizes push and publication:

1. Push the reviewed release commit to `origin/main`.
2. Run `RELEASE_MZP_TO_GITHUB.bat -CheckOnly` and review all compared versions and assets.
3. Run `RELEASE_MZP_TO_GITHUB.bat` and type its exact confirmation.
4. Verify the published tag, release title, MZP, checksum asset, and latest-release URL.
5. Do not amend, replace, or delete a published release automatically. Report a partial failure and ask for direction.

## Auto-update contract

- Update discovery and download run through hidden Windows `curl.exe` processes owned by a detached helper outside the 3ds Max main thread.
- Only stable, non-draft GitHub Releases from `maxpkg-dev/max-ultra-mcp` are eligible.
- The MZP filename, package GUID, semantic version, release asset URL, checksum filename, and SHA-256 must all match before staging.
- A verified update is applied only through the MZP/MaxPkg installer. Dispose the active bridge first, then restart `01_START_MAX_ULTRA_MCP_FIRST.ms` automatically from the updated package. Never copy files over the installed package tree directly.
- Failed checks or downloads leave the installed version untouched. Failed installation remains visible in local status and is not represented as success.
- User settings, authentication state, scenes, and user-authored files are never part of update staging or cleanup.
