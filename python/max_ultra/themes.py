# File-backed palettes shared by all Max Ultra Qt windows and passive previews.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import json
import re
from pathlib import Path

THEME_DIRECTORY = Path(__file__).resolve().parents[2] / 'assets/themes'
BINDINGS = json.loads((THEME_DIRECTORY / 'bindings.json').read_text(encoding='utf-8-sig'))
PALETTE_ROLES = ('window_background', 'field_background', 'button_background', 'journal_background', 'border', 'button_hover', 'heading_text')
REQUIRED_ROLES = set(BINDINGS.values()) | {'field_text', 'header_background'}
THEME_IDS = ('max', 'graphite', 'forest', 'plum', 'coffee', 'teal', 'burgundy')
current = 'graphite'
max_colors = {}
definition = {}


def load(identifier):
    if identifier not in THEME_IDS:
        raise ValueError('Unknown color theme')
    document = json.loads((THEME_DIRECTORY / (identifier + '.json')).read_text(encoding='utf-8-sig'))
    if not isinstance(document, dict) or not isinstance(document.get('name'), str) or not isinstance(document.get('colors'), dict):
        raise ValueError('Invalid theme name or colors: ' + identifier)
    missing = REQUIRED_ROLES - set(document['colors'])
    if missing:
        raise ValueError('Missing theme colors: ' + ', '.join(sorted(missing)))
    native = document.get('colorMan', {})
    light = document.get('light_colors', {})
    if not isinstance(native, dict) or not isinstance(light, dict):
        raise ValueError('Invalid colorMan or light_colors section')
    def validate(value, allow_mix=True):
        if isinstance(value, str) and (re.fullmatch(r'#[0-9a-fA-F]{6}', value) or value.startswith('$') and value[1:] in native):
            return
        if allow_mix and isinstance(value, dict) and set(value) == {'mix'}:
            parts = value['mix']
            if isinstance(parts, list) and len(parts) == 3 and isinstance(parts[2], (float, int)) and 0 <= parts[2] <= 1:
                validate(parts[0], False)
                validate(parts[1], False)
                return
        raise ValueError('Invalid theme color: ' + repr(value))
    for fallback in native.values():
        if not isinstance(fallback, str) or not re.fullmatch(r'#[0-9a-fA-F]{6}', fallback):
            raise ValueError('Invalid colorMan fallback')
    for value in list(document['colors'].values()) + list(light.values()):
        validate(value)
    return document


def resolve(value, document=None):
    document = definition if document is None else document
    if isinstance(value, dict):
        first, second, amount = value['mix']
        first, second = resolve(first, document), resolve(second, document)
        return '#' + ''.join('{:02x}'.format(round(int(first[i:i+2], 16) * (1-amount) + int(second[i:i+2], 16) * amount)) for i in (1, 3, 5))
    if value.startswith('$'):
        return max_colors.get(value[1:], document['colorMan'][value[1:]])
    return value.lower()


def palette(document):
    return tuple(resolve(document['colors'][role], document) for role in PALETTE_ROLES)


THEMES = {}
definition = load('graphite')
for _identifier in THEME_IDS:
    try:
        _document = load(_identifier)
    except (OSError, ValueError):
        # Keep malformed optional palettes selectable so the controller can
        # report their errors without preventing the entire script from starting.
        _document = dict(definition, name=_identifier.title())
    THEMES[_identifier] = (_document['name'], palette(_document))


def color_hex(value):
    channels = [float(value.x), float(value.y), float(value.z)]
    scale = 255 if max(channels) <= 1.001 else 1
    return '#' + ''.join('{:02x}'.format(max(0, min(255, round(channel * scale)))) for channel in channels)


def read_max_colors(runtime):
    global max_colors
    native = definition.get('colorMan', {})
    values = {}
    for name, fallback in native.items():
        try:
            values[name] = color_hex(runtime.colorMan.getColor(runtime.Name(name)))
        except (RuntimeError, TypeError, AttributeError, ValueError):
            values[name] = fallback
    changed = values != max_colors
    max_colors = values
    THEMES[current] = (definition['name'], palette(definition))
    return changed


def max_is_light():
    if not definition.get('colorMan'):
        return False
    color = resolve(definition['colors']['field_background'])
    return sum(int(color[i:i+2], 16) * weight for i, weight in ((1, .2126), (3, .7152), (5, .0722))) > 150


def select(identifier, document=None):
    global current, definition
    identifier = identifier if identifier in THEMES else 'graphite'
    document = load(identifier) if document is None else document
    # Load and validate before changing the active palette.
    current, definition = identifier, document
    THEMES[identifier] = (document['name'], palette(document))
    return current


def style(source):
    colors = dict(definition['colors'])
    if max_is_light():
        colors.update(definition.get('light_colors', {}))
    def replace_color(match):
        value = match.group()
        if value.startswith('@'):
            role = value[1:]
        else:
            value = value.lower() if value.startswith('#') else '#{:02x}{:02x}{:02x}'.format(*(int(match.group(i)) for i in (1, 2, 3)))
            role = BINDINGS.get(value)
        return resolve(colors[role]) if role in colors else match.group()
    rendered = re.sub(r'@[a-z][a-z0-9_]*|#[0-9a-fA-F]{6}\b|rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)', replace_color, source)
    if 'QWidget {' in source:
        rendered += '\nQLineEdit, QPlainTextEdit, QTextBrowser, QTableView, QTreeWidget, QListWidget, QComboBox { color:' + resolve(colors['field_text']) + '; }'
        rendered += '\nQWidget#windowHeader { background:' + resolve(colors['header_background']) + '; }'
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
