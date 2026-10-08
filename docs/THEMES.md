# Editing interface themes

Each palette is an independent UTF-8 JSON file in `assets/themes`:

- `graphite.json`: Warm Graphite
- `forest.json`: Forest
- `plum.json`: Muted Plum
- `coffee.json`: Coffee
- `max.json`: 3ds Max user colors
- `teal.json`: Deep Teal
- `burgundy.json`: Burgundy

Edit values in `colors`, using `#RRGGBB`. Names describe their purpose:
`window_background`, `field_background`, `text`, `heading_text`,
`active_border`, `scrollbar_thumb`, `scrollbar_hover`, `log_success`,
`log_error`, `donate_background`, and the remaining button/status colors.
All files contain a complete palette; they do not inherit another theme.
SVG button icons use the button text color without modifying their geometry.

Save the file, switch to another theme in Settings, then switch back.
The selected JSON file is read and validated on every switch; all open
windows update immediately. Invalid or missing files are reported in the
journal and leave the current selection and palette unchanged.
Keep `graphite.json` valid: it is the startup default.

The Max palette also supports `$background`, `$windowText`, and other
`colorMan` role references. Its `colorMan` section defines fallback colors
when a role cannot be read. Replace a reference with a hex color to override
it locally. A value such as `{"mix": ["$window", "$windowText", 0.55]}` blends
two colors. `light_colors` overrides log colors when the resolved field
background is light. The script reads Max colors and never changes them.

`bindings.json` maps legacy HTML color literals to named roles. It is a
compatibility resource, not another palette; normal color edits belong in
the theme files. User skill code examples are never recolored.

These files are packaged with the script. Keep a backup of custom edits:
installing an updated MZP can replace the bundled files.
