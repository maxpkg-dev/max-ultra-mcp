# Create and import a skill

Save a successful workflow so your AI assistant can reuse it.

## Create

1. Complete a task with your AI assistant and check the result.
2. In Max Ultra MCP, open **Skills**, select **Custom**, and click **Copy Skill Creation Prompt**.
3. Paste the prompt into the **same AI conversation** where you completed the task.
4. Ask the assistant to save the skill as a folder or ZIP containing **SKILL.md**. Keep any required references and images with it.

## Import and use

1. Choose **Import Folder** or **Import ZIP**.
2. Select the folder or ZIP and review the preview.
3. Click **Add Skill**. It becomes available to Codex, Claude Code, and Antigravity.
4. Ask your assistant to use the skill for a matching task. If it is not found, refresh the client or start a new conversation.

A ZIP must contain exactly one skill: **SKILL.md** at the archive root or inside one enclosing folder. The filename must be exactly **SKILL.md**. Use a standard, unencrypted ZIP.

Import sends no data. Your AI client may send instructions and images to its model provider when using the skill. Review content before enabling it.

## Browse and remove

Click a reference to read it. **Back** returns to the previous document. Built-in skills are read-only.

To remove a custom skill, select it and click **Delete**. This removes the imported copy and its client entries; your original folder or ZIP is kept. To update a skill, edit the original, delete the imported copy, and import again.

## If import fails

- Include **SKILL.md** with a name, description, and instructions. Ask the assistant to follow the copied creation prompt.
- Include every referenced file. Supporting text belongs in **references/**; images belong in **assets/**.
- Supported attachments: MD, TXT, JSON, CSV, PNG, JPG, JPEG, and WebP. Scripts, nested archives, links to other folders, and client configuration files are not accepted.
- Limits: 200 files and 50 MiB total; SKILL.md up to 64 KiB, other text up to 1 MiB each, images up to 5 MiB each. ZIP files may be up to 54 MiB; the expanded contents must meet the same limits.
- If several skills are in one ZIP, put each skill in its own ZIP and import them separately.
