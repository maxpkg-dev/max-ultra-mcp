# Disk-backed session history with bounded page reads and credential redaction.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import datetime
import json
from collections import deque
import re
import threading

try:
    import sqlite3
    SQLITE_IMPORT_ERROR = ""
except (ImportError, OSError) as error:
    sqlite3 = None
    SQLITE_IMPORT_ERROR = str(error)


def redact(message):
    message = str(message)
    message = re.sub(r"(?i)(authorization\s*[:=]\s*)(?:bearer\s+)?\S+", r"\1<REDACTED>", message)
    message = re.sub(r"(?i)((?:password|access_token|api_key|control.token)\s*[:=]\s*)\S+", r"\1<REDACTED>", message)
    return re.sub(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|[a-fA-F0-9]{64})\b", "<REDACTED>", message)


class Journal:
    def __new__(cls, filename):
        if sqlite3 is None:
            return FileJournal(filename)
        return super().__new__(cls)

    def __init__(self, filename):
        self.fallback_warning = ""
        self.filename = str(filename)
        self._lock = threading.RLock()
        self._db = sqlite3.connect(self.filename, timeout=1, check_same_thread=False)
        self._db.execute("PRAGMA journal_mode=WAL")
        self._db.execute("PRAGMA synchronous=NORMAL")
        self._db.execute("CREATE TABLE IF NOT EXISTS entries (id INTEGER PRIMARY KEY, stamp TEXT NOT NULL, category TEXT NOT NULL, message TEXT NOT NULL)")
        self._db.execute("CREATE INDEX IF NOT EXISTS entries_category ON entries(category, id)")
        self._db.commit()

    def append(self, category, message):
        stamp = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
        with self._lock, self._db:
            cursor = self._db.execute("INSERT INTO entries(stamp,category,message) VALUES (?,?,?)", (stamp, str(category), redact(message)))
            return cursor.lastrowid

    @staticmethod
    def _where(search, category):
        clauses, args = [], []
        if search:
            clauses.append("instr(lower(message), lower(?)) > 0")
            args.append(search)
        if category:
            clauses.append("category = ?")
            args.append(category)
        return (" WHERE " + " AND ".join(clauses) if clauses else ""), args

    def count(self, search="", category=""):
        where, args = self._where(search, category)
        with self._lock:
            return self._db.execute("SELECT count(*) FROM entries" + where, args).fetchone()[0]

    def page(self, offset=0, limit=256, search="", category=""):
        if offset < 0 or not 1 <= limit <= 1000:
            raise ValueError("Invalid journal page bounds")
        where, args = self._where(search, category)
        with self._lock:
            return self._db.execute("SELECT id,stamp,category,message FROM entries" + where + " ORDER BY id LIMIT ? OFFSET ?", args + [limit, offset]).fetchall()

    def tail(self, limit=30):
        limit = min(1000, max(1, limit))
        with self._lock:
            return list(reversed(self._db.execute("SELECT id,stamp,category,message FROM entries ORDER BY id DESC LIMIT ?", (limit,)).fetchall()))

    def export(self, destination, search="", category=""):
        # Stream a consistent snapshot without accumulating the whole history.
        where, args = self._where(search, category)
        database = sqlite3.connect(self.filename, timeout=1)
        try:
            with open(destination, "w", encoding="utf-8", newline="\n") as stream:
                for row in database.execute("SELECT id,stamp,category,message FROM entries" + where + " ORDER BY id", args):
                    stream.write("{} [{}] {}\n".format(row[1], row[2], row[3]))
        finally:
            database.close()

    def close(self):
        with self._lock:
            self._db.close()


class FileJournal:
    """Streaming JSON-lines storage when the host cannot import SQLite.

    Reads scan disk rather than retaining unbounded session history in memory.
    Existing SQLite files are never opened or modified by this backend.
    """

    def __init__(self, filename):
        self.filename = str(filename) + ".jsonl"
        self._lock = threading.RLock()
        self._closed = False
        self.fallback_warning = (
            "SQLite is unavailable; activity history uses fallback file storage. "
            "Search and paging may be slower for large logs. " + SQLITE_IMPORT_ERROR)
        with open(self.filename, "a", encoding="utf-8"):
            pass
        self._next_id = 1
        for row in self._rows():
            self._next_id = max(self._next_id, row[0] + 1)

    def _rows(self, search="", category=""):
        if self._closed:
            raise RuntimeError("Journal is closed")
        with open(self.filename, "r", encoding="utf-8") as stream:
            for line in stream:
                row = json.loads(line)
                if (not search or search.lower() in row[3].lower()) and (not category or row[2] == category):
                    yield tuple(row)

    def append(self, category, message):
        stamp = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
        with self._lock:
            if self._closed:
                raise RuntimeError("Journal is closed")
            row = (self._next_id, stamp, str(category), redact(message))
            with open(self.filename, "a", encoding="utf-8", newline="\n") as stream:
                stream.write(json.dumps(row, ensure_ascii=True) + "\n")
            self._next_id += 1
            return row[0]

    def count(self, search="", category=""):
        with self._lock:
            return sum(1 for _ in self._rows(search, category))

    def page(self, offset=0, limit=256, search="", category=""):
        if offset < 0 or not 1 <= limit <= 1000:
            raise ValueError("Invalid journal page bounds")
        with self._lock:
            rows = []
            for index, row in enumerate(self._rows(search, category)):
                if index >= offset:
                    rows.append(row)
                    if len(rows) == limit:
                        break
            return rows

    def tail(self, limit=30):
        with self._lock:
            return list(deque(self._rows(), maxlen=min(1000, max(1, limit))))

    def export(self, destination, search="", category=""):
        from pathlib import Path
        if Path(destination).resolve() == Path(self.filename).resolve():
            raise ValueError("Export destination must differ from journal storage")
        with self._lock:
            if self._closed:
                raise RuntimeError("Journal is closed")
            with open(destination, "w", encoding="utf-8", newline="\n") as stream:
                for row in self._rows(search, category):
                    stream.write("{} [{}] {}\n".format(row[1], row[2], row[3]))

    def close(self):
        with self._lock:
            self._closed = True
