# Changelog

## Unreleased

- Changed: Removed the obsolete adaptive main-panel layout path. The 720×640 floater, four rollout heights, and all control coordinates are now declared directly; only position and Hide state persist.
- Changed: Support reminders now appear one minute after the first successful connection, ten minutes after the first reminder, and 60 minutes after the second reminder.
- Changed: Settings About now uses a centered vertical layout with native MAXScript labels and hyperlinks for the product, version, author, project site, and package manager, followed by the themed Donate action.
- Fixed: The restore mini-panel can again be dragged down near the Windows taskbar; only its 24 px title strip is kept reachable instead of clamping the entire 64 px panel above the taskbar.
- Changed: Activity log category badges now have a two-space unfilled gap after timestamps, include filled outer spaces, and render padded seven-character statuses in a monospaced font, giving every colored block the same pixel width. An unfilled ` > ` separator aligns message starts without changing MCP activity responses. Badge text uses a darker, more saturated shade derived from its category-colored background; light themes use a lighter badge surface for contrast. Timestamps and messages keep their previous foreground colors, while separators and trailing visual padding remain unfilled.
- Improved: Donate keeps a readable gap between its label and an optically centered 16 px Lucide heart.
- Improved: All main-panel button icons now use the same 16×16 canvas.
- Changed: Donate now uses the exact orange link theme color. Donate, Refresh, Hide panel, Reconnect, Stop / Exit, and Settings load packaged, ready-to-use white PNG renditions of their official Lucide icons through native WinForms. Reconnect uses the distinct `plug-zap` symbol instead of duplicating Refresh. No runtime recoloring or SVG renderer is used.
- Fixed: Footer links and Donate now move through the MaxScript rollout `.pos` property. Applying WinForms `.Location` had offset each child inside its own host, clipping the first link and hiding the remaining controls.
- Changed: The bridge row uses lighter green and red foreground colors. Error text is now the stable short message `Please restart the script`; full diagnostics remain in the Activity log, tooltip, and accessibility description.
- Changed: WinForms links now use the dedicated orange theme color `[255, 127, 0]` for normal and visited states.
- Fixed: 3ds Max 2022 no longer routes server labels or mini-panel buttons through the fragile compatible GDI+ `MeasureString` path. Bold controls now own independent rooted fonts, preventing the `Parameter is not valid` paint exception after reload or garbage collection.
- Improved: The main panel now uses four fixed borderless rollout zones with a shared ColorMan-aware WinForms style, a dedicated AI readiness strip, concise server context, full-width Activity area, and an accented support footer.
- Improved: The main floater now uses compact fixed toolbox chrome with mouse resizing disabled, no icon, Minimize, or Maximize buttons, and only the close action visible; programmatic minimize/restore remains supported.
- Changed: Legacy saved panel dimensions are ignored and no longer read or written; position and Hide state remain persistent.
- Improved: The main AI strip now uses one aggregate status button that names ready clients and does not present an unused optional client as a separate red requirement.
- Improved: The separate main-panel **AI setup** button was removed; the fixed-width aggregate status now opens Setup directly and displays **Click to set up AI agent** when no client is ready.
- Fixed: Exact fixed rollout and control coordinates keep the Activity log's five-pixel top inset and the 44 px footer visible without measuring live client width or native window chrome; transparent Server/footer controls inherit their rollout background without obscuring sibling controls.
- Fixed: Server labels and footer links now use the actual opaque background exposed by their rollout parent chain, falling back to the ColorMan rollout color only when the host exposes no usable value.
- Fixed: Custom bold UI font lifetime is retained by the bridge; labels are reset to the system font before the reference is released, and the shared Font is never manually disposed while Max can still paint a rollout control.
- Fixed: Repeated panel configuration no longer disposes and recreates live GDI+ icon bitmaps, preventing the WinForms `Parameter is not valid` paint exception.
- Fixed: Initial panel display no longer runs the complete WinForms configuration a second time after floater creation.
- Fixed: Rollout labels reject unrelated system-white `Parent.BackColor` values and use the ColorMan rollout fallback unless a parent color is consistent with the active Max theme.
- Changed: The redundant Connect only action was removed; Reconnect remains the explicit retry for an already-running daemon.
- Improved: ChatGPT Desktop/Codex and Claude Code registration readiness is checked once two seconds after startup with a 30-second timeout, while a centered dependency-free Lucide `refresh-cw` vector icon starts an immediate check, inconclusive failures stay visible without opening setup, and onboarding dismissal suppresses only automatic setup opening.
- Improved: Hide preserves position and makes the live rollout floater invisible without stopping the bridge; Expand reuses that floater and recreates it at the saved position only when necessary.
- Improved: The restore mini-panel now uses bold system text and a high-contrast connection-colored action background; the main Server endpoint/problem text is bold as well.
- Added: The Activity log can show up to three highlighted support reminders per bridge session: one minute after the first successful connection, ten minutes after the first reminder, and 60 minutes after the second. Hide and Reconnect do not reset the absolute deadlines.
- Improved: The Activity log now keeps three empty display lines below the latest entry and inserts new text before them for more comfortable end scrolling, without adding padding to protocol responses.
- Improved: The Activity RichTextBox now uses six-pixel native RichEdit margins on both horizontal sides instead of relying on the ineffective WinForms `Padding` property.
- Added: A local ChatGPT and Codex plugin packages all Max Ultra workflow skills so natural 3ds Max requests route to the registered MCP tools.
- Fixed: The natural workflow skill now uses readable examples and explicitly applies to requests in any user language.
- Added: A client-neutral read-only diagnostics CLI discovers packaged skills, checks live health and capabilities, audits Codex and Claude Code registration, and prints setup commands without changing client configuration or 3ds Max scenes.
- Fixed: Window capture now targets a supplied Max-owned HWND directly after native process-ownership validation, including child and MAXScriptDialog windows, without depending on top-level UI Automation rediscovery.
- Added: Read-only diagnostics return bounded UI Automation and native WinForms trees plus compact MSHTML WebBrowser sizing, layout, scroll, zoom, and DPI metrics without raw DOM or page source.
- Improved: MCP errors now include predictable UI recovery hints, and the natural 3D workflow lists and safely selects a Max instance before taking action.
- Added: Canonical cross-agent project policy with thin Codex and Claude skill adapters; deterministic hooks remain limited to repository hygiene rather than scene or UI decisions.

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
