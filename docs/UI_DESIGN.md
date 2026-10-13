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
- Skills dialog actions become icon-only below a dialog width of 900 px.

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

Changes to a shared control must apply across all windows. `ThemedComboBox` provides the same rounded dropdown and Lucide chevron with a transparent arrow area for the journal filter and Settings theme picker. `SEARCH_STYLE` keeps the main journal and Community Skills search fields consistent; checkbox appearance comes from the shared window stylesheet.

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

## Skills loading overlay

`LoadingOverlay` is a child Qt widget placed above the Skills content, similar to an absolutely positioned translucent web overlay. The title bar and close button remain uncovered.

The overlay paints the recessed theme color with alpha 175/255, a faint circular track and an accent-colored rotating arc. A 40 ms Qt timer advances the arc by 12 degrees. This is a painted progress indicator, not a replacement action icon.

`SkillsWindow.set_busy()` controls visibility and disables the underlying controls, including preview interaction. Completion or failure clears the busy state through the helper lifecycle. Resizing updates the overlay bounds. Hiding the window stops the animation timer; reopening during loading resumes it. No nested event loop or sleep is used for the animation.

## Where to make changes

| File or symbol | Responsibility |
| --- | --- |
| `python/max_ultra/widgets.py: STYLE` | Shared Qt style rules, rounding, responsive style selectors |
| `Panel.update_compact_layout()` | Main-panel button, icon, label, margin and scrollbar sizes |
| `Panel.update_journal_density()` | Log font size and base row height |
| `ActionButton`, `JournalDelegate`, `JournalView` | Custom icon/text rendering and journal layout |
| `Window`, `LoadingOverlay` | Common window behavior and loading veil |
| `python/max_ultra/dialogs.py` | Settings, AI setup, Skills and help layouts |
| `python/max_ultra/qt.py` | Qt compatibility, native shadow and keyboard integration |
| `python/max_ultra/themes.py`, `assets/themes/` | Theme loading, named colors and live application |
| `tests/qt-ui-fixture.py` | Breakpoint transitions, icons, journal behavior and sizing |
| `tests/qt-dialog-fixture.py` | Dialog layouts, opacity and overlay lifecycle |

Verify changes in both PySide2 and PySide6. Test shrinking after enlargement, theme switching, visible scrollbars, long messages, DPI scaling and keyboard interaction. Standalone Qt fixture results do not replace real-Max checks of ownership, focus, modal dialogs and multi-monitor behavior. Keep required runtime assets in `maxpkg-files.txt` when adding new files.

The main panel uses its smallest control tier below 350 logical pixels: 24-pixel action height, 14-pixel icons, 8-point journal text and a 7-pixel scrollbar. At 350 pixels and above the existing normal/large tiers remain unchanged. Skills document padding is independent of this main-panel breakpoint.
