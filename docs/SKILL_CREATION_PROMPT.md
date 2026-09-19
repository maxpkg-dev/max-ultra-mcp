Create a reusable, instruction-only Max Ultra MCP skill from the last successfully completed and verified workflow in this conversation.

If an installed Skill Creator capability or skill (for example, skill-creator) is available, read and use it for authoring and validation. Combine its guidance with the portable Max Ultra MCP import contract below; that contract determines the deliverable files. If Skill Creator is unavailable, follow the explicit format and validation steps below directly. Do not invent a tool, require installation, or install a capability for this request. Run a provided validator only when available and permitted, and report which checks actually ran.

Use the conversation already available to you. Do not collect other chats, repeat scene operations, install anything, or import the skill automatically. If the completed workflow or its successful outcome is unclear, ask one focused question before creating files. I may add an optional name or scope after this request.

Extract the proven approach, including my corrections. Do not summarize the conversation or turn failed attempts, untested ideas, incidental preferences, or a single example into universal rules. Preserve necessary constraints and parameterize example names, paths, dimensions, renderer choices, and output destinations. Distinguish required inputs from reasonable defaults. Remove secrets, customer information, personal paths, and unrelated conversation history.

Produce a portable folder with SKILL.md at its root, optionally packaged as one standard unencrypted ZIP. The ZIP must contain SKILL.md at its root or inside a single enclosing folder. Use UTF-8 and this exact frontmatter shape, with one-line strings:

---
name: short-lowercase-hyphenated-name
description: A concise statement of the specific task and when this skill applies.
---

The body must explain the intended result, inputs, essential workflow, verification, and when to stop or ask for missing information. Keep the user's current request and permissions authoritative. Use only MCP tools whose existence has been verified in the current tool catalog; do not imply that skills add new tools or train a model. When a verified workflow uses an existing script tool, describe the reasoning and checks rather than shipping an executable helper.

Include supporting files only when useful: references/ may contain .md, .txt, .json, or .csv; assets/ may contain .png, .jpg, .jpeg, or .webp. Link them with relative Markdown links inside the folder. No missing references, scripts, executable files, hooks, client configuration, symlinks, nested archives, HTML, SVG, automatic downloads, native shell preprocessing, or @file inclusion. Frontmatter accepts only name and description, with no YAML blocks, collections, tags, or aliases. These are Max Ultra MCP importer limits, not general client limitations.

Keep SKILL.md within 64 KiB, each other text file within 1 MiB, each image within 5 MiB, and the package within 200 files and 50 MiB. Do not include assets containing identifying metadata or customer material without my explicit request.

Create the actual folder in a location you are allowed to write. Verify its structure, metadata, references, and privacy before reporting its exact location. If you cannot create files, say clearly that you are providing text only, give the file tree and each text file's contents, and explain how to save them. Never claim that files were created unless you created them.

Finish with the folder location and this short instruction: In the main Max Ultra MCP panel, click Skills, select Custom, choose Import Folder or Import ZIP, review the preview, and click Add Skill. Add Skill makes it available to Codex, Claude Code, and Antigravity. Creating the folder does not import or enable it. Client refresh or a new conversation may be required.
