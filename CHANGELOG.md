# Changelog

## Unreleased

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
