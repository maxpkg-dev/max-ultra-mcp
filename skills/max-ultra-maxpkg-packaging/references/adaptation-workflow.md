# MaxPkg Adaptation Workflow

Use this reference for both package-ready development and migration of an existing 3ds Max project.

## Audit before editing

Build a bounded inventory of:

- the real `.ms`, `.mse`, or `.py` runtime entry;
- secondary commands that may need extra macros or Quad Menu entries;
- helper scripts, assemblies, icons, presets, localization, data, documentation, and other runtime resources;
- saved settings and the writable location that owns them;
- callbacks, startup scripts, menus, macros, toolbar actions, and external registrations;
- legacy installer and uninstaller actions;
- version, license, developer, compatibility, and changelog evidence;
- build output, tests, source archives, caches, private notes, credentials, and other files that must not enter the package.

Do not start with the old installer as the architecture. First establish what launches the actual tool and what it needs at runtime.

## Preserve the project

Packaging produces an additional MZP artifact; it does not replace the user's source tree.

- Never delete, move, or rename original files during adaptation.
- Do not overwrite an existing source file with generated package output.
- Keep legacy installers and obsolete launchers in the project unless the user separately requests their removal. Exclude them from the package file list and archive.
- Preserve source-only documentation, tests, design assets, and backups while excluding them from production package inputs.
- When runtime code must be edited for dynamic paths or lifecycle compatibility, keep the change focused and preserve unrelated behavior.

## Required MaxPkg authoring files

After the user approves adaptation, use the launcher returned by `scripts/get-maxpkg-upstream.ps1` and ensure the target project has this MaxPkg Packager 2.x layout:

- `maxpkg-packager.ms` in the project root, the original launcher from the resolved GitHub commit;
- `max-package\project.ini` and `max-package\changelog.ini`, written by the packager;
- `max-package\icon.svg`, the square package icon;
- `max-package\_install.ms` and `max-package\_uninstall.ms`, the standard hooks.

Copy the launcher into the project root when it is missing. If a same-named file already exists, compare it with the fetched upstream file. Do not silently overwrite a modified or mismatched file; explain the conflict and request separate approval before replacement. Preserve its upstream header and implementation.

Both standard hooks are mandatory in every package. They ship with the packager, which copies them into `max-package` when it opens the project and replaces copies that differ from its own. Do not download, edit, or move them, and do not keep copies in the project root. The first run of the launcher installs the packager into the user profile and needs internet access once.

A project made with packager 1.x keeps `maxpkg-packager.ini`, `maxpkg-changelog.ini`, `maxpkg-icon.svg`, `_install.ms`, and `_uninstall.ms` in its root. The packager moves them into `max-package` on first open; let it do that instead of moving files by hand, then update any project script, ignore rule, or document that still names the old root files.

The launcher and the `max-package` folder keep the project independently buildable in 3ds Max. Do not treat generated manifests, generated `mzp.run` files, or a previously built MZP as replacements for them. Do not add the standard hooks to the ordinary package file list: MaxPkg embeds them in every package. Retain unrelated legacy author installers in the source tree, but exclude them from the package. Keep the project root clean: anything created for packaging belongs in `max-package`.

## New package-ready projects

When MCP is helping create the script itself:

- keep one direct runtime entry file that launches the tool from its installed package location;
- resolve helpers and read-only resources relative to the script that owns them;
- write settings and user-generated data only to a suitable writable 3ds Max user directory;
- keep runtime initialization in the entry or a focused runtime helper, not an installer;
- reserve custom lifecycle hooks for actions that cannot happen lazily at runtime;
- keep package identity, release metadata, macro generation, compilation, and icon installation in MaxPkg Packager.

This avoids creating a legacy installer that must later be migrated.

## Existing-project migration

Read the old installer and uninstaller only to classify their responsibilities. Map each required action as follows:

| Legacy responsibility | MaxPkg adaptation |
| --- | --- |
| Copy project files | Include the required files and preserve package-relative layout. |
| Create the main macro or toolbar button | Configure the main button and entry file in MaxPkg Packager. |
| Create secondary macros | Configure Extra Macros; enable Quad Menu only when requested and supported. |
| Install an icon | Use the square package SVG and generated MaxPkg macro handling. |
| Initialize runtime-only state | Move it into the entry file or a focused helper loaded by the entry. |
| Create default user settings | Initialize lazily in a writable user location without overwriting existing data. |
| Register a callback or package-owned startup integration | Extract only that action into a focused custom install script when runtime registration is unsuitable. |
| Remove a callback or package-owned integration | Use a focused custom uninstall script with ownership checks. |
| Show an author installer UI or copy package payload manually | Exclude that behavior from the package while retaining the original source file. |

## Runtime paths

MaxPkg installs into a GUID-owned package directory. Runtime code must discover its own location rather than predict that directory.

Prefer a role-specific variable and the executing script:

```maxscript
local scriptFolderPath = getFilenamePath (getThisScriptFileName())
local helperFilePath = scriptFolderPath + "helpers\\tool-helper.ms"

if (not doesFileExist helperFilePath) do throw "Required helper file does not exist"
fileIn helperFilePath
```

Use `getSourceFileName()` only when the actual execution context makes `getThisScriptFileName()` unreliable and that behavior has been verified. Review path behavior again when compiling `.ms` to `.mse` or applying Build Path Remap.

Never embed a source checkout, user name, drive letter, current Max version, package GUID, or assumed `$temp` subfolder. Use `getDir` only for data that genuinely belongs in a user-writable 3ds Max directory.

## Settings and updates

- Preserve existing settings during installation and update.
- Separate immutable package resources from mutable user data.
- Do not write settings beside the installed entry file merely because the source project did so.
- Make first-run defaults safe and repeatable.
- Make focused custom lifecycle actions idempotent where practical.
- Uninstall package-owned callbacks, startup files, and registrations only after resolving and verifying their exact targets.
- User-created presets and content survive normal uninstall unless the user explicitly requests a separate purge policy.

## MaxScript quality during adaptation

- Preserve the project's stricter established conventions.
- Avoid ambiguous identifiers such as `path`, `text`, `name`, `section`, `icon`, `ok`, and `value`; use role-specific names.
- Declare temporary state locally, prefix unavoidable globals, and keep UI state separate from processing state.
- Give value-producing functions explicit returns and use clear guard failures.
- Format named arguments as `argumentName: argumentValue` and use `+` rather than `format` for string concatenation.
- Check file existence before execution, copy, or deletion. Do not hide required failures in empty `catch` blocks.
- Treat generated MaxScript, macros, manifests, and cleanup scripts as production output and inspect their final contents.
- Keep new `.NET` UI bindings stable and avoid repeated event registration when a rollout reopens.

## Adaptation acceptance

Before declaring migration complete, confirm:

1. no final code path launches the complete legacy installer or uninstaller;
2. obsolete installer launchers are absent from the package file list and archive but remain in the user's source tree;
3. the runtime entry launches directly from a package-relative location;
4. every required resource is present and dynamically resolved;
5. custom hooks contain only focused additional work and are not duplicated in the ordinary file list;
6. a clean install does not depend on a prior version of the tool;
7. update preserves user settings;
8. uninstall affects only package-owned integrations;
9. the project root contains the reviewed `maxpkg-packager.ms` launcher, `max-package` contains both standard hooks, and no packaging file was left in the root;
10. a user can run `maxpkg-packager.ms` in 3ds Max and build the MZP without the AI agent;
11. tests claimed in the handoff were actually performed.

Official source material:

- [MaxPkg Adaptation Prompt](https://github.com/maxpkg-dev/max-dev-tool/blob/dec469a8791d7e1d2ec978c3ea1668c0fce1158e/docs/maxpkg-adaptation-prompt.md)
- [Recommended MaxScript Coding Rules](https://github.com/maxpkg-dev/max-dev-tool/blob/dec469a8791d7e1d2ec978c3ea1668c0fce1158e/docs/code-rules.md)
- [MaxPkg Packager for AI agents](https://github.com/maxpkg-dev/max-dev-tool/blob/dec469a8791d7e1d2ec978c3ea1668c0fce1158e/docs/ai-agents.md)
