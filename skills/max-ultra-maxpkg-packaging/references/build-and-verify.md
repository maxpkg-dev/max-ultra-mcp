# MaxPkg Configuration, Build, and Verification

Read this reference when the user asks to adapt a project for MaxPkg, configure MaxPkg Packager, produce an MZP, prepare a release, or complete marketplace onboarding.

## Use the official project tooling

Leave this authoring layout in the target project:

```text
<PROJECT_ROOT>\
  maxpkg-packager.ms
  _install.ms
  _uninstall.ms
  maxpkg-packager.ini
  maxpkg-changelog.ini
  maxpkg-icon.svg
  <runtime entry and resources>
  dist\
```

The three `.ms` files are mandatory in the project root even when the current project has no custom installation or cleanup action. For this skill, a project without either standard hook is incomplete and must not be reported as ready. Use the original standard hooks fetched with the packager from the same resolved GitHub commit and do not rewrite them with project code. The `dist` directory may be created by the packager on the first successful build.

Fetch the current official repository through `scripts/get-maxpkg-upstream.ps1`. Read the returned official prompt instead of a local prompt snapshot. Do not mix packager and hook files from unrelated revisions, overwrite a different local revision without review, or strip upstream headers.

Project-local configuration includes `maxpkg-packager.ini`, `maxpkg-changelog.ini`, and `maxpkg-icon.svg`; normal output defaults to `dist`. These files and the MZP are added alongside the user's sources. Generated manifests and `mzp.run` files exist inside build output and never replace the root authoring files or the original project.

## Configure the packager automatically

Do not stop at a table of recommended values when the selected packager can be configured locally.

1. Read the selected `maxpkg-packager.ms` revision's current load/save methods and INI schema.
2. Create or update its project-local configuration and versioned changelog using that exact implemented format, or use stable Max-owned UI controls when direct configuration is unsafe.
3. Preserve unknown settings and an existing valid GUID.
4. Reopen or refresh the packager and confirm that every configured field round-trips correctly.
5. Resolve every validation error that can be fixed from project evidence.
6. Ask one compact grouped question only for required facts that cannot be inferred safely.

### Info

- Package Name and Button Name use only characters accepted by the current packager.
- Preserve an existing valid package GUID. Generate one only for a genuinely new package identity.
- Set a factual short description and developer name.
- License is a legal decision. Use only a confirmed supported value.
- Add documentation, homepage, support, license, and purchase links only when they exist and are verified.

### Setup

- Decide whether to create the main 3ds Max button and expose it in the MaxPkg toolbar.
- Configure and verify both standard root hooks, `_install.ms` and `_uninstall.ms`, even when they currently perform only the official default lifecycle behavior.
- Select focused custom install or uninstall scripts through the dedicated fields. Do not also add them to the ordinary file list.

### Files

- Include the complete runtime allowlist and exclude tests, caches, logs, source archives, credentials, old installer launchers, unrelated notes, previous MZPs, and temporary output.
- Select one supported `.ms`, `.mse`, or `.py` entry file that launches the tool directly.
- Decide `.ms` to `.mse` compilation using actual runtime compatibility evidence.
- Use Build Path Remap only when the installed layout intentionally differs from the source layout, then recheck every runtime path and macro target.
- Configure Extra Macros for reviewed secondary commands. Add Quad Menu integration only when useful and supported.
- Use a square SVG icon that belongs to the project and remains legible at small sizes. Do not invent misleading branding.

### Release

- Use a supported semantic version and release channel.
- Use a real `YYYY-MM-DD` release date.
- Set minimum 3ds Max version from code and test evidence, not aspiration.
- Add at least one factual changelog item for the current version.

## MCP-assisted configuration and build

