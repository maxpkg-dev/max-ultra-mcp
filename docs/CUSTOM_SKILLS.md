# Create and import a skill

Save a successful workflow so your AI assistant can reuse it.

## Create

1. Complete a task with your AI assistant and check the result.
2. In Max Ultra MCP, open **Skills > How to create and import skills**. Read the displayed creation prompt and click **Copy prompt** in that dialog.
3. Paste the prompt into the **same AI conversation** where you completed the task.
4. Ask the assistant to save the skill as a folder or ZIP containing **SKILL.md**. Keep any required references and images with it.

## Import and use

1. Choose **Import Folder** for one folder, or **Import ZIPs** for one or more archives.
2. Select the sources. Valid skills are imported immediately for Codex, Claude Code, and Antigravity. Each ZIP is checked independently; a failed archive does not stop the others or replace an existing skill.
3. Read the results in the preview pane. Successful imports and any errors remain visible until you choose another action or select a skill. Restart your AI client or start a new chat, then ask it to use the skill for a matching task.

A ZIP must contain exactly one skill: **SKILL.md** at the archive root or inside one enclosing folder. The filename must be exactly **SKILL.md**. Use a standard, unencrypted ZIP.

Import sends no data. Your AI client may send instructions and images to its model provider when using the skill. Choose only skills you trust; Delete removes an unwanted imported skill.

## Browse and remove

New packages should include **skill.json** beside **SKILL.md** with an explicit display title, description, author and version. See [the metadata format](SKILL_METADATA.md). Right-click a skill and choose **About** to view this information, or **Open folder** to inspect the imported files. Older packages still work; missing attribution and version are shown as **Not specified**.

Click a reference to read it. **Back** returns to the previous document. Built-in skills are read-only.

To remove a custom skill, select it and click **Delete**. This removes the imported copy and its client entries; your original folder or ZIP is kept. To update a skill, edit the original, delete the imported copy, and import again.

## If import fails

- Include **SKILL.md** with a name, description, and instructions. Ask the assistant to follow the copied creation prompt.
- An optional one-line `author` field in the frontmatter stores attribution (1-256 characters). The Skills list displays the name and description.
- Include every referenced file. Supporting text belongs in **references/**; images belong in **assets/**.
- Supported attachments: MD, TXT, JSON, CSV, PNG, JPG, JPEG, and WebP. Scripts, nested archives, links to other folders, and client configuration files are not accepted.
- Limits: 200 files and 50 MiB total; SKILL.md up to 64 KiB, other text up to 1 MiB each, images up to 5 MiB each. ZIP files may be up to 54 MiB; the expanded contents must meet the same limits.
- If several skills are in one ZIP, put each skill in its own ZIP and import them separately.

## Install from Community Skills

Click **Install community skills** in the Skills window to browse the public catalog inside Max Ultra MCP. Search by title, description or author, then click **Install** on a skill. The owned background helper fetches the official catalog and archive, checks the exact size and SHA-256, validates its metadata and package, and uses the normal local importer. Merely viewing the list never installs or executes content. Start a new AI conversation after import.

**Open online catalog** remains available for manual downloads, including when offline or a request fails. **Refresh** retries the feed. The catalog is read from `https://maxpkg-dev.github.io/max-ultra-mcp-community-skills/catalog.json`; only schema version 1 is supported. Official GitHub release ZIPs and their HTTPS asset redirects are accepted. Feed downloads are limited to 2 MiB, archives to 50 MiB, redirects to five, and network operations have bounded timeouts. Existing ZIP expansion and file validation limits still apply.

An existing skill with the same machine name is never overwritten. A different version offers **Manage installed**: inspect and back up your local files via **Open folder**, explicitly delete that copy if replacement is intended, then Refresh the catalog and Install. A checksum mismatch or changed catalog requires Refresh; it never bypasses verification.
