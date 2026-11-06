# Listing Content and Images

Read this reference before writing maxpkg.dev listing copy or making the cover and screenshots. It extends the listing rules of `max-ultra-maxpkg-packaging`. When that skill produced `maxpkg-marketplace-listing.md`, check the file against this reference instead of starting over.

## Facts first

- Read the project before writing: README, source, changelog, packager settings, and `manifest.json` inside the built MZP.
- Describe only what the tool actually does in the version being published. Make no claims the tool does not support: no invented features, compatibility, prices, or test results, and no planned features.
- Use the package name, capitalization, version, and terms from the manifest.
- Keep the package GUID, local paths, user names, machine names, e-mail addresses, scene authors, customer names, and private URLs out of every text field and image.

## Who the text is for

Write for an ordinary 3ds Max user who has never heard of the tool. After one read, they should know what it does, what they can do with it, and how to use it. Explain it so simply that a tired, distracted reader still gets it.

- Use plain words and short sentences.
- Leave out internal technical details such as file formats, algorithms, and code, and leave out test statistics.
- Do not add thanks lists, credits to people who helped, or links the user did not ask for.
- Do not pad the text, and do not leave out a real feature either.
- Look at two or three well-described packages in the maxpkg.dev catalog, such as Max Ultra MCP, TerraScoop, or Dropper, for tone and depth, but keep the text easy to follow.
- Avoid superlatives and generic marketing language.

## Short description

One or two sentences, up to about 250 characters: what the tool does and its main benefit, in plain words. It must make sense without the long description.

Use the same text for the packager `description` option. Every version upload replaces the site's Short Description with the manifest `description`, so the manifest must already hold the final text.

## Full description

Markdown without an H1 heading, because the name has its own field. Usually 400 to 800 words. Use these sections:

1. An introductory paragraph: what the tool does, followed by one concrete example. For example: "You saved a scene in 3ds Max 2027 and your client has 2022: drop the file in, choose 2022, and press Convert."
2. `## What you can do with it`: the everyday tasks it solves.
3. `## How to use it`: numbered steps from start to result, with the real button and panel names.
4. `## Features`: every real feature, one line each.
5. Optional: a small table when it helps a user decide, for example supported versions or formats.
6. `## Good to know`: limits, plugins, and other things a user must know before relying on it, and where its files and settings go.
7. `## Requirements`: the verified 3ds Max range, operating system, anything else needed, and whether it is free.

## Category, tags, and links

- Category: exactly one, from the site's current list.
- Tags: at most five, lowercase except product names. Prefer tags that already exist on the site. Use short, searchable terms a 3ds Max user would type. Do not repeat the category or the package name.
- Links: homepage, documentation, GitHub, and license only when they exist. The purchase or donation URL and its button text come from the manifest; open them to check.

## FAQ

Five to eight plain question-and-answer pairs. Questions are plain text without Markdown headings. Cover only what project evidence supports, usually:

- Which 3ds Max versions are supported?
- Does it change my files or scenes?
- Does it need plugins or other dependencies?
- Where are its settings kept, and do they survive an update?
- Is it free or paid, and what does the license allow?
- The most likely "How do I ...?" question.

## Cover

- Square, 1024 x 1024 pixels; PNG, JPG, or WEBP up to 5 MB.
- The logo and package name large at the top, a one-line subtitle, one simple illustration of what the tool does, and a short tagline.
- It must read well at 240 pixels.
- Direction and motion cues must be logical: an arrow points from the input to the result. For example, a rewind arrow points from the source state to the restored target.

## Screenshots

Upload 6 to 12 images, PNG, JPG, or WEBP, up to 10 MB each. The first one is the primary image; drag images on the Images page to reorder them. Capture the real tool with neutral demo data and neutral folder and scene names, and never mock the interface. Upload two kinds:

- **Plain screenshots, required.** The tool exactly as a user sees it, with no design around it. Take at least one inside 3ds Max with the tool window open over the viewport. Add the tool window on its own for each main step: the main window with data, important menus or dialogs, Settings, and the result. These show users what they will really get. Presentation cards alone are never enough.
- **Presentation cards, optional.** 16:9, 1920 x 1080 pixels, on a dark background, with a short title and a subtitle at the top left and the real interface below. Show one feature per card, in the order a user meets them.

Capture Max-owned windows with `max_ui_capture_window` and viewport results with `max_capture_viewport`, and inspect every image before using it. Never show a UI state or a result that the tool did not produce.

## Privacy review of every image

Before uploading, look at each image at full size and check:

- window titles, file dialogs, and path fields, since the 3ds Max title bar shows the scene path;
- user and machine names, e-mail addresses, scene author fields, layer or object names from customer work, and notifications;
- the package GUID, which is in the MZP file name;
- metadata: remove EXIF, XMP, and PNG text chunks that hold prompts, source paths, or account data.

Replace a failing image with a new capture or a cropped one. Do not blur personal data that a clean capture could avoid.
