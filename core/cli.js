/*
 * Provides a read-only command-line companion for Max Ultra MCP discovery and diagnostics.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { BridgeControlClient } = require("./bridge-control-client");
const { version: PACKAGE_VERSION } = require("./package.json");

const PROJECT_ROOT = path.resolve(__dirname, "..");
const SKILLS_ROOT = path.join(PROJECT_ROOT, "skills");
const SERVER_PATH = path.join(__dirname, "server.js");
const SERVER_NAME = "max-ultra-mcp";
const CLIENT_PROBE_TIMEOUT_MS = 5000;
const CONTROL_TIMEOUT_MS = 30000;

function toPortablePath(filePath) {
  return filePath.split(path.sep).join("/");
}

function readVersionChannel() {
  try {
    const versionText = fs.readFileSync(path.join(PROJECT_ROOT, "version.ini"), "utf8");
    return /(?:^|\r?\n)Channel=([^\r\n]+)/i.exec(versionText)?.[1]?.trim() || "unknown";
  } catch {
    return "unknown";
  }
}

function parseFrontMatter(markdownText, skillFile) {
  const lines = markdownText.replace(/^\uFEFF/, "").split(/\r?\n/);
  if (lines[0]?.trim() !== "---") throw new Error(`Skill frontmatter is missing: ${skillFile}`);
  const closingIndex = lines.findIndex((line, index) => index > 0 && line.trim() === "---");
  if (closingIndex < 0) throw new Error(`Skill frontmatter is incomplete: ${skillFile}`);
  const fields = {};
  for (const line of lines.slice(1, closingIndex)) {
    const separatorIndex = line.indexOf(":");
    if (separatorIndex < 1) continue;
    fields[line.slice(0, separatorIndex).trim()] = line.slice(separatorIndex + 1).trim();
  }
  if (!fields.name || !fields.description) throw new Error(`Skill name or description is missing: ${skillFile}`);
  return { name: fields.name, description: fields.description };
}

function markdownFilesBelow(directoryPath) {
  const files = [];
  for (const directoryEntry of fs.readdirSync(directoryPath, { withFileTypes: true })) {
    const entryPath = path.join(directoryPath, directoryEntry.name);
    if (directoryEntry.isDirectory()) files.push(...markdownFilesBelow(entryPath));
    else if (directoryEntry.isFile() && path.extname(directoryEntry.name).toLowerCase() === ".md") files.push(entryPath);
  }
  return files.sort((left, right) => left.localeCompare(right));
}

function toolReferencesForSkill(skillDirectory) {
  const toolNames = new Set();
  const markdownFiles = markdownFilesBelow(skillDirectory);
  for (const markdownFile of markdownFiles) {
    const markdownText = fs.readFileSync(markdownFile, "utf8");
    for (const match of markdownText.matchAll(/\bmax_[a-z][a-z0-9_]*\b/g)) toolNames.add(match[0]);
  }
  return {
    markdownFiles: markdownFiles.map((markdownFile) => toPortablePath(path.relative(PROJECT_ROOT, markdownFile))),
    toolReferences: [...toolNames].sort((left, right) => left.localeCompare(right)),
  };
}

function discoverSkills() {
  if (!fs.existsSync(SKILLS_ROOT)) return [];
  const skills = [];
  for (const directoryEntry of fs.readdirSync(SKILLS_ROOT, { withFileTypes: true })) {
    if (!directoryEntry.isDirectory()) continue;
    const skillDirectory = path.join(SKILLS_ROOT, directoryEntry.name);
    const skillFile = path.join(skillDirectory, "SKILL.md");
    if (!fs.existsSync(skillFile)) continue;
    const markdownText = fs.readFileSync(skillFile, "utf8");
    const frontMatter = parseFrontMatter(markdownText, skillFile);
    const references = toolReferencesForSkill(skillDirectory);
    skills.push({
      name: frontMatter.name,
      description: frontMatter.description,
      path: skillFile,
      relativePath: toPortablePath(path.relative(PROJECT_ROOT, skillFile)),
      markdownFiles: references.markdownFiles,
      toolReferences: references.toolReferences,
    });
  }
  return skills.sort((left, right) => left.name.localeCompare(right.name));
}

function parseArguments(rawArguments) {
  const options = { command: "help", json: false, check: false, instanceId: "", profile: "archviz", timeoutMs: CONTROL_TIMEOUT_MS };
  const argumentsToRead = [...rawArguments];
  if (argumentsToRead.length && !argumentsToRead[0].startsWith("-")) options.command = argumentsToRead.shift().toLowerCase();
  while (argumentsToRead.length) {
    const argument = argumentsToRead.shift();
    if (argument === "--json") options.json = true;
    else if (argument === "--check") options.check = true;
    else if (argument === "--version" || argument === "-v") options.command = "version";
    else if (argument === "--help" || argument === "-h") options.command = "help";
    else if (argument === "--instance") {
      options.instanceId = String(argumentsToRead.shift() || "").trim();
      if (!options.instanceId) throw new Error("--instance requires a connected instance id");
    } else if (argument.startsWith("--instance=")) {
      options.instanceId = argument.slice("--instance=".length).trim();
      if (!options.instanceId) throw new Error("--instance requires a connected instance id");
    } else if (argument === "--profile") {
      options.profile = String(argumentsToRead.shift() || "").trim().toLowerCase();
    } else if (argument.startsWith("--profile=")) {
      options.profile = argument.slice("--profile=".length).trim().toLowerCase();
    } else if (argument === "--timeout") {
      options.timeoutMs = Number(argumentsToRead.shift());
    } else if (argument.startsWith("--timeout=")) {
      options.timeoutMs = Number(argument.slice("--timeout=".length));
    } else {
      throw new Error(`Unknown option '${argument}'`);
    }
  }
  if (!Number.isFinite(options.timeoutMs) || options.timeoutMs < 1000 || options.timeoutMs > 600000) {
    throw new Error("--timeout must be between 1000 and 600000 milliseconds");
  }
  if (!new Set(["core", "archviz", "full"]).has(options.profile)) throw new Error("--profile must be core, archviz, or full");
  return options;
}

function existingClientCommandPaths(commandName) {
  const candidatePaths = [];
  const lookupCommand = process.platform === "win32" ? "where.exe" : "which";
  const lookupResult = spawnSync(lookupCommand, [commandName], {
    encoding: "utf8",
    windowsHide: true,
    timeout: CLIENT_PROBE_TIMEOUT_MS,
    maxBuffer: 1024 * 1024,
  });
  if (lookupResult.status === 0) {
    for (const outputLine of String(lookupResult.stdout || "").split(/\r?\n/)) {
      if (outputLine.trim()) candidatePaths.push(outputLine.trim());
    }
  }
  if (process.platform === "win32" && commandName === "codex" && process.env.LOCALAPPDATA) {
    const codexBinRoot = path.join(process.env.LOCALAPPDATA, "OpenAI", "Codex", "bin");
    if (fs.existsSync(codexBinRoot)) {
      const versionDirectories = fs.readdirSync(codexBinRoot, { withFileTypes: true })
        .filter((entry) => entry.isDirectory())
        .map((entry) => path.join(codexBinRoot, entry.name))
        .sort((left, right) => fs.statSync(right).mtimeMs - fs.statSync(left).mtimeMs);
      for (const versionDirectory of versionDirectories) candidatePaths.push(path.join(versionDirectory, "codex.exe"));
    }
  }
  if (process.platform === "win32" && commandName === "claude") {
    if (process.env.USERPROFILE) candidatePaths.push(path.join(process.env.USERPROFILE, ".local", "bin", "claude.exe"));
    if (process.env.APPDATA) candidatePaths.push(path.join(process.env.APPDATA, "npm", "claude.cmd"));
  }
  return [...new Set(candidatePaths.map((candidatePath) => path.resolve(candidatePath)))]
    .filter((candidatePath) => fs.existsSync(candidatePath));
}

function runClientCommand(commandPath, commandArguments) {
  const executionOptions = {
    encoding: "utf8",
    windowsHide: true,
    timeout: CLIENT_PROBE_TIMEOUT_MS,
    maxBuffer: 1024 * 1024,
  };
  if (process.platform === "win32" && [".bat", ".cmd"].includes(path.extname(commandPath).toLowerCase())) {
    return spawnSync(process.env.ComSpec || "cmd.exe", ["/d", "/s", "/c", "call", commandPath, ...commandArguments], executionOptions);
  }
  return spawnSync(commandPath, commandArguments, executionOptions);
}

function probeClientRegistration(commandName) {
  if (process.env.MAX_ULTRA_MCP_CLI_SKIP_CLIENT_PROBES === "1") {
    return { client: commandName, available: null, configured: null, state: "skipped" };
  }
  const commandPath = existingClientCommandPaths(commandName)[0];
  if (!commandPath) return { client: commandName, available: false, configured: false, state: "unavailable" };
  const getResult = runClientCommand(commandPath, ["mcp", "get", SERVER_NAME]);
  if (getResult.status === 0) return { client: commandName, available: true, configured: true, state: "configured" };
  const listResult = runClientCommand(commandPath, ["mcp", "list"]);
  const combinedOutput = `${listResult.stdout || ""}\n${listResult.stderr || ""}`;
  const configured = listResult.status === 0 && new RegExp(`(?:^|\\s)${SERVER_NAME}(?:\\s|$)`, "im").test(combinedOutput);
  return { client: commandName, available: true, configured, state: configured ? "configured" : "not_configured" };
}

function recommendedNodePath() {
  const packageNodePath = path.join(PROJECT_ROOT, "runtime", "win-x64", "node.exe");
  return fs.existsSync(packageNodePath) ? packageNodePath : process.execPath;
}

function setupInstructions(options) {
  const nodePath = recommendedNodePath();
  const environmentArgument = `MAX_ULTRA_MCP_TOOL_PROFILE=${options.profile}`;
  return {
    ok: true,
    readOnly: true,
    note: "These commands use the official client CLIs. The Max Ultra MCP CLI only prints them; it never changes client configuration.",
    codex: {
      displayName: "ChatGPT Desktop / Codex",
      command: ["codex", "mcp", "add", SERVER_NAME, "--env", environmentArgument, "--", nodePath, SERVER_PATH, "--stdio"],
      verify: ["codex", "mcp", "get", SERVER_NAME],
    },
    claudeCode: {
      displayName: "Claude Code",
      command: ["claude", "mcp", "add", SERVER_NAME, "--scope", "user", "--env", environmentArgument, "--", nodePath, SERVER_PATH, "--stdio"],
      verify: ["claude", "mcp", "get", SERVER_NAME],
    },
    afterInstall: "Restart or reconnect the configured AI client, then run status and health.",
  };
}

async function withControlClient(options, callback) {
  const controlClient = new BridgeControlClient({ timeoutMs: options.timeoutMs });
  try {
    await controlClient.connect();
    return await callback(controlClient);
  } finally {
    controlClient.close();
  }
}

function targetArguments(options) {
  return options.instanceId ? { instance_id: options.instanceId } : {};
}

async function readStatus(options) {
  const status = {
    ok: true,
    readOnly: true,
    product: "3DGROUND - Max Ultra MCP",
    version: PACKAGE_VERSION,
    channel: readVersionChannel(),
    mcp: {
      name: SERVER_NAME,
      transport: "stdio",
      entrypoint: SERVER_PATH,
      arguments: ["--stdio"],
      clients: [probeClientRegistration("codex"), probeClientRegistration("claude")],
      setup: setupInstructions(options),
    },
    skills: { root: SKILLS_ROOT, count: discoverSkills().length },
    connection: { connected: false, daemon: null, instances: null, error: null },
  };
  try {
    const connection = await withControlClient(options, async (controlClient) => ({
      daemon: await controlClient.probe(),
      instances: await controlClient.listInstances(),
    }));
    status.connection = { connected: true, ...connection, error: null };
  } catch (error) {
    status.ok = false;
    status.connection.error = error.message;
  }
  return status;
}

async function readTool(command, options) {
  const toolName = command === "health" ? "max_health" : "max_capabilities";
  return withControlClient(options, (controlClient) => controlClient.callTool(toolName, targetArguments(options)));
}

async function readSkills(options) {
  const result = { ok: true, readOnly: true, root: SKILLS_ROOT, count: 0, skills: discoverSkills(), capabilityCheck: null };
  result.count = result.skills.length;
  if (!options.check) return result;
  const capabilities = await readTool("capabilities", options);
  const availableTools = new Set(Array.isArray(capabilities.tools) ? capabilities.tools : []);
  for (const skill of result.skills) {
    const available = skill.toolReferences.filter((toolName) => availableTools.has(toolName));
    const unavailable = skill.toolReferences.filter((toolName) => !availableTools.has(toolName));
    skill.capabilities = { referenced: skill.toolReferences.length, available: available.length, unavailable };
  }
  result.capabilityCheck = {
    connected: true,
    instanceId: capabilities.instance?.instanceId || options.instanceId || null,
    maxVersion: capabilities.instance?.maxVersion || null,
    activeRenderer: capabilities.activeRenderer || null,
    availableToolCount: availableTools.size,
    note: "Tool references are discovered from each skill folder. Workflow execution remains the responsibility of the agent and MCP.",
  };
  return result;
}

function helpText() {
  return [
    `3DGROUND - Max Ultra MCP CLI ${PACKAGE_VERSION}`,
    "",
    "Read-only discovery and diagnostics for the existing Max Ultra MCP daemon.",
    "",
    "Usage:",
    "  diagnostics\Max Ultra MCP Diagnostics.bat <command> [options]",
    "  node core/cli.js <command> [options]",
    "",
    "Commands:",
    "  status         Check official-client MCP registration, daemon connection, Max instances, and skill count.",
    "  setup          Print official Codex and Claude Code MCP installation and verification commands; do not run them.",
    "  skills         List every packaged skill with its description, SKILL.md path, and referenced MCP tools.",
    "  health         Run the read-only max_health call against the only or explicitly selected Max instance.",
    "  capabilities   Show concise live Max, renderer, unit, profile, UI, and tool capability information.",
    "  help           Show this help.",
    "  version        Show the product version.",
    "",
    "Options:",
    "  --json                 Emit machine-readable JSON.",
    "  --check                With skills, compare discovered tool references with live max_capabilities.",
    "  --profile <name>       Profile for setup instructions: core, archviz, or full (default archviz).",
    "  --instance <id>        Target one connected Max when several instances are available.",
    "  --timeout <ms>         Control-call timeout from 1000 to 600000 (default 30000).",
    "  --help, -h             Show help.",
    "  --version, -v          Show the product version.",
    "",
    "The CLI never installs skills, changes client configuration, executes MaxScript, mutates a scene, or saves a file.",
    "Skills guide the agent; Max Ultra MCP tools perform the reviewed workflow.",
  ].join("\n");
}

function writeJson(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function quoteCommandArgument(argument) {
  const stringValue = String(argument);
  return /[\s"]/u.test(stringValue) ? `"${stringValue.replaceAll('"', '\\"')}"` : stringValue;
}

function writeSetup(setup) {
  process.stdout.write(`${setup.note}\n\n`);
  for (const client of [setup.codex, setup.claudeCode]) {
    process.stdout.write(`${client.displayName}\n`);
    process.stdout.write(`  Install: ${client.command.map(quoteCommandArgument).join(" ")}\n`);
    process.stdout.write(`  Verify:  ${client.verify.map(quoteCommandArgument).join(" ")}\n\n`);
  }
  process.stdout.write(`${setup.afterInstall}\n`);
}

function writeStatus(status) {
  process.stdout.write(`${status.product} ${status.version} (${status.channel})\n`);
  process.stdout.write(`MCP entrypoint: ${status.mcp.entrypoint} --stdio\n`);
  for (const client of status.mcp.clients) process.stdout.write(`${client.client}: ${client.state}\n`);
  process.stdout.write(`Skills: ${status.skills.count} below ${status.skills.root}\n`);
  if (!status.connection.connected) {
    process.stdout.write(`Daemon: unavailable (${status.connection.error})\n`);
    return;
  }
  process.stdout.write(`Daemon: connected, PID ${status.connection.daemon.pid}, Max instances ${status.connection.instances.count}\n`);
  for (const instance of status.connection.instances.instances || []) {
    process.stdout.write(`  ${instance.instanceId}: 3ds Max ${instance.maxVersion}, healthy=${instance.healthy}\n`);
  }
}

function writeSkills(result) {
  process.stdout.write(`Packaged skills: ${result.count}\n`);
  for (const skill of result.skills) {
    process.stdout.write(`\n${skill.name}\n`);
    process.stdout.write(`  ${skill.description}\n`);
    process.stdout.write(`  Path: ${skill.path}\n`);
    process.stdout.write(`  MCP tool references: ${skill.toolReferences.length}\n`);
    if (skill.capabilities) {
      process.stdout.write(`  Live availability: ${skill.capabilities.available}/${skill.capabilities.referenced}\n`);
      if (skill.capabilities.unavailable.length) process.stdout.write(`  Not advertised: ${skill.capabilities.unavailable.join(", ")}\n`);
    }
  }
  if (result.capabilityCheck) process.stdout.write(`\nChecked against ${result.capabilityCheck.instanceId} (${result.capabilityCheck.availableToolCount} advertised tools).\n`);
}

function writeHealth(health) {
  const instance = health.instance || {};
  const response = health.health || {};
  process.stdout.write(`3ds Max ${instance.maxVersion || "unknown"} (${instance.instanceId || "unknown"})\n`);
  process.stdout.write(`Healthy: ${instance.healthy !== false && response.ok !== false}; main thread: ${response.mainThread === true}\n`);
  if (response.scene) process.stdout.write(`Scene objects: ${response.scene.objectCount}; selected: ${response.scene.selectionCount}; frame: ${response.scene.frame}\n`);
}

function writeCapabilities(capabilities) {
  const instance = capabilities.instance || {};
  process.stdout.write(`3ds Max ${instance.maxVersion || "unknown"} (${instance.instanceId || "unknown"})\n`);
  process.stdout.write(`Renderer: ${capabilities.activeRenderer || "Unknown"} (${capabilities.rendererAdapter || "unknown"})\n`);
  if (capabilities.units) process.stdout.write(`Units: ${capabilities.units.systemType}, display ${capabilities.units.displayType}\n`);
  process.stdout.write(`Profiles: ${(capabilities.profiles || []).join(", ")}\n`);
  process.stdout.write(`Advertised tools: ${(capabilities.tools || []).length}; process-scoped UI Automation: ${capabilities.uiAutomation?.processScoped === true}\n`);
}

async function run(rawArguments = process.argv.slice(2)) {
  const options = parseArguments(rawArguments);
  if (options.command === "help") {
    process.stdout.write(`${helpText()}\n`);
    return 0;
  }
  if (options.command === "version") {
    process.stdout.write(`${PACKAGE_VERSION}\n`);
    return 0;
  }
  if (options.command === "status") {
    const status = await readStatus(options);
    if (options.json) writeJson(status); else writeStatus(status);
    return status.ok ? 0 : 1;
  }
  if (options.command === "setup") {
    const setup = setupInstructions(options);
    if (options.json) writeJson(setup); else writeSetup(setup);
    return 0;
  }
  if (options.command === "skills") {
    const skills = await readSkills(options);
    if (options.json) writeJson(skills); else writeSkills(skills);
    return 0;
  }
  if (options.command === "health" || options.command === "capabilities") {
    const response = await readTool(options.command, options);
    if (options.json) writeJson({ ok: true, readOnly: true, command: options.command, data: response });
    else if (options.command === "health") writeHealth(response);
    else writeCapabilities(response);
    return 0;
  }
  throw new Error(`Unknown command '${options.command}'. Run 'help' for available commands.`);
}

if (require.main === module) {
  run().then((exitCode) => {
    process.exitCode = exitCode;
  }).catch((error) => {
    const wantsJson = process.argv.includes("--json");
    if (wantsJson) writeJson({ ok: false, readOnly: true, error: error.message });
    else process.stderr.write(`Max Ultra MCP CLI error: ${error.message}\n`);
    process.exitCode = 1;
  });
}

module.exports = { discoverSkills, helpText, parseArguments, readSkills, readStatus, run, setupInstructions };
