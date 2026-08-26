# MaxPkg Marketplace Publishing

Read this reference when the user asks how to add an MZP to maxpkg.dev, prepare marketplace copy, choose a category, create screenshots, populate Assets, upload a version, or submit a package for review.

## Refresh official requirements first

Marketplace fields and policies can change. Before preparing a listing:

1. Run `scripts/get-maxpkg-upstream.ps1 -Prompt FullOnboarding` and read the returned official README, coding rules, and onboarding prompt completely.
2. Read the current official [Publish Your Script](https://maxpkg.dev/docs/creators/publish-your-script), [Max Dev Tool](https://maxpkg.dev/docs/creators/max-dev-tool), and [Categories](https://maxpkg.dev/categories) pages.
3. Follow relevant repositories linked by those official pages, beginning with [maxpkg-dev/max-dev-tool](https://github.com/maxpkg-dev/max-dev-tool). Treat the resolved upstream commit as the implementation source of truth for the packager.
4. If an authenticated browser session is available, inspect the current Create Package, Assets, and Versions forms read-only before finalizing field-specific guidance. Do not use private APIs, bypass access controls, or claim that an uninspected field exists.
5. When official sources disagree, follow the current public website for marketplace policy and the pinned repository revision for packaging behavior. Identify the conflict and request confirmation when it affects a user decision.

Never guess current categories, limits, image dimensions, accepted formats, pricing fields, or review requirements. Mark any fact that could not be verified as requiring confirmation in the live form.

## Start from a verified package

Inspect the built MZP, `maxpkg-packager.ini`, `maxpkg-changelog.ini`, icon, manifest files, and project documentation before writing marketplace copy. Confirm the exact packager-produced filename and current version.

The public documentation states that maxpkg.dev reads core facts from the uploaded MZP, including package name, short description, version, supported 3ds Max versions, license, changelog, icon, and links. Fix incorrect package facts in the project configuration and rebuild with the original packager instead of contradicting the archive on the website.

Preserve the package GUID for the lifetime of the package. The GUID is private identity metadata: keep it out of public listing documents, descriptions, keywords, captions, screenshots, filenames, and chat-ready copy. It may appear only in package configuration and a private handoff note needed to verify the exact artifact.

## Generate the complete listing package

Do not merely explain the form. After mandatory write consent, create `maxpkg-marketplace-listing.md` in the project root. Do not include it in the MZP unless the user explicitly wants it shipped as documentation.

Populate the document with evidence-backed, ready-to-paste content in this order:

- Package name.
- Recommended current marketplace category and a one-sentence rationale.
- One-sentence summary.
- Short description.
- Long Markdown description.
- Feature list.
- Typical workflow or concise usage steps.
- Requirements and verified compatibility.
- License and developer details.
- Documentation, homepage, support, source, license, and purchase links that actually exist.
- Current version, release channel, release date, and factual changelog.
- Search keywords only when the current form supports them.
- FAQ questions and answers.
- Ordered asset plan with filename, title, caption, exact capture state, and readiness status for every image.
- Exact MZP filename to upload, without a developer-machine absolute path.
- Fields still requiring user confirmation.
- Exact dashboard upload and review checklist.

The long description must not contain an H1 heading. Never emit a line beginning with a single `# ` in the paste-ready description. The package name already has its own marketplace field. Start with a plain introductory paragraph; use `##` only when section headings materially improve readability.

The FAQ must not use Markdown headings such as `#`, `##`, or `###`. Format each entry as plain `Question:` and `Answer:` lines, or use bold labels when the live editor supports them. Include only questions supported by project evidence, such as compatibility, installation, update behavior, settings persistence, uninstall behavior, documentation, support, and licensing.

Keep the public listing portable and anonymous. Do not include absolute local paths, usernames, machine names, account identifiers, private URLs, API keys, customer assets, raw logs, or the package GUID. Report the exact local MZP path separately in the private task handoff.

## Write factual marketplace copy

- Use concise plain English and describe the user outcome before implementation details.
- Do not invent features, test results, compatibility, legal terms, authorship, support promises, prices, links, or categories.
- Distinguish verified behavior from planned behavior. Do not advertise backlog items.
- Use the same product name, capitalization, version, and terminology as the package metadata.
- Avoid unsupported superlatives and generic AI-generated marketing language.
- Make the short description understandable without the long description.
- Keep install instructions aligned with MaxPkg; do not tell users to run legacy installers that are excluded from the package.

## Prepare screenshots and Assets

Use real product UI, real workflow states, and real results. Do not fabricate screenshots, use stock images as proof, or show a success state that was not reached.

Prepare a coherent ordered set:

1. A strong cover or primary screenshot that explains the product at a glance.
2. The main UI in a representative, populated state.
3. A meaningful workflow, before-and-after comparison, or result view.
4. Additional images only when they demonstrate a distinct capability or reduce ambiguity.

For every proposed image, generate:

- a sanitized lowercase filename;
- a short title;
- a factual one-sentence caption;
- the exact scene, UI, camera, selection, and data state to capture;
- the capability the image proves;
- crop or composition notes;
- a status of `ready`, `capture required`, or `confirmation required`.

Inspect the current Assets form for accepted formats, dimensions, aspect ratio, file-size limits, image count, ordering, and crop behavior. Do not invent these constraints when they are not documented publicly.

For a 3ds Max viewport result:

1. Wait for the scene and viewport to become stable.
2. Clear selection unless selection is necessary to explain the operation.
3. Maximize the viewport and frame the intended result cleanly.
4. Hide selection brackets, outlines, grids, helpers, gizmos, tooltips, floating menus, and unrelated interface elements unless they are essential evidence.
5. Use an appropriate Shaded or Realistic mode and the best stable anti-aliasing available without changing the artistic result.
6. Capture through `max_capture_viewport` or the selected-process window capture path, then visually inspect the image before accepting it.

For UI screenshots, show the real tool at a useful scale with representative non-sensitive data. Include enough 3ds Max context to establish authenticity, but crop unrelated desktop content. Remove developer paths, e-mail addresses, keys, customer names, account data, machine identifiers, and personal notifications.

If screenshots cannot be captured in the current environment, do not substitute fake images. Leave an exact shot list that the user or a later connected Max session can reproduce.

## Explain and perform the upload safely

Use the current labels from the live site when available. The documented flow is:

1. Sign in to maxpkg.dev and complete the developer onboarding exposed by the account interface.
2. Open the developer dashboard and create a package.
3. Fill the package fields from `maxpkg-marketplace-listing.md` and select the verified current category.
4. In Assets, add the icon, cover or first screenshot, and remaining screenshots in the planned order. Apply the prepared titles and captions where the form supports them, then inspect preview and crop results.
5. In Versions, upload the exact original-packager MZP named `<slug>@<major.minor.patch>@<guid>.mzp`.
6. Privately verify that the displayed package identity, version, compatibility, changelog, icon, and links match the inspected archive. Never copy the GUID into a public field.
7. Preview the package page and test every public link. Correct package-owned metadata in the MaxPkg project and rebuild when the MZP is wrong.
8. Submit the package or version for review only after the user explicitly authorizes that external action. New packages and versions remain subject to marketplace review.

A request for instructions, listing copy, screenshots, or release preparation does not authorize sign-in, upload, submission, publication, account changes, or payment-related actions. Pause immediately before the first external mutation unless the user explicitly requested it and the exact package, version, and account are established.
