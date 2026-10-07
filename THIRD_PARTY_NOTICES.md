# Third-party notices

The AI Client Setup buttons display existing vector client artwork solely to identify compatible products. OpenAI/Codex, Claude/Anthropic, and Google Antigravity names and logos remain the property of their respective owners; inclusion does not imply affiliation or endorsement and does not place those marks under this project's license. The Qt interface packages SVG assets:

- `assets/client-logos/codex.svg`: the OpenAI knot (`static/library/openai_dark.svg`) from [SVGL](https://github.com/pheralb/svgl/tree/f9b726cee1d1f3c697a18c880185e89d9a55bb70), revision `f9b726cee1d1f3c697a18c880185e89d9a55bb70`. See [OpenAI brand guidelines](https://openai.com/brand/).
- `assets/client-logos/claude.svg`: `static/library/claude-ai-icon.svg` from the same SVGL revision. The collection's MIT license is included in `assets/client-logos/SVGL-LICENSE.txt`.
- `assets/client-logos/antigravity.svg`: the [official white vector mark](https://antigravity.google/assets/image/brand/antigravity-icon__white.svg), supplied on the [Google Antigravity press page](https://antigravity.google/press). This official variant avoids the masks and blur filters in the full-color mark that Qt 5 cannot render correctly.

The three client marks retain their source path geometry. Their SVG view boxes center the original artwork with equal padding (80% of the icon canvas along the longest visible dimension). Claude's fill is changed to white to match the other marks.

Architectural workflow contributions supplied by Anastasiia Reznichenko are acknowledged in the packaged skill's [attribution and source terms](skills/max-ultra-small-house-detailing/ATTRIBUTION.md). That notice records the source collection's unspecified licensing status; it does not grant a license to the original materials. Original lesson PDFs, photographs, screenshots, and project records are not bundled.

The following source-controlled MaxPkg release-tooling files are synchronized from [maxpkg-dev/max-dev-tool](https://github.com/maxpkg-dev/max-dev-tool) revision `4412adcf06b1f62b27fc42fc7a252a4a96b95402`:

- `maxpkg-packager.ms`
- `_install.ms`
- `_uninstall.ms`

They are kept in the project root because that is the layout required by MaxPkg Packager. `scripts/sync-maxpkg-tooling.ps1` verifies their pinned raw-file SHA-256 values before updating them. Preserve the original file headers and upstream notices when refreshing these files.

Release artifacts also bundle the official Node.js runtime and its license file. `scripts/prepare-portable-node.ps1` downloads the pinned official archive from `nodejs.org`, verifies its published SHA-256 checksum, and places `NODE-LICENSE.txt` beside the executable.

All Qt action icons are original SVG files from [Lucide 0.468.0](https://github.com/lucide-icons/lucide/tree/0.468.0/icons): `x` (close), `copy`, `download`, `maximize` (expand), `heart`, `panel-top-close`, `plug-zap` (reconnect), `power`, `refresh-cw`, `search`, `settings-2` (settings), and `book-open` (Skills). Only `currentColor` is replaced with the interface foreground color `#e8e3da`; no geometry is redrawn. This version preserves path syntax understood by Qt 5. Lucide is distributed under the ISC License, Copyright (c) 2020 Lucide Contributors. Its license is included in `assets/icons/LUCIDE-LICENSE.txt`. Legacy PNG assets are not included in the Qt package.

The Skills preview Back control embeds the official Lucide `arrow-left` SVG geometry from https://github.com/lucide-icons/lucide/blob/main/icons/arrow-left.svg. Its ISC license and the MIT notice for Feather-derived icons are included in `assets/icons/LUCIDE-LICENSE.txt`.

Skills window actions also use the original Lucide 0.468.0 `arrow-left`, `folder-open`, `file-archive`, `trash-2`, `send`, `book-open`, and `globe` SVGs. Only the foreground color is substituted.
`assets/icons/check.svg` uses the original Lucide 0.468.0 `check` geometry for checkbox indicators, with only the foreground color substituted.