1. Call `max_list_instances` and select the intended test instance explicitly when several are connected.
2. Call `max_get_info` and record the real 3ds Max version used for testing.
3. Test the adapted entry with `max_run_script_file` before packaging. Verify expected UI or scene post-state without modifying a real user scene unexpectedly.
4. Run the target project's `maxpkg-packager.ms` with `max_run_script_file`.
5. Use `max_ui_wait`, `max_ui_inspect`, stable selectors, and other process-scoped UI tools only inside the selected `3dsmax.exe`. Reinspect controls after a rollout or floater is recreated.
6. Use the packager's own validation. Do not reimplement its archive generator as an unverified substitute.
7. When required metadata is complete and validation passes, invoke the real Build MZP action for the user.
8. Wait for completion, inspect the packager status and log, and verify that a new expected MZP exists without altering source files.

Do not guess at a localized label or use coordinates when a stable control or project-local configuration format is available. Any operation that installs, uninstalls, replaces existing generated configuration, or launches arbitrary scripts remains a write requiring normal approval.

If 3ds Max or a stable build action is unavailable, complete automatic project configuration and every static check possible. State the precise blocker and leave the shortest one-action manual build instruction; do not claim an MZP exists.

## Manual reproducibility acceptance

Before handoff, confirm that the project is usable without the AI agent:

1. the three mandatory root `.ms` files exist and belong to the same reviewed MaxPkg revision;
2. `maxpkg-packager.ini`, `maxpkg-changelog.ini`, and `maxpkg-icon.svg` exist and contain the reviewed project-specific configuration;
3. running the root `maxpkg-packager.ms` in 3ds Max loads that project-local configuration;
4. the packager reaches its ready state after required metadata is supplied;
5. the user can invoke Build MZP and receive the archive below `dist`.

Attempt the build for the user when the selected 3ds Max instance and stable packager controls are available. The build must be performed by the fetched original `maxpkg-packager.ms`, not by a custom archive generator. If 3ds Max is unavailable, leave the fully configured authoring project and state the single manual action: run `maxpkg-packager.ms` in 3ds Max and choose Build MZP.


## Static archive verification

After a successful build, inspect the MZP as an archive and verify:

- the filename exactly matches the original packager result `<slug>@<major.minor.patch>@<guid>.mzp`;
- the slug is derived by the original packager from Package Name, and the release channel is not appended to the version or filename;
- `manifest.ini`, `manifest.json`, `maxpkg-changelog.ini`, `mzp.run`, and `mzp.run.ms`;
- both original standard hooks, `_install.ms` and `_uninstall.ms`;
- entry file and generated macro targets;
- standard and custom hook declarations;
- package icon path;
- complete expected runtime files and no excluded/private files;
- Build Path Remap results and case-correct relative paths;
- no developer-machine absolute paths, credentials, logs, or previous package artifacts.

A statically valid archive is not proof that installation or runtime behavior works.

## Real 3ds Max acceptance

When the user authorizes testing in a suitable non-production Max environment, verify:

1. clean installation completes;
2. the main generated button launches the installed entry;
3. extra macros and requested Quad Menu entries launch the correct installed files;
4. icon display is correct;
5. focused custom install work completes once and tolerates update or reinstall;
6. existing user settings survive update;
7. silent uninstall removes only package-owned integrations;
8. reinstall succeeds after uninstall.

Do not claim these checks when only source or archive inspection was performed. Provide the shortest remaining manual checklist.

## Marketplace onboarding is optional

Prepare marketplace listing text, screenshots, cover guidance, category confirmation, and upload instructions only when the user requests full onboarding or publication preparation. Never sign in, upload, submit, or publish without explicit authorization.

When requested, base every statement on the project and tested package. Sanitize screenshots and documents: remove user paths, keys, e-mail addresses, customer data, private URLs, and unrelated desktop content. If the live category list cannot be inspected, mark the recommendation for confirmation instead of inventing a category.

Official source material:

- [MaxPkg Packager README](https://github.com/maxpkg-dev/max-dev-tool/blob/93ceb0e018b44ca53546cf2c274b196160495699/README.md)
- [MaxPkg Full Onboarding Prompt](https://github.com/maxpkg-dev/max-dev-tool/blob/93ceb0e018b44ca53546cf2c274b196160495699/maxpkg-full-onboarding-prompt.md)
