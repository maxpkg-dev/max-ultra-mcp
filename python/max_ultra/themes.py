# Shared dark color schemes for all Max Ultra Qt windows and passive previews.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import re

THEMES = {
    "max": ("3ds Max (user colors)", ("#242320", "#1c1c1a", "#302e29", "#302f2b", "#514b42", "#41382d", "#efb577")),
    "graphite": ("Warm Graphite", ("#242320", "#1c1c1a", "#302e29", "#302f2b", "#514b42", "#41382d", "#efb577")),
    "forest": ("Forest", ("#202824", "#19211d", "#2c3831", "#29352e", "#506457", "#3a4d40", "#a9c994")),
    "plum": ("Muted Plum", ("#29232d", "#211c25", "#372f3d", "#332c39", "#61536d", "#493d52", "#ccb0dd")),
    "coffee": ("Coffee", ("#2c241f", "#241c17", "#3c3027", "#372d26", "#6a5544", "#4d3d30", "#dfbb89")),
}
current = "graphite"
max_colors = {}


def color_hex(value):
    channels = [float(value.x), float(value.y), float(value.z)]
    scale = 255 if max(channels) <= 1.001 else 1
    return '#' + ''.join('{:02x}'.format(max(0, min(255, round(channel * scale)))) for channel in channels)


def read_max_colors(runtime):
    global max_colors
    defaults = {'background': '#444444', 'window': '#333333', 'text': '#e1e1e1',
                'windowText': '#e1e1e1', 'shadow': '#282828', 'hilight': '#666666',
                'itemHilight': '#705137', 'hilightText': '#ffffff',
                'rollupTitleFace': '#515151', 'rollupTitleText': '#e1e1e1'}
    values = {}
    for name, fallback in defaults.items():
        try:
            values[name] = color_hex(runtime.colorMan.getColor(runtime.Name(name)))
        except (RuntimeError, TypeError, AttributeError, ValueError):
            values[name] = fallback
    changed = values != max_colors
    max_colors = values
    THEMES['max'] = ('3ds Max (user colors)', (values['background'], values['window'], values['background'], values['window'], values['shadow'], values['hilight'], values['rollupTitleText']))
    return changed


def max_is_light():
    color = max_colors.get('window', '#333333')
    return current == 'max' and sum(int(color[index:index+2], 16) * weight for index, weight in ((1, .2126), (3, .7152), (5, .0722))) > 150


def select(identifier):
    global current
    current = identifier if identifier in THEMES else "graphite"
    return current


def style(source):
    if current == "graphite":
        return source
    background, field, button, journal, border, hover, accent = THEMES[current][1]
    groups = (
        (("#242320", "#292823"), background),
        (("#1c1c1a", "#1e1e1b", "#191916"), field),
        (("#302e29", "#35312a", "#39342c", "#353535"), button),
        (("#302f2b", "#292929"), journal),
        (("#514b42", "#49453e", "#5a554b", "#60574a", "#4b463e", "#62594c", "#777066", "#8e7455", "#615647"), border),
        (("#41382d", "#705137", "#493b2c"), hover),
        (("#efb577", "#dc9b57", "#e3a363"), accent),
    )
    replacements = {key: value for keys, value in groups for key in keys}
    if current == 'max' and max_colors:
        replacements.update({
            '#e8e3da': max_colors['text'], '#b8b0a3': max_colors['text'],
            '#eee8de': max_colors['text'], '#efb577': max_colors['rollupTitleText'],
            '#705137': max_colors['itemHilight'], '#493b2c': max_colors['itemHilight'],
            '#fff0dc': max_colors['hilightText'], '#fff0df': max_colors['hilightText'],
        })
        if max_is_light():
            replacements.update({'#8ed0e0': '#236270', '#bea5ff': '#683c9b', '#78e196': '#246d37',
                                 '#ffc350': '#895100', '#ff7d7d': '#a52a2a', '#efa35c': '#9c4c00',
                                 '#bebe8c': '#626222', '#29232c': '#ffffff'})
    def replace_color(match):
        value = match.group().lower() if match.group().startswith('#') else '#{:02x}{:02x}{:02x}'.format(*(int(match.group(index)) for index in (1, 2, 3)))
        return replacements.get(value, match.group())
    rendered = re.sub(r'#[0-9a-fA-F]{6}\b|rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)', replace_color, source)
    if current == 'max' and max_colors and 'QWidget {' in source:
        rendered += '\nQLineEdit, QPlainTextEdit, QTextBrowser, QTableView, QTreeWidget, QListWidget { color:' + max_colors['windowText'] + '; }'
        rendered += '\nQWidget#windowHeader { background:' + max_colors['rollupTitleFace'] + '; }'
    return rendered


def html(content):
    # Change CSS only; skill examples and copied code must remain byte-for-byte
    # unchanged even when they contain palette colors as sample data.
    content = re.sub(r'(<style\b[^>]*>)(.*?)(</style>)', lambda match: match[1] + style(match[2]) + match[3], content, flags=re.I | re.S)
    return re.sub(r'(\bstyle\s*=\s*)([\'\"])(.*?)\2', lambda match: match[1] + match[2] + style(match[3]) + match[2], content, flags=re.I | re.S)


def set_style(widget, source):
    widget._theme_style = source
    widget.setStyleSheet(style(source))


def set_label(widget, source):
    widget._theme_label = source
    widget.setText(html(source))


def apply(window):
    apply_all([window])


def apply_all(windows):
    from .qt import QtWidgets
    widgets, seen = [], set()
    for window in windows:
        for widget in [window] + window.findChildren(QtWidgets.QWidget):
            if id(widget) not in seen:
                seen.add(id(widget))
                widgets.append(widget)
    # Restyle every window first, then its rich content. Settings is also a
    # child of the panel, so deduplicate it instead of processing it twice.
    for window in windows:
        window.setUpdatesEnabled(False)
    try:
        for widget in widgets:
            source = getattr(widget, "_theme_style", None)
            if source is not None:
                widget.setStyleSheet(style(source))
        for widget in widgets:
            label = getattr(widget, '_theme_label', None)
            if label is not None:
                widget.setText(html(label))
            content = getattr(widget, "_theme_html", None)
            if content is not None:
                position = widget.verticalScrollBar().value()
                widget.setHtml(content)
                widget.verticalScrollBar().setValue(position)
    finally:
        for window in windows:
            window.setUpdatesEnabled(True)
            # PySide6 item views expose update(index), unlike QWidget.update().
            # Repaint only the owning windows, explicitly using QWidget's API.
            QtWidgets.QWidget.update(window)
