# Changelog

## Unreleased

## 1.2.4 - 2026-08-27

- Improved: GitHub release publication now uses a concise Y/N confirmation prompt.
- Changed: Missing MaxPkg tooling now bootstraps from the current official revision while existing self-updated tooling is preserved.
- Fixed: Release preparation preserves the reviewed maxpkg-icon.svg instead of overwriting it from a secondary asset copy.
- Fixed: Release preparation no longer replaces an existing self-updated MaxPkg Packager.

## 1.2.3 - 2026-08-27

- Fixed: Release, update, and portable-runtime helpers use a self-contained .NET SHA-256 implementation when PowerShell module autoloading is unavailable.
- Improved: The panel title and About page now load the installed package version from manifest.ini, with version.ini as the source-development fallback.
- Changed: Release preparation now uses the permanent Free license without requiring a repeated command-line argument.
- Changed: The default release handoff stops before MaxPkg build, commits, push, or publication unless the maintainer requests those actions explicitly.

## 1.2.2 - 2026-08-27

- Improved: Long activity-log entries wrap onto additional lines instead of being clipped at the right edge.

- Added: The main panel includes a header Donate action, left-aligned maxpkg.dev and 3dground.net footer links, and a linked maxpkg.dev package-manager entry in About.

- Fixed: MaxPkg uninstall preserves quoted package-root paths that end in a backslash, allowing the focused cleanup helper to start correctly.
- Fixed: A stale detached shutdown helper can no longer terminate a replacement daemon that reuses the same loopback port with a different owner token.

## 1.2.1 - 2026-08-26

- Changed: Release tooling is pinned to the official MaxPkg Packager 1.2.0 revision and exact SHA-256.
- Improved: MaxPkg-assisted builds now use the official automation API through MCP and retain UI automation only for older packager compatibility.
- Improved: MaxScript results preserve valid large MaxPkg API responses up to 500,000 characters and report explicit truncation metadata.

- Fixed: Update checks preserve quoted package-root paths that end in a backslash, allowing the hidden helper to receive its result-file argument.
- Improved: Update-check startup failures now report the helper exit code when no result file was produced.
- Fixed: Update and onboarding status labels now use the ColorMan rollout background instead of the rollout-title color.

## 1.2.0 - 2026-08-26

- Added: Deterministic release preparation and publishing safeguards from one version source.
- Added: Verified automatic updates from stable GitHub Releases through MaxPkg with automatic restart.
- Added: MaxPkg marketplace preparation guidance for listing copy, FAQ, sanitized assets, and upload workflow.
- Changed: The main panel title now includes the product version and no longer uses the First Step label.
- Fixed: Automatic update checks now start correctly in supported 3ds Max versions.
- Fixed: MaxPkg production archives include required Node package metadata and linked user and agent documentation.
- Fixed: Release preparation can be rerun safely after a verification failure without duplicating its changelog section.
- Fixed: UI Automation safely normalizes non-finite Qt element bounds instead of failing during window-tree inspection.
- Fixed: MaxPkg launches resolve the active bootstrap from the installed package entry instead of a previously loaded source file.
- Fixed: Control authentication now uses installation-stable per-user state so MaxPkg updates can restart the shared daemon safely.
- Fixed: Verified daemon replacement tolerates transient probe responses while the previous listener is closing.
- Changed: Release builds now pin the official MaxPkg Packager 1.1.7 revision and verify its exact SHA-256.

## 1.1.0 - 2026-08-26

- Added: Session-owned common jobs and read-only material diagnostics.
- Added: Privacy-safe semantic activity labels in the 3ds Max panel.
- Added: Identity-verified server restart and cleanup behavior.
- Added: Clean maximized viewport review captures with restored display settings.
- Added: Floor-plan wall, opening, normal, corner, and slab reliability improvements.
- Changed: Destructive plan/apply workflows bind reusable validation tokens to their exact context.
- Fixed: Viewport framing uses supported 3ds Max commands.
