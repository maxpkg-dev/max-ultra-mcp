# Antigravity setup

Open **AI Client Setup** in 3ds Max, click the **Antigravity** button. Setup discovers the installed app and automatically adds or updates the `max-ultra-mcp` server. No JSON editing is required.

Antigravity 2.x uses `%USERPROFILE%\.gemini\config\mcp_config.json`. Before changing an existing file, setup creates a timestamped, unique `.bak` beside it, including for an empty file. Missing settings are created. Other servers and top-level settings are preserved. An already correct entry is not rewritten and does not create an extra backup. Older app versions are not configured using the 2.x location.

The installer uses the bundled Node.js runtime's standard `JSON.parse` and `JSON.stringify` APIs to update the settings object. Numeric tokens are preserved with the standard `JSON.rawJSON` API where supported. A validation-only scan rejects duplicate keys; it does not insert text into the file. Before committing, the helper verifies that unrelated settings survive serialization, writes a temporary file, checks that the original has not changed, then atomically replaces it and rereads the intended entry. A failed verification restores the original when no newer edit would be overwritten. Backups remain available if recovery cannot safely complete.

Malformed JSON, conflicting server ownership, duplicate keys, unavailable file access, and concurrent edits produce an error instead of silently overwriting settings. Backups may contain other servers' credentials and must remain private. The generated Max Ultra MCP entry contains only the resolved runtime, STDIO host, selected tool profile, and active bridge port; it adds no credentials.

**Configured** confirms configuration, not a live connection. Use **Test prompt** in Antigravity to verify its tools and Max instance. If tools are unavailable, refresh **Settings > Customizations > Installed MCP Servers** or reopen Antigravity. Setup does not forcibly close clients or 3ds Max. Workspace settings may override the global file. Multiple Max instances require session-specific selection. See the [official MCP guide](https://antigravity.google/docs/mcp).

Discovery checks standard per-user and Program Files app locations. The Skills manager's adapters are separate from MCP connection setup. After uninstalling Max Ultra MCP, remove its saved Antigravity server entry manually.

The Setup button is disabled with **Not found** when the client is unavailable. Use **Refresh status** after installing it. During configuration, **Setting up...** appears and conflicting setup actions are disabled. An **Error** status includes an explanation below the cards. Repeated clicks on **Configured** leave the registration unchanged. Expand **Manual / Other STDIO clients** to inspect or copy the manual values.
