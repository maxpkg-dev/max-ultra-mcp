# maxpkg.dev Site Map

Read this reference before acting on a maxpkg.dev dashboard page. It describes the site as verified for a signed-in developer on 2026-11-06. Labels, limits, and addresses can change: read each page with the browser's page-reading tools before acting, and report any difference.

## Pages

Every package page is a sibling below `/dashboard/packages/<id>/`, where `<id>` is the package's dashboard id. Use the page's own navigation when an address changes.

| Page | Purpose |
| --- | --- |
| `/dashboard/packages` | Package list and Quick MZP import for a new package |
| `/dashboard/packages/<id>/edit` | Metadata |
| `/dashboard/packages/<id>/assets` | Images: cover and screenshots |
| `/dashboard/packages/<id>/links` | Links |
| `/dashboard/packages/<id>/faq` | FAQ |
| `/dashboard/packages/<id>/versions` | Versions and Quick version import |
| `/dashboard/packages/<id>/publication` | Review status |

## Packages: Quick MZP import

- File input: `input.file-dropzone__input[accept=".mzp"]`.
- The file name must be the original packager name `<slug>@<major.minor.patch>@<guid>.mzp`.
- The first upload creates the package with status Pending Review.
- Wait for "Upload complete", then open the new package from the list.

## Metadata

Changes autosave and show "Saved". Wait for it after each field.

- Name.
- Category: a custom dropdown. Open it and click the option with a real pointer click.
- License Type.
- Short Description: a plain textarea.
- Full Description: a plain textarea that takes Markdown. Do not use an H1 heading.
- Tags: a combobox with at most 5 tags. A synthetic `element.click()` on its options is ignored. Type the tag and press Enter, or click the option for real with the browser tool's click action.

When a value is set by script instead of typing, confirm that "Saved" appears and that the value survives a reload. Otherwise, type it with the browser tool.

## Images

- Cover: a single-file input. PNG, JPG, or WEBP, up to 5 MB. The image must be square.
- Screenshots: a multi-file input, up to 10 MB each. The first screenshot is the primary one, so upload in the planned order. Uploaded images can be reordered by drag and drop.
- The page also accepts Ctrl+V for screenshots. That needs a real system clipboard; it does not work through the Claude desktop built-in browser.
- After the cover upload, check the CDN thumbnail `https://cdn.maxpkg.dev/scripts/<id>/cover/cover-thumb.webp`. Take the exact URL from the page and add a cache-busting query.

To find the right input before a relay injection, list the file inputs on the page:

```javascript
Array.from(document.querySelectorAll('input[type="file"]'), (input, index) => ({
  index,
  accept: input.accept,
  multiple: input.multiple,
  className: String(input.className),
  section: (input.closest("section, form, fieldset") || input.parentElement).textContent.trim().slice(0, 80),
}));
```

Pick a selector that matches exactly one input, for example by its `accept`, `multiple`, or the section it belongs to.

## Links

- Documentation URL, GitHub URL, License URL, and Homepage URL.
- Purchase URL and purchase button text.
- The manifest prefills the homepage and purchase values.
- Fill only links that exist, and open each one to check it.

## FAQ

- "Add FAQ item" opens a question input (placeholder "How do I use this package?") and an answer textarea.
- Up to 20 items. Changes autosave.
- Questions and answers are plain text; do not use Markdown headings.

## Versions

- Quick version import uploads a new MZP version of this package.
- Existing version numbers are blocked. A release cannot be overwritten or edited.
- Row actions are only Download and Archive. There is no delete. Archive needs the user's explicit yes.
- The table shows each version's 3ds Max range. Check it after every upload.
- Every version upload replaces the Short Description with the manifest `description`. Check it after the upload.

## Publication

- Shows the review status: Awaiting approval or Approved.
- Report the status; do not try to change it.

## Content Security Policy

Directives observed on the dashboard pages:

- `connect-src 'self' https://*.supabase.co https://cdn.maxpkg.dev ...`: the page cannot fetch from localhost.
- `frame-src` allows YouTube only, so a local page cannot be framed.
- `img-src` allows `https:`, `data:`, and `blob:`.

The policy does not restrict top-level navigation. That is why the [URL-fragment relay](file-relay.md) works.
