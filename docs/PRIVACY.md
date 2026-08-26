# Privacy and Data Sanitization

Max Ultra MCP is developed in a public-source repository. Documentation, examples, fixtures, logs, screenshots, generated media, and test output committed to the repository must contain synthetic or anonymized data only.

## Never commit

- Real Windows usernames, profile directories, home directories, or workstation names.
- Personal e-mail addresses, phone numbers, account identifiers, or private organization details.
- API keys, access tokens, installation control tokens, passwords, cookies, authorization headers, private keys, or credential files.
- Public or private network addresses other than documentation-safe loopback values.
- Windows SIDs, hardware identifiers, machine ids, license ids, or cloud resource ids.
- Real customer project names, scene names, asset paths, filenames, client names, floor plans, renders, or production screenshots.
- Raw daemon, MaxScript Listener, renderer, installer, CI, or terminal logs that can expose paths, PIDs, process command lines, environment variables, or usernames.
- Image metadata containing prompts, source paths, account data, GPS, EXIF, XMP, or generation-service identifiers.

## Approved placeholders

Use explicit placeholders that cannot be mistaken for real data:

| Sensitive value | Use instead |
| --- | --- |
| User profile | `<USER_PROFILE>` or `%USERPROFILE%` |
| User name | `<USER>` |
| Project root | `<PROJECT_ROOT>` |
| Installation root | `<INSTALL_ROOT>` |
| Asset directory | `<ASSET_ROOT>` |
| Output directory | `<OUTPUT_DIR>` |
| Token or secret | `<REDACTED_TOKEN>` |
| Instance id | `mock-max-2027-1` |
| Process id | a documented synthetic value such as `22027` |
| Host | `127.0.0.1` |
| Customer or scene | `ExampleProject` / `ExampleScene.max` |

Windows environment variables such as `%LOCALAPPDATA%` are preferred over expanded user-specific paths.

## Examples and fixtures

- Build fixtures from synthetic geometry and invented asset names.
- Do not copy a real customer scene and merely rename it.
- Remove authoring and generation metadata from images before committing them.
- Review visible text inside screenshots and renders, not only filenames and metadata.
- Use mock process ids, versions, instance ids, and timestamps in deterministic tests.
- Keep expected output free of local absolute paths unless a placeholder is the subject of the test.

## Runtime diagnostics

Runtime logs may contain operational paths and process ids because local diagnostics require them. They must remain local and must not be copied into documentation, issues, fixtures, or commits without sanitization.

AI onboarding status files may contain local executable and repository paths. They stay in the per-user Max Ultra MCP state directory, must never include CLI output or client configuration contents, and must be sanitized before sharing.

When returning diagnostics through MCP:

- Bound output length.
- Avoid environment dumps.
- Never return the installation control token.
- Redact authorization fields and known credential patterns.
- Prefer filenames relative to an explicitly approved root when practical.

## Review checklist

Before a commit or release:

1. Search text files for profile paths, home paths, e-mail addresses, secrets, tokens, external IPs, SIDs, and long unexplained identifiers.
2. Search for the current workstation username and absolute repository path.
3. Inspect image files for EXIF, XMP, PNG text chunks, and visible sensitive text.
4. Inspect staged diffs and newly added logs, JSON, screenshots, archives, and generated assets manually.
5. Confirm that examples use the placeholders above.

If a real credential is discovered, revoke or rotate it first. Removing it from the latest file or commit is not sufficient. Coordinate any history rewrite with the repository owner; never rewrite shared history automatically.

## Intentional public data

The product name, `3dground.net`, public documentation links, copyright attribution, and contributor attribution intentionally identify the project and are not anonymized unless the repository owner requests a branding change.
