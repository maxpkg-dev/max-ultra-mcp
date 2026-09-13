# Max Ultra MCP 1.3.4 beta - PRIVATE TEST PATCH

Private test build, 2026-09-13. Not a public or stable release.

## Final changes

- Bounded bridge transport, queue admission, cancellation/deadlines, nested callback protection and deferred reload fixes, including Max 2022-compatible BinaryReader and exact Int64 deadline parsing.
- Compact native RichTextBox badges with aligned opening/closing bracket columns and centered labels. Exactly two literal spaces before the opening bracket and after the closing bracket. Timestamps are bold italic; labels and messages remain regular. All original category colors are preserved, including padded/tabbed category tokens.
- Automatic update checks run on genuine bridge starts 1, 4, 7 and so on in one Max process. The counter survives bootstrap replacement through the existing facade, resets in a new Max process, and is never written to disk. Skipped launches do not start the update helper. Manual checks stay immediate, with the existing in-flight guard. Hide/show, reconnect and timer ticks do not count as launches.

## Verified evidence

The full synthetic suite passed, including protocol mocks for 2022/2027, lifecycle/transport, CLI cleanup, diagnostics, UI helper, WinForms and release workflow. The exact isolated cadence function returned true,false,false,true,false,false,true; resetting its session state returned true on the next first launch.

The exact final formatter ran against an isolated RichTextBox inside Max 2022: every opening bracket was at x55 and every closing bracket at x125; center error was at most 0.5 pixel. Consecutive mixed-category rows retained their original colors. Timestamp Bold and Italic were true; status/message Bold remained false. Raw and padded success categories both returned original green; tabbed system returned original purple. The native offscreen preview was visually inspected on the actual dark background. This is offscreen evidence, not an assertion that a user-visible panel was reloaded by the agent.

Short ordinary five-second requests and health calls passed in the running Max 2022 process with an empty unsaved scene. No scene was modified. Official MaxPkgPackerApi reload/validate/build produced the MZP; all 122 allowlisted files match source hashes. The package includes the server modules/helpers, skills/assets, portable Node.js 24.18.0 and its license. No system Node installation is needed.

## Installation and rollback for testers

Use a separate test machine or Windows profile and an empty scene. This beta uses the existing package identity and can replace a stable installation in the same profile. Keep the known-good stable MZP. Install through MaxPkg and launch its Max Ultra MCP button/01_START_MAX_ULTRA_MCP_FIRST.ms. Confirm version 1.3.4 beta.

For rollback in the test profile, close the bridge, use standard MaxPkg uninstall for the beta, then install the retained stable MZP. Do not delete user settings or scene folders. Installation, rollback and uninstall acceptance were not performed for this build.

## Remaining limits and reporting

Real Max 2027, installed-package acceptance, full session reload/network cadence integration, renderer/plugin compatibility, and long soak/native crash validation remain untested. This patch does not establish a native-crash cause or guarantee native stability. No automated UI input, automatic reload, public release, commit, push or tag was performed.

Report package version/hash, exact Max build, last action, time to failure and whether Max recovered. Keep raw logs/dumps local unless requested privately. Redact personal paths, machine identifiers, credentials and customer data before sharing; do not publish customer scenes or dumps.
## Artifact

- Filename: max-ultra-mcp@1.3.4@c6977570-25a6-41b0-b9bb-b3be8101123c.mzp
- Size: 37021541 bytes
- SHA-256: 65ef80992b915cd23f8c2d7bc4bf70e48f198b9353708dba75c9d03b65093b99
