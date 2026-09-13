# Changelog

## Unreleased

## 1.3.4 - 2026-09-13

- Changed: Automatic update checks run on bridge starts 1, 4, 7 and so on within each Max session; manual checks remain immediate.

- Improved: Activity timestamps are bold italic; compact status badges use visually centered labels and aligned brackets while preserving the original palette.

- Fixed: Persistent transport reads complete frames without StreamReader read-ahead stalls, bounds connect/read/write waits and partial frames, and closes the shared socket on cancellation.
- Fixed: Nested timer dispatch is rejected; reload waits asynchronously for the current callback and worker to finish before replacing the facade.
- Added: Request admission and queue size limits, pre-dispatch deadlines, explicit unknown-outcome timeout wording, and isolated transport/lifecycle regression fixtures. Real-Max soak and native-crash validation remain required.

## 1.3.3 - 2026-09-09

- Improved: README and website setup guidance explain the required Codex mode in ChatGPT Desktop and clarify that automatic Claude registration targets Claude Code.

## 1.3.2 - 2026-09-08

- Added: A small-house detailing skill adapts architectural guidance supplied by Yuriy Bobak for editable roofs, timber UVs, fitted furniture, import verification, and delivery checks while preserving the focused floor-plan workflow.
- Improved: Camera composition guidance checks transform handedness before correcting an apparently mirrored architectural view.

## 1.3.1 - 2026-09-07

- Fixed: Bootstrap, update, AI Setup, shutdown, uninstall, image/UI helpers, and batch launchers resolve Windows executables from checked system paths instead of relying on PATH. Missing system executables and unavailable package working directories have distinct diagnostics.

## 1.3.0 - 2026-09-07

- Added: Read-only Max-owned UI diagnostics combine bounded UI Automation, native HWND trees, and WebBrowser layout, scroll, zoom, and DPI metrics.
- Added: A client-neutral diagnostics CLI discovers packaged skills, checks live health and capabilities, audits client registration, and prints setup commands without changing client configuration or scenes.
- Added: A ChatGPT and Codex plugin packages all eight workflow skills and routes natural 3ds Max requests in any language to the registered MCP tools.
- Added: A dedicated armchair workflow covers reference proportions, upholstery, seams, curvature-following subdivision topology, simple rails, clean contact joints, and stock-delivery checks.
- Improved: Direct native HWND capture supports Max-owned child and MAXScriptDialog windows, with ownership validation and actionable recovery hints.
- Fixed: AI-client STDIO hosts survive same-port daemon replacement and reconnect through one bounded, verified attempt on the next tool call.
- Changed: Interrupted calls are never replayed automatically; they report BRIDGE_DOWN with an unknown-outcome warning. Selection and jobs reset after reconnect, and a new scene-revision epoch rejects stale NodeRefs.
- Improved: The fixed 720-by-621 main panel has compact toolbox chrome, four borderless zones, aggregate AI readiness, concise server context, and packaged 16-pixel Lucide icons.
- Improved: Client readiness is checked once after startup and on manual refresh; inconclusive failures remain visible, and dismissing Setup suppresses only its automatic opening.
- Improved: Hide and Expand preserve the live panel, position, connection, and reminder schedule; the compact restore panel keeps a reachable title strip near the taskbar.
- Improved: Activity entries use aligned colored badges, six-pixel margins, compact spacing, and automatic scrolling that preserves the read-only caret and review position.
- Fixed: Rolling Activity-log trimming retains 30 entries through an empty RTF stream while preserving badge and link formatting and read-only protection.
- Fixed: Rooted fonts, reused icons, and theme-aware label backgrounds avoid invalid GDI+ painting in 3ds Max 2022; server labels avoid the unstable tooltip-notification path in 3ds Max 2027.
- Improved: The footer rotates linked project promotions without retaining text-input focus. Clickable Donate reminders appear at bounded intervals, and Settings About uses a centered native layout.
- Changed: Removed adaptive panel sizing, saved dimensions, the separate AI setup button, and the redundant Connect only action.
- Improved: Release preparation synchronizes product and plugin versions, preserves the reviewed Donate metadata, and generates the complete production file list from the canonical allowlist.
- Fixed: Machine-local Packager INIs stay out of version control, and UI test fixtures stay out of production archives.

## 1.2.5 - 2026-08-27

- Improved: MaxScript tools now require an exact privacy-safe operation name and reject missing or generic activity labels instead of logging an ambiguous action.
- Improved: Activity messages now use concise professional wording, with successful outcomes in green and ordinary system lifecycle events in a distinct system color.
- Improved: PREPARE_RELEASE.bat now reads the intended version from version.ini by default while retaining an optional explicit override.

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
