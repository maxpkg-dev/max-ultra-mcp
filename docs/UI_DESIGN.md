# Qt interface design and implementation

This document describes the current Python/Qt interface of **3DGROUND - Max Ultra MCP**, including the decisions made while replacing the earlier WinForms UI. It is a maintenance guide to implemented behavior, not a claim that every supported Max version has been visually tested.

## Foundation

The interface uses Qt Widgets supplied by 3ds Max: PySide2 for Max 2022-2024 and PySide6 for Max 2025-2027. `python/max_ultra/qt.py` provides the compatibility imports. The script uses Max's existing Qt application; users do not install another Python or Qt runtime.

The familiar layout was retained: AI Client Setup, Refresh and Hide panel at the top; scene context and a flexible journal in the middle; Skills and Settings below; promotions and Donate at the bottom. Refresh reconnects the bridge before checking AI client status, with repeated clicks disabled during the operation. The main close button stops the script. Layouts allocate the remaining height to the journal instead of positioning every control at fixed coordinates.

Background helpers perform I/O. Qt widgets and Max APIs are updated on the main thread. Long blocking Max operations can still pause the embedded interface.

## Responsive main panel

The initial size is 640 x 480, with a minimum of 240 x 180. Width thresholds use **Qt logical pixels**, not physical screen pixels. Fonts use points and SVGs render at the device pixel ratio, so these rules work alongside Windows DPI scaling.

`Panel.update_compact_layout()` in `python/max_ultra/widgets.py` sets these sizes:

| Main window width | Button text | Heading | Context and promotions | Button icon | Minimum button height | Scrollbar width |
| --- | --- | --- | --- | --- | --- | --- |
| Below 300 | 9 pt | 9 pt | 8 pt | 14 px | 24 px, fixed | 7 px |
| 300-519 | 11 pt | 12 pt | 11 pt | 20 px | 32 px | 9 px |
| 520-1250 | 11 pt | 12 pt | 11 pt | 20 px | 32 px | 13 px |
| Above 1250, below 1800 | 14 pt | 16 pt | 14 pt | 26 px | 44 px | 17 px |
| 1800 and above | 18 pt | 20 pt | 18 pt | 34 px | 56 px | 21 px |

Horizontal scrollbar thickness follows the same values. Close buttons remain smaller than action buttons: 14, 18, 24 or 30 px depending on the mode.

Outer margins progress from `(4, 3, 4, 3)` in the smallest mode to `(8, 6, 8, 6)`, `(12, 9, 12, 9)` and `(16, 12, 16, 12)`. Vertical layout spacing is 3, 6, 9 or 12 px. Action-row spacing is 3, 8, 12 or 16 px. Resizing back restores the previous mode rather than accumulating scale changes.

These breakpoints belong to the main panel. Auxiliary dialogs use their own layouts and scrolling; they do not inherit the main panel's size mode.

### Removing button labels when space is limited

- The bottom action row measures its text requirements and switches to icon-only buttons when the row no longer fits.
- Hide panel becomes icon-only below 520 px.
- Donate becomes icon-only below 400 px.
- Below 520 px, the AI button uses the shorter `Setup AI Client` label.
- Refresh is always icon-only.
- The Skills import actions become icon-only, and its help links become icons, below a dialog width of 720 px.

Tooltips and accessible names retain the meaning of icon-only actions. Promotions choose a full or short message using actual font measurements; text is elided only when the short version still does not fit. The smallest mode deliberately uses smaller click targets to leave more room for the log.

## Journal typography and wrapping

`Panel.update_journal_density()` controls the Consolas journal font separately:

1. Width at least 1800: 18 pt, with 8 px of extra row height.
2. Width above 1250: 14 pt, with 6 px extra.
3. Width below 300: 8 pt, with 1 px extra.
4. Width below 420 or height below 300: 9 pt, with 2 px extra.
5. Width below 520 or height below 380: 10 pt, with 3 px extra.
6. Otherwise: 11 pt, with 4 px extra.

Rows use colored timestamps, category badges and message text. System, success, warning, error, information and support messages have separate palette roles. Donation messages use the support color and a clickable Donate link.

At a journal viewport width of 600 logical pixels or more, long messages can occupy multiple lines. Narrow views retain single-line elision. Continuation lines can use the full row width, including the space below the timestamp and badge.

`JournalDelegate` paints and measures rows. `JournalView` measures visible rows rather than every record. `JournalModel` pages the disk-backed history. Automatic scrolling follows new messages only while the user is already at the bottom; reading older entries preserves position and exposes a jump-to-latest action.

## SVG icons

Interface action icons come from **Lucide Icons**, stored in `assets/icons`, with their license included. Use the packaged SVG assets instead of redrawing action icons or substituting font symbols.

`ActionButton` renders SVG glyphs at the required device resolution, tints them using the current text color, and centers them vertically beside the label. Client brand logos are separate vector assets in `assets/client-logos`; they are not Lucide icons. Their geometry is preserved, with consistent monochrome presentation and balanced display sizes.

