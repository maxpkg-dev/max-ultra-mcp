---
name: max-ultra-maxpkg-packaging
description: Adapt a new or existing 3ds Max MaxScript or Python project for MaxPkg, configure the official packager, build or verify its MZP through Max Ultra MCP, and prepare a maxpkg.dev marketplace listing and assets. Use when a user asks to make a script MaxPkg-compatible, replace a legacy installer, prepare a MaxPkg release, or publish/add an MZP on maxpkg.dev. Do not use merely to run an existing third-party MZP or package non-3ds Max software.
---

# Max Ultra MaxPkg Packaging

Prepare the requested 3ds Max project for the official MaxPkg installation flow while preserving its runtime behavior, settings, user data, licensing behavior, supported-version logic, and original project files. MaxPkg replaces the distribution method; it does not replace or erase the user's sources.

Use the official [MaxPkg development tool](https://github.com/maxpkg-dev/max-dev-tool) repository as the live source of truth. Do not rely on a copied or remembered MaxPkg prompt. At the start of every adaptation, run [scripts/get-maxpkg-upstream.ps1](scripts/get-maxpkg-upstream.ps1), then read the returned README, coding rules, and selected official prompt completely. The helper resolves GitHub `HEAD` to an immutable commit SHA and downloads every source file from that exact commit. If the fetch fails, stop before editing and report the upstream-access blocker.

Max Ultra MCP adds only safety and product constraints that are intentionally stricter than upstream: obtain preflight consent, preserve all user source files, and always include both standard hooks.

## Mandatory preflight consent

Before any file edit, generated configuration, copy, build, installation, or uninstall operation:

1. Resolve the target project root read-only. Run `scripts/get-maxpkg-upstream.ps1 -Prompt Adaptation`, or use `-Prompt FullOnboarding` when marketplace preparation was requested. Read the returned `README.md`, `code-rules.md`, and selected prompt completely. Record the returned repository commit SHA. Do not substitute a bundled prompt snapshot or this skill's summary.
2. Detect whether the target is a Git repository and inspect its working-tree and upstream status read-only. Do not create a commit, push, stash, reset, clean, or rewrite history.
3. Tell the user which project will be adapted, which categories of files may be edited or added, and that the intended output is a separate MZP without deleting sources.
4. Ask for explicit confirmation that the agent may modify the project, that all work is saved, and that a restorable backup exists.
5. When Git is present, also ask the user to confirm that every important change has been committed and pushed to the intended remote. Report any observed dirty, untracked, or ahead state before asking.

Do not perform writes until the user answers these questions affirmatively. A read-only audit may continue only far enough to identify the exact project, Git state, proposed mutation scope, and missing facts. If backup or Git safety is not confirmed, stop after the audit and provide preparation instructions.

Use this concise confirmation request after the read-only audit:

> I am ready to adapt `<PROJECT_ROOT>` for MaxPkg. This may edit runtime paths and add project-local packager configuration, standard MaxPkg tooling, icon/changelog files, and a new MZP build artifact; it will not delete or replace your source files. Please confirm that I may modify this project, all work is saved and backed up, and, if this is a Git repository, all important changes are committed and pushed.

## Choose the requested scope

- For a script being created through MCP, make it package-ready from the beginning: direct runtime entry, dynamic resource paths, writable user-data paths, and no separate installer assumptions.
- For an existing script, read [references/adaptation-workflow.md](references/adaptation-workflow.md) and migrate its legacy installation actions without chaining or packaging the old installer.
- For automatic packager configuration, MZP output, release readiness, or marketplace onboarding, also read [references/build-and-verify.md](references/build-and-verify.md).
- For maxpkg.dev listing text, form guidance, categories, screenshots, Assets, version upload, or review preparation, also read [references/marketplace-publishing.md](references/marketplace-publishing.md). Refresh the official website and linked repositories before relying on field or asset requirements.
- A request to adapt a project for MaxPkg normally includes configuring the packager and attempting a local build when the required facts and 3ds Max environment are available. It never includes publishing, uploading, account changes, marketplace submission, or a Git commit unless separately requested.

## Required workflow

1. Identify the exact project root and requested scope. Inspect the complete relevant project before editing: entry files, helpers, resources, settings, macros, startup integration, callbacks, installers, uninstallers, documentation, version data, icons, tests, and build output.
2. Record the existing runtime behavior and installation responsibilities. Separate package deployment, macro/icon creation, runtime initialization, user settings, custom setup, custom cleanup, and obsolete installation-only work.
3. Adapt paths and lifecycle behavior according to the selected reference. Preserve all user project files. Exclude obsolete or private files from the package allowlist instead of deleting, moving, or renaming them.
4. After preflight consent, run the upstream helper with `-ProjectRoot <PROJECT_ROOT> -PrepareProject -ConfirmProjectWrite`. Leave a complete, manually runnable MaxPkg authoring project in the target root. The root must contain the original `maxpkg-packager.ms`, `_install.ms`, and `_uninstall.ms` downloaded from the same resolved upstream commit. Both hooks are mandatory for this skill. Preserve their implementation and headers. The helper creates missing files and stops on a conflicting same-named file; report that conflict and obtain separate approval before any replacement. Put only focused project-specific work that MaxPkg cannot perform into dedicated custom install or uninstall scripts.
5. Configure the actual project-local packager files automatically using the formats implemented by the selected packager revision. Use only metadata supported by project evidence. Ask together for any non-inferable legal or identity facts such as license, developer name, existing package GUID, paid URL, or compatibility claim.
6. When 3ds Max testing is available, select the intended Max instance, run entry points with `max_run_script_file`, launch the packager, and use process-scoped UI automation only for stable controls inside that selected `3dsmax.exe` process.
7. When validation can pass, invoke the original packager's real Build MZP action and verify the newly created archive. Do not generate a replacement ZIP/MZP or rename its output. The original packager must produce `<slug>@<major.minor.patch>@<guid>.mzp`; release channel remains separate metadata. The MZP is an additional build artifact, normally below `dist`; it never replaces the source project. Generated manifests and `mzp.run` files are build output, not substitutes for the three required root authoring files.
8. Inspect the final archive and manifests, then distinguish static validation, real installation testing, launch testing, update testing, and uninstall testing in the report.
9. When marketplace preparation is requested, generate `maxpkg-marketplace-listing.md` with complete field-ready copy, a category recommendation, FAQ questions and answers, an ordered asset plan, screenshot titles and captions, and exact upload steps. The long description must not contain an H1 (`#`) heading, and FAQ entries must not use Markdown heading wrappers. Keep the package GUID and developer-machine paths out of this public listing document.
10. Track every `fetchRoot` returned by the upstream helper. After the official files have been read and copied and the task is complete, remove only those exact verified temporary directories. Never leave stale upstream prompt/tooling downloads behind.

## Non-negotiable boundaries

- Never delete, move, rename, or replace the user's source files as part of packaging. Do not remove a legacy installer from disk merely because it must be excluded from the MZP.
- MaxPkg is the only installation system inside the adapted package. Do not add a legacy fallback or a `MaxPkg == undefined` branch that runs the old installer.
- Do not call a complete author installer or uninstaller through `fileIn`, `include`, `execute`, shell commands, generated macros, or custom hooks.
- Do not duplicate package extraction, main macro generation, icon installation, toolbar metadata, or MaxPkg notification already owned by generated MaxPkg runtime files.
- Do not hard-code a developer path, user profile, drive, 3ds Max version, package GUID, or `$temp` package folder into runtime code.
- Do not overwrite or delete existing user settings during install or update. Uninstall removes only verified package-owned integrations unless the user explicitly requests a separate user-data purge.
- Do not invent license terms, URLs, authorship, version compatibility, test results, product capabilities, or marketplace categories.
- Treat the package GUID as private identity metadata. Preserve it in package configuration, but never place it in public descriptions, screenshots, captions, keywords, or other marketplace copy.
- Do not publish, upload, commit, or push unless the user separately requests that action.

## Handoff

Report the resolved upstream commit, official prompt used, adapted runtime entry, installer-action mapping, changed and package-excluded files, automatic MaxPkg configuration, exact archive path and filename when built, generated marketplace-listing and asset-plan paths, validation performed, real-Max tests performed, untested manual checks, assumptions, and facts still requiring confirmation. Report an exact local MZP path or GUID only in the private task handoff, clearly marked as non-public metadata.
