# Create and import a skill

Save a successful workflow so your AI assistant can reuse it.

## Create

1. Complete a task with your AI assistant and check the result.
2. In Max Ultra MCP, open **Skills > How to Create and Import Skills**. Read the displayed creation prompt and click **Copy prompt** in that dialog.
3. Paste the prompt into the **same AI conversation** where you completed the task.
4. Ask the assistant to save the skill as a folder or ZIP containing **SKILL.md**. Keep any required references and images with it.

## Import and use

1. Choose **Import Folder** for one folder, or **Import ZIPs** for one or more archives.
2. Select the sources. Valid skills are imported immediately for Codex, Claude Code, and Antigravity. Each ZIP is checked independently; a failed archive does not stop the others or replace an existing skill.
3. Imported skills appear under **Installed**. If a source fails, an import report opens with the reason for each one. Restart your AI client or start a new chat, then ask it to use the skill for a matching task.

A ZIP must contain exactly one skill: **SKILL.md** at the archive root or inside one enclosing folder. The filename must be exactly **SKILL.md**. Use a standard, unencrypted ZIP.

Import sends no data. Your AI client may send instructions and images to its model provider when using the skill. Choose only skills you trust; Delete removes an unwanted imported skill.

## Browse and remove

New packages should include **skill.json** beside **SKILL.md** with an explicit display title, description, author and version. See [the metadata format](SKILL_METADATA.md). Click **View details** on a card to read the skill together with its author, version, source and contacts; **Open Folder** there shows the imported files. Older packages still work; missing attribution and version are shown as **Not specified**.

Click a reference to read it. **Back** returns to the previous document. Built-in skills are read-only.

To remove an installed skill, click the red trash button on its card and confirm. This removes the imported copy and its client entries; your original folder or ZIP is kept. To update a skill, edit the original, delete the imported copy, and import again.

## If import fails

- Include **SKILL.md** with a name, description, and instructions. Ask the assistant to follow the copied creation prompt.
- An optional one-line `author` field in the frontmatter stores attribution (1-256 characters). The skill card displays the title and description.
- Include every referenced file. Supporting text belongs in **references/**; images belong in **assets/**.
- Supported attachments: MD, TXT, JSON, CSV, PNG, JPG, JPEG, and WebP. Scripts, nested archives, links to other folders, and client configuration files are not accepted.
- Limits: 200 files and 50 MiB total; SKILL.md up to 64 KiB, other text up to 1 MiB each, images up to 5 MiB each. ZIP files may be up to 54 MiB; the expanded contents must meet the same limits.
- If several skills are in one ZIP, put each skill in its own ZIP and import them separately.

## Install from Community Skills

The Skills window shows every skill as a card. Two filters sit under the search field: **Community**, which is always selected when the window opens, and **Built-in**. Community lists your installed skills first and the skills that are not installed below them. A search looks through all skills, whichever filter is selected, by title, description or author. Built-in and installed skills appear at once, without a loading step. The public catalog is refreshed in the background: the Community section shows the last saved catalog immediately and updates when the new one arrives.

Community cards have a dashed outline and are not installed until you click **Install**. The owned background helper fetches the official catalog and archive, checks the exact size and SHA-256, validates its metadata and package, and uses the normal local importer. Viewing the catalog never installs a new skill or executes content. An installed skill is listed once, in the Installed group. Start a new AI conversation after import.

**View details** opens one details window with the skill's metadata and, for built-in and installed skills, its instructions. Choosing another skill replaces the content of that window instead of opening another one. For a community skill that is not installed, the window loads its published description from the catalog site and shows it in place; if that fails, it offers **Open Online Page** in the middle of the window.

**Online Catalog** remains available for manual downloads, including when offline or a request fails. **Refresh** and **Retry** reload the feed; a saved catalog stays visible when a refresh fails. The catalog is read from `https://maxpkg-dev.github.io/max-ultra-mcp-community-skills/catalog.json`; only schema version 1 is supported. Official GitHub release ZIPs and their HTTPS asset redirects are accepted. Feed downloads are limited to 2 MiB, archives to 50 MiB, redirects to five, and network operations have bounded timeouts. Existing ZIP expansion and file validation limits still apply.

### Automatic updates

When the catalog loads and lists a newer version of a skill you installed from Community, that skill is updated without a click. Only a matched community copy is replaced: the same machine name, title and author, a declared Community Skills source, a ready state, and files that are unchanged since installation. The new archive is downloaded, verified and unpacked before the old copy is removed, and the update keeps the AI clients the skill was registered for. An older catalog version never downgrades an installed skill.

A copy you imported yourself, or a community copy whose files you edited, is never overwritten. Its card reports that a newer version is available; to replace it, inspect or back up the files through **View details > Open Folder**, delete the card, then install the skill from Community. A checksum mismatch or changed catalog requires Refresh; it never bypasses verification.

### Removing skills

Every installed card has a red trash button on the right. Deletion requires confirmation and uses the normal protected removal path. Changed registrations are preserved and the card reports incomplete removal so it can be retried. Built-in skills have no deletion action.