Copy actions temporarily display `Copied` with a check icon, then restore their original caption and copy icon after two seconds. Enabled buttons and other interactive controls use the pointing-hand cursor.

Button captions use title case, preserving acronyms and lowercase short connecting words such as `to`, `and`, `a` and `the`. Skills and Settings share the same width in the main action row.

Changes to a shared control must apply across all windows. `ThemedComboBox` provides the same rounded dropdown and Lucide chevron with a transparent arrow area for the journal filter and Settings theme picker. `SEARCH_STYLE` keeps the main journal and Skills search fields consistent; checkbox appearance comes from the shared window stylesheet.

## Colors and themes

Colors live in `assets/themes/*.json`, separately from dimensions and layout rules. The available themes are Warm Graphite, Forest, Muted Plum, Coffee, Deep Teal, Burgundy and the user's 3ds Max colors. See [Editing interface themes](THEMES.md).

`themes.py` resolves named color roles into styles and HTML. Selecting a theme reloads its file, persists the choice and updates open script windows immediately. The Max theme reads `colorMan` with fallbacks; it does not change Max's own colors.

Status colors remain meaningful: green for readiness, amber for pending work or issues, red for errors. Donate has a shared style across windows. Hover, focus, disabled and pressed states are explicitly styled rather than left to the default blue system appearance.

## Rounded surfaces, tabs and scrollbars

The visual direction uses subtle rounded corners rather than large pill shapes:

| Surface | Current rounding |
| --- | --- |
| Action buttons | 4 px; 3 px in the smallest mode |
| Settings groups and checkbox indicators | 3 px |
| Main journal field | 8 px, with a rounded widget mask to clip child backgrounds |
| Tab content pane | 5 px |
| Tab upper corners | 4 px |
| Help code-block container | 4 px |
| Normal scrollbar track / thumb | 6 px / 4 px |
| Compact scrollbar track / thumb | 4 px / 2 px |
| Smallest scrollbar track / thumb | 3 px / 2 px |

Not every Qt text field currently has an explicit corner radius. The journal and help code container do; generic text editors retain their shared field styling. Skill metadata intentionally keeps its square HTML frame. Preserve this distinction when describing or extending the design.

`JoinedTabBar` and `TabHeading` draw a continuous active-color baseline across the tab heading, leaving the selected tab visually joined to its content.

Scrollbars use a recessed track, a lighter contrasting thumb and a separate hover color. Pressing uses the text color. Native arrows, page fills and square scroll-area backing containers are cleared or transparent so no blue patterned backing remains behind the rounded track. The relevant roles are `recessed_background`, `scrollbar_thumb`, `scrollbar_hover` and `text`.

## Window chrome, shadows and opacity

The shared `Window` class uses a custom header with `Qt.Tool | Qt.FramelessWindowHint`, parented to Max. Native edge hit testing preserves resizing. There is no global topmost flag.

`qt.enable_window_shadow()` requests Windows DWM non-client rendering and extends a one-pixel frame to obtain a native outer shadow. It runs on show and after DWM composition changes. If the cosmetic request is unavailable, the window still opens normally. Windows controls native outer-corner rounding; the code does not enforce a universal rounded window shape on every Windows version.

Settings is modal and covers other script windows with a full-window translucent veil, without reducing their window opacity. Main-panel opacity is saved and limited to 20-100%. Dragging its slider temporarily hides the veil to preview the real opacity; releasing the mouse restores the veil. The mini-panel remains constrained to monitor work areas, including the taskbar boundary.

Donate is the preferred main-panel focus target at startup and restoration. Status refreshes should not steal focus from editing or journal reading.

## Skills window

`python/max_ultra/skills_window.py` holds one window for built-in, installed and community skills, and one reusable details window. The initial size is 1180 x 820 with a minimum of 360 x 300.

The top row holds the search field with Import Folder, Import ZIPs and an icon-only Refresh beside it. Below it are two filter chips: Community first, then Built-in. Community is always selected when the window opens; the choice is deliberately not saved. A chip shows its counter only once its list is known. The bottom row holds the text links How to Create and Import Skills, Submit Your Skill and Open Online Catalog, with Donate on the right. Below a window width of 720 logical pixels the import actions show icons only, the three links are replaced by icon-only actions with the same names in their tooltips, and the chips use less padding.

The content is one scroll area. The Community filter shows the Installed group first and the Not installed group below it, each with a heading, a counter and a rule; the Built-in filter shows its cards without a heading. Each group has an optional hint line and a `CardGrid`. The grid fits as many equal columns as its width allows with a 280 px minimum card width and a 10 px gap, up to four columns; the default window shows three. Every row is as tall as its tallest card. The vertical scrollbar track is always present so that the column count does not change while cards reflow. A search looks through every group regardless of the selected chip, by title, description and author; each matching group then appears under its heading, and a group without matches is hidden.

