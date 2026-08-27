# Max Ultra MCP Release Rules

Read this file completely whenever the user asks to prepare, build, publish, or otherwise create a Max Ultra MCP release.

## Authorization boundary

A request to prepare or release authorizes local release-metadata preparation and verification only. By default, stop after generating and reviewing the MaxPkg inputs. The maintainer runs MaxPkg Packager, builds and tests the MZP, creates commits, pushes, and starts GitHub publication unless the user explicitly requests one of those exact actions.

Never publish from a dirty tree, an unreviewed archive, a branch other than `main`, or a commit that does not match `origin/main`. Never overwrite an existing tag or GitHub Release.

## Release source of truth

- `version.ini` is the canonical product version and channel.
- `maxpkg-packager.ini` is generated, ignored, and machine-local. It receives the canonical version during package preparation and must never become a release source of truth.
- `scripts/prepare-release.ps1` updates `version.ini`, `core/package.json`, and `CHANGELOG.md`; regenerates MaxPkg inputs with the permanent `Free` license; and runs verification.
- The installed UI reads its displayed version from package `manifest.ini` and falls back to `version.ini` only in a source checkout. The main title must not contain First Step.
- `CHANGELOG.md` is the human-readable release history. Keep `## Unreleased` at the top and use factual entries formatted as `- Added:`, `- Changed:`, `- Improved:`, `- Fixed:`, or `- Removed:`.
- `scripts/prepare-maxpkg.ps1` converts the current tracked changelog section to machine-local `maxpkg-changelog.ini` for MaxPkg Packager.
- `maxpkg-icon.svg` is source controlled and must never be overwritten during release preparation.
- Existing MaxPkg tooling may self-update and must be preserved during preparation. The pinned revision is a verified bootstrap only for missing files; overwriting requires an explicit tooling-sync action with `-Force`.

Do not manually bump only one version-bearing file. Do not invent compatibility, test results, dates, features, or fixes.

## Local preparation workflow

1. Read `AGENTS.md`, `.agents/coding-rules.md`, this file, `docs/PRIVACY.md`, and `docs/MAXPKG.md` completely.
2. Inspect `git status`, changes since the latest stable tag, and the `CHANGELOG.md` Unreleased section. Separate unrelated user work.
3. Determine the next stable semantic version from actual compatibility impact.
4. Rewrite Unreleased entries as concise, factual, English-only, privacy-safe release notes.
5. Run `PREPARE_RELEASE.bat -Version <VERSION>` or `scripts/prepare-release.ps1 -Version <VERSION>`. The project license defaults permanently to `Free`. Do not use `-SkipTests` for a real release.
6. Confirm the pinned portable Node.js runtime is present, then run syntax checks, the full verification suite, `git diff --check`, Cyrillic/privacy scans, and inspect the exact diff.
7. Stop and hand the prepared project to the maintainer. Do not run MaxPkg Packager, build an MZP, create a commit, push, tag, or publish unless the user explicitly requests that exact action.
8. The maintainer runs `maxpkg-packager.ms`, reviews all tabs, validates and builds the MZP, and performs the appropriate real-3ds-Max acceptance checks.
9. The maintainer commits and pushes the reviewed source, then runs `RELEASE_MZP_TO_GITHUB.bat -CheckOnly` before the publishing BAT.

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
