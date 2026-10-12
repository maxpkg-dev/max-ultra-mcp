# Skill package metadata

Max Ultra MCP 1.5.0 accepts an optional UTF-8 `skill.json` beside `SKILL.md` at the skill root. A ZIP may contain this root directly or inside one enclosing folder. New skill packages should include this file so people can inspect attribution and version without reading the instructions.

```json
{
  "schemaVersion": 1,
  "title": "Architectural Render Review",
  "description": "Review composition, lighting and presentation of architectural renders.",
  "author": "Example Author",
  "version": "1.0.0",
  "source": "Community Skills",
  "website": "https://example.com/skills",
  "email": "author@example.com"
}
```

Only these eight keys are accepted. `schemaVersion` is required and must be the number `1`. The other keys are optional, but a supplied value must be a nonempty single-line string without control characters. Limits are 160 characters for `title`, 1024 for `description`, 256 for `author`, 64 for `version`, 160 for `source`, 2048 for `website`, and 254 for `email`. Version must contain three nonnegative decimal integers (`MAJOR.MINOR.PATCH`), with no leading zeroes, prefix, prerelease or build suffix. The complete file must not exceed 8192 bytes. Objects, arrays, null values, unknown fields and unsupported schema versions are rejected before installation. In particular, `author` is a string, not an object.

`website` must be an absolute HTTPS URL with a hostname, no whitespace, backslashes or credentials. `email` must be one ASCII address with a local part of at most 64 characters and a dotted domain with valid labels; display names, lists and header/query injection are rejected. Contacts appear in About only when supplied. Clicking opens the website or a mail draft; importing and opening About never navigates or sends mail. Do not invent contact details.

`title` and `description` are display metadata for the Skills list and About dialog. The frontmatter `name` remains the skill's stable machine name; the frontmatter `description` remains its AI discovery description. The instruction body stays in `SKILL.md`. Import does not execute or interpret metadata as instructions. About shows `source` as a publisher-declared label, not a verified download origin or trust certification. Built-in/Custom remains a separate Type, independent of this label. Missing source falls back to that known classification. About also displays installation status.

Without `skill.json`, existing folders, ZIPs and registry records continue to work. Display title and description fall back to the frontmatter name and description. Explicit manifest author takes precedence over the optional frontmatter author. Missing author or version displays `Not specified`; the application never guesses from prose, filenames, machine IDs or a content hash.

All package files, including `skill.json`, contribute to the content revision hash. Metadata is copied into the managed package and persisted in the registry on import. Source folders and archives are not modified. Old installed copies do not acquire missing metadata automatically: prepare a new source version, delete the imported copy, and import it again. Version is descriptive metadata, not an automatic update mechanism.

For catalog exports, construct this file from explicitly supplied public metadata: for example, copy a validated author object's `name` into the string `author`. Do not copy catalog `metadata.json` wholesale. Review decisions, rights, provenance, profile objects and private moderation fields are not part of this schema. The importer does not read an external catalog database.

Adding metadata changes ZIP bytes and the revision/checksum. Publish a new skill version and new archive; do not replace a previously published ZIP in place. Older Max Ultra MCP importers that reject extra root files require an upgrade before importing the new format. Legacy ZIPs without this file remain supported by the new importer.

Bundled skill manifests are maintained explicitly with their source and mirrored plugin copies. Their initial metadata version is 1.5.0; later changes to a bundled workflow's published package should update its manifest version deliberately.
