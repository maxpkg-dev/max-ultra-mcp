# Third-party notices

The following source-controlled MaxPkg release-tooling files are synchronized from [maxpkg-dev/max-dev-tool](https://github.com/maxpkg-dev/max-dev-tool) revision `93ceb0e018b44ca53546cf2c274b196160495699`:

- `maxpkg-packager.ms`
- `_install.ms`
- `_uninstall.ms`

They are kept in the project root because that is the layout required by MaxPkg Packager. `scripts/sync-maxpkg-tooling.ps1` verifies their pinned raw-file SHA-256 values before updating them. Preserve the original file headers and upstream notices when refreshing these files.

Release artifacts also bundle the official Node.js runtime and its license file. `scripts/prepare-portable-node.ps1` downloads the pinned official archive from `nodejs.org`, verifies its published SHA-256 checksum, and places `NODE-LICENSE.txt` beside the executable.