A card shows a bold title, a wrapping row of capsule badges (status, author, version), a description limited to three lines with the full text in its tooltip, and an action row. Every card uses the same layout, so a built-in card is as tall as an installed or community card with the same content; its action row keeps the height of a button although it holds only View details. Built-in and installed cards use the card surface; community cards that are not installed use a transparent surface, a dashed outline and muted text, with a green Install action. Installed cards have a red icon-only delete action on the right; built-in cards have none. A badge wider than its card is elided instead of widening the card.

Built-in and installed skills are on the local disk, so the window reads their metadata directly (`read_local_skills()`: the bundled `skills` folders and the user store's `registry.json`) when it is created, when it is opened again and on Refresh. No helper process is involved, and there is no loading state for them. Cards are built per group when it is first shown, each widget directly inside its final parent, so opening does not pay for the hidden filter or for reparenting styled widgets; data that changes nothing on screen does not rebuild the cards.

The community catalog is the only thing that loads in the background. The last catalog comes from `skills-cache.json` in the script state folder and is shown at once; a read-only helper in its own slot then asks for the feed, after the window has painted, shown by a small rotating arc in the Not installed heading. A catalog checked within the last ten minutes is not requested again when the window is reopened; Refresh always asks. The helper makes one request, for the feed, so no second service can delay it. Nothing covers the window. Install, automatic update, import and delete disable only the actions that change skills; reading, search and navigation stay available. The progress and result of an operation appear in `StatusBanner`, a closable strip between the filter chips and the cards: a rounded panel in the journal's category colors (information for progress, success, warning for a partial result, error), with wrapping text and a Dismiss action on the right. A new message replaces the previous one, and the banner is cleared when the window is opened again. Install and update also show the progress bar and elapsed time below it. An action requested while the operation slot is busy waits for it and then runs.

Skill operations start the bundled Node.js runtime directly on `core/skills-cli.js` (`launch_node()`), owned by the same job object as other helpers. This avoids the start-up time of a PowerShell wrapper on every install, delete, import and catalog request. A checkout without the bundled runtime falls back to `scripts/skills-manager.ps1`.

View details opens `SkillDetailsWindow`. It is created once and reused: choosing another skill replaces its title, badges, metadata line and document. Local skills show their instructions with Back navigation and Open Folder. The document is read from disk and rendered by Qt's own Markdown import (`render_markdown()`) inside the window, so it appears at once, without a helper process or a loading state. Raw HTML in a skill is shown as text and never interpreted, the browser loads no resources, and only text files inside the skill folder can be opened. A file that cannot be read keeps the previous document and reports the reason below it. A failed import shows its report in the same window.

A community skill that is not installed has no local files, so the window shows its published description instead: one bounded request for `docs/skills/<id>.md` on the catalog site, started through its own helper slot (`page_operation()`), rendered by the same Markdown path. While it loads, `LoadingOverlay` covers only the document area: the recessed theme color at alpha 175/255, a faint circular track and an accent-colored arc advanced 12 degrees by a 40 ms Qt timer. A description read once is kept for the session and shown again without a request; an answer for a skill that is no longer shown is ignored. Relative links open in the browser and only inside the catalog site. When the description cannot be loaded, the document is replaced by one centered sentence and a centered Open Online Page action.

## Where to make changes

| File or symbol | Responsibility |
| --- | --- |
| `python/max_ultra/widgets.py: STYLE` | Shared Qt style rules, rounding, responsive style selectors |
| `Panel.update_compact_layout()` | Main-panel button, icon, label, margin and scrollbar sizes |
| `Panel.update_journal_density()` | Log font size and base row height |
| `ActionButton`, `JournalDelegate`, `JournalView` | Custom icon/text rendering and journal layout |
| `Window`, `LoadingOverlay` | Common window behavior and the document loading veil |
| `python/max_ultra/dialogs.py` | Settings, AI setup, skill help and the shared skill document browser |
| `python/max_ultra/skills_window.py` | Skills cards, filter chips, catalog loading, automatic updates and the details window |
| `python/max_ultra/qt.py` | Qt compatibility, native shadow and keyboard integration |
| `python/max_ultra/themes.py`, `assets/themes/` | Theme loading, named colors and live application |
| `tests/qt-ui-fixture.py` | Breakpoint transitions, icons, journal behavior and sizing |
| `tests/qt-dialog-fixture.py` | Dialog layouts, opacity, skill cards and the details window |
| `tests/qt-community-fixture.py` | Skills catalog, cached opening, automatic updates, busy states and the import report |

Verify changes in both PySide2 and PySide6. Test shrinking after enlargement, theme switching, visible scrollbars, long messages, DPI scaling and keyboard interaction. Standalone Qt fixture results do not replace real-Max checks of ownership, focus, modal dialogs and multi-monitor behavior. Keep required runtime assets in `maxpkg-files.txt` when adding new files.

The main panel uses its smallest control tier below 350 logical pixels: 24-pixel action height, 14-pixel icons, 8-point journal text and a 7-pixel scrollbar. At 350 pixels and above the existing normal/large tiers remain unchanged. Skills document padding is independent of this main-panel breakpoint.
