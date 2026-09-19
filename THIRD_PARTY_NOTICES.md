# Third-party notices

The AI Client Setup buttons display genuine client artwork solely to identify compatible products. OpenAI/Codex, Claude/Anthropic, and Google Antigravity names and logos remain the property of their respective owners; inclusion does not imply affiliation or endorsement and does not place those marks under this project's license. The packaged 48 px PNGs preserve the original colors and proportions, with transparent padding and no embedded metadata:

- `assets/client-logos/codex.png`: the unplated application icon from the official OpenAI Codex Windows package, version 26.915.3509.0, `assets/Square44x44Logo.targetsize-256_altform-unplated.png`. See [OpenAI brand guidelines](https://openai.com/brand/).
- `assets/client-logos/claude.png`: the icon linked by the official [Claude website](https://claude.com), [source PNG](https://assets.claude.com/95a868946ac8a31e5ff832e2899f294aa368b836.png?w=128&h=128).
- `assets/client-logos/antigravity.png`: the icon linked by the official [Google Antigravity website](https://antigravity.google), [source PNG](https://antigravity.google/assets/image/antigravity-logo.png).

Architectural workflow contributions supplied by Anastasiia Reznichenko are acknowledged in the packaged skill's [attribution and source terms](skills/max-ultra-small-house-detailing/ATTRIBUTION.md). That notice records the source collection's unspecified licensing status; it does not grant a license to the original materials. Original lesson PDFs, photographs, screenshots, and project records are not bundled.

The following source-controlled MaxPkg release-tooling files are synchronized from [maxpkg-dev/max-dev-tool](https://github.com/maxpkg-dev/max-dev-tool) revision `4412adcf06b1f62b27fc42fc7a252a4a96b95402`:

- `maxpkg-packager.ms`
- `_install.ms`
- `_uninstall.ms`

They are kept in the project root because that is the layout required by MaxPkg Packager. `scripts/sync-maxpkg-tooling.ps1` verifies their pinned raw-file SHA-256 values before updating them. Preserve the original file headers and upstream notices when refreshing these files.

Release artifacts also bundle the official Node.js runtime and its license file. `scripts/prepare-portable-node.ps1` downloads the pinned official archive from `nodejs.org`, verifies its published SHA-256 checksum, and places `NODE-LICENSE.txt` beside the executable.

The UI includes PNG renditions of the `heart`, `panel-top-close`, `plug-zap`, `power`, `refresh-cw`, and `settings` icons from [Lucide](https://github.com/lucide-icons/lucide). Lucide is distributed under the ISC License, Copyright (c) 2020 Lucide Contributors. The ready-to-use transparent PNG files use white artwork and the official SVG geometry.

The `skills.png` book outline is original project artwork, styled to match the existing white line icons.

The Skills preview Back control embeds the official Lucide `arrow-left` SVG geometry from https://github.com/lucide-icons/lucide/blob/main/icons/arrow-left.svg. Its ISC license and the MIT notice for Feather-derived icons are included in `assets/icons/LUCIDE-LICENSE.txt`.
