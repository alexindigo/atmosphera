#!/usr/bin/env python3
"""browser-bridge — per-window website identity for the niri windows map.

For every browser window niri reports, resolve the current tab's URL by
matching the window title against the browser's own history database, then
pull the site's favicon from the browser's local favicon cache. Everything
is read from local files; no network access, no browser cooperation needed.

Tier 1 (this file) is zero-setup. If KDE's plasma-browser-integration
extension is ever installed, a Tier 2 live feed can replace the history
scraping without changing the output shape.

Output: one JSON array per line, printed when anything changes:
  [{"winId": 7, "url": "https://github.com/...", "host": "github.com",
    "icon": "/home/user/.cache/atmosphera/browser-icons/<hash>.png"}]
`icon` is null when the browser has no cached favicon for the URL.

Matching: browsers set the window title to "<page title> - <Browser>".
History DBs store (url, title, visit_time) — Firefox places.sqlite
(moz_places), Chromium History (urls). We strip the browser suffix and
notification counters from the window title, then look up the most recent
history entry by exact title, falling back to containment. Per-URL, not
per-tab — good enough for a favicon.

DB safety: browsers hold their DBs in WAL mode; we copy db+wal+shm to a
temp dir and query the copy. Originals are never opened.
"""

import hashlib
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.parse

POLL_INTERVAL = 2.0
POLL_INTERVAL_DOWN = 5.0

CACHE_DIR = os.path.expanduser("~/.cache/atmosphera/browser-icons")

BROWSER_DEFS = [
    {
        "kind": "firefox",
        "app_ids": {"firefox", "org.mozilla.firefox"},
        "suffixes": [" — Mozilla Firefox", " - Mozilla Firefox"],
        "history_sql": (
            "SELECT url FROM moz_places WHERE title = ? "
            "ORDER BY last_visit_date DESC LIMIT 1"
        ),
        "history_like_sql": (
            "SELECT url FROM moz_places WHERE title != '' AND ? LIKE '%' || title || '%' "
            "ORDER BY last_visit_date DESC LIMIT 1"
        ),
        "favicon_sql": (
            "SELECT i.data, i.width FROM moz_icons i "
            "JOIN moz_icons_to_pages ip ON ip.icon_id = i.id "
            "JOIN moz_pages_w_icons p ON p.id = ip.page_id "
            "WHERE p.page_url = ? AND i.data IS NOT NULL "
            "ORDER BY i.width DESC LIMIT 1"
        ),
        "favicon_host_sql": (
            "SELECT i.data, i.width FROM moz_icons i "
            "JOIN moz_icons_to_pages ip ON ip.icon_id = i.id "
            "JOIN moz_pages_w_icons p ON p.id = ip.page_id "
            "WHERE p.page_url LIKE ? || '%' AND i.data IS NOT NULL "
            "ORDER BY i.width DESC LIMIT 1"
        ),
    },
    {
        "kind": "chromium",
        "app_ids": {"brave-browser", "google-chrome", "chromium", "chromium-browser"},
        "suffixes": [" - Brave", " - Google Chrome", " - Chromium", " - Chrome"],
        "history_sql": (
            "SELECT url FROM urls WHERE title = ? "
            "ORDER BY last_visit_time DESC LIMIT 1"
        ),
        "history_like_sql": (
            "SELECT url FROM urls WHERE title != '' AND ? LIKE '%' || title || '%' "
            "ORDER BY last_visit_time DESC LIMIT 1"
        ),
        "favicon_sql": (
            "SELECT b.image_data, b.width FROM favicon_bitmaps b "
            "JOIN icon_mapping m ON m.icon_id = b.icon_id "
            "WHERE m.page_url = ? AND b.image_data IS NOT NULL "
            "ORDER BY b.width DESC LIMIT 1"
        ),
        "favicon_host_sql": (
            "SELECT b.image_data, b.width FROM favicon_bitmaps b "
            "JOIN icon_mapping m ON m.icon_id = b.icon_id "
            "WHERE m.page_url LIKE ? || '%' AND b.image_data IS NOT NULL "
            "ORDER BY b.width DESC LIMIT 1"
        ),
    },
]

# Profile locations: (kind, history_path, favicons_path). Firefox profiles
# are resolved dynamically from profiles.ini (default profile only, v1).
CHROMIUM_PROFILES = [
    ("brave-browser", "~/.config/BraveSoftware/Brave-Browser/Default"),
    ("google-chrome", "~/.config/google-chrome/Default"),
    ("chromium", "~/.config/chromium/Default"),
    ("chromium-browser", "~/.config/chromium/Default"),
]

_COUNTER_RE = re.compile(r"^\(\d+\)\s*")  # "(3) Inbox" notification counters
_STYLE_ATTR_RE = re.compile(r'style="([^"]*)"')


def sanitize_svg(data):
    """Rewrite CSS-style clip-path to the presentation-attribute form.

    QtSvg (QML Image) ignores `style="clip-path:url(#id)"` but honors the
    `clip-path="url(#id)"` attribute — without this, clipped SVG favicons
    (e.g. gemini.google.com's star) render as their full bounding box.
    Non-SVG input is returned untouched.
    """
    head = data[:300].lstrip()
    if not (head.startswith(b"<svg") or head.startswith(b"<?xml")):
        return data
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return data

    def fix(m):
        kept = []
        clip = None
        for rule in m.group(1).split(";"):
            rule = rule.strip()
            if not rule:
                continue
            if rule.startswith("clip-path:") and clip is None:
                clip = rule.split(":", 1)[1].strip()
            else:
                kept.append(rule)
        out = ""
        if kept:
            out = 'style="' + "; ".join(kept) + '"'
        if clip:
            out = (out + " " if out else "") + f'clip-path="{clip}"'
        return out or 'style=""'

    return _STYLE_ATTR_RE.sub(fix, text).encode("utf-8")


_SVG_HEAD = (b"<svg", b"<?xml")


def is_svg(data):
    head = data[:300].lstrip()
    return head.startswith(_SVG_HEAD[0]) or head.startswith(_SVG_HEAD[1])


def rasterize_svg(data, size=256):
    """Best-effort SVG→PNG via an available system rasterizer.

    QtSvg mishandles some valid SVGs (clip-path around embedded rasters,
    e.g. gemini.google.com's star). rsvg-convert/resvg render them
    correctly, so prefer a real rasterizer when one is installed. Returns
    PNG bytes or None (caller falls back to the sanitized SVG).
    """
    for tool in ("rsvg-convert", "resvg"):
        exe = shutil.which(tool)
        if not exe:
            continue
        src = out = None
        try:
            with tempfile.NamedTemporaryFile(suffix=".svg", delete=False) as f:
                f.write(data)
                src = f.name
            out = src + ".png"
            if tool == "rsvg-convert":
                cmd = [exe, "-w", str(size), "-h", str(size), "-o", out, src]
            else:
                cmd = [exe, "-w", str(size), src, out]
            r = subprocess.run(cmd, capture_output=True, timeout=15)
            if r.returncode == 0 and os.path.isfile(out):
                with open(out, "rb") as f:
                    return f.read()
        except Exception:
            pass
        finally:
            for p in (src, out):
                if p:
                    try:
                        os.unlink(p)
                    except OSError:
                        pass
    return None


def norm_title(title, suffixes):
    t = (title or "").strip()
    for s in suffixes:
        if t.endswith(s):
            t = t[: -len(s)].strip()
            break
    # Firefox appends "(Private Browsing)" — those tabs won't be in history
    # anyway, but strip so the lookup at least fails cleanly
    for s in list(suffixes):
        for priv in (" (Private Browsing)",):
            if t.endswith(s + priv):
                t = t[: -len(s + priv)].strip()
    t = _COUNTER_RE.sub("", t)
    return t


def firefox_default_profile():
    """Path of the default Firefox profile dir, or None."""
    root = os.path.expanduser("~/.mozilla/firefox")
    ini = os.path.join(root, "profiles.ini")
    try:
        import configparser

        cp = configparser.ConfigParser()
        cp.read(ini)
        # [Install*] sections point at the profile actually in use
        for sec in cp.sections():
            if sec.startswith("Install") and cp.has_option(sec, "Default"):
                p = cp.get(sec, "Default")
                if os.path.isdir(os.path.join(root, p)):
                    return os.path.join(root, p)
                if os.path.isdir(p):
                    return p
        for sec in cp.sections():
            if sec.startswith("Profile") and cp.get(sec, "Default", fallback="0") == "1":
                p = cp.get(sec, "Path")
                if cp.get(sec, "IsRelative", fallback="1") == "1":
                    p = os.path.join(root, p)
                if os.path.isdir(p):
                    return p
    except Exception:
        pass
    # Fallback: newest dir containing places.sqlite
    try:
        cands = [
            os.path.join(root, d)
            for d in os.listdir(root)
            if os.path.isfile(os.path.join(root, d, "places.sqlite"))
        ]
        if cands:
            return max(cands, key=os.path.getmtime)
    except Exception:
        pass
    return None


class BrowserSource:
    """One detected browser profile: app_id prefix + DB paths."""

    def __init__(self, defn, app_id, history, favicons):
        self.defn = defn
        self.app_id = app_id
        self.history = history
        self.favicons = favicons

    def mtimes(self):
        def mt(p):
            try:
                return os.path.getmtime(p)
            except OSError:
                return None

        return (mt(self.history), mt(self.history + "-wal"),
                mt(self.favicons), mt(self.favicons + "-wal"))


def detect_sources():
    sources = []
    ff_profile = firefox_default_profile()
    if ff_profile:
        for app_id in ("firefox", "org.mozilla.firefox"):
            sources.append(BrowserSource(
                BROWSER_DEFS[0], app_id,
                os.path.join(ff_profile, "places.sqlite"),
                os.path.join(ff_profile, "favicons.sqlite"),
            ))
    for app_id, profile in CHROMIUM_PROFILES:
        profile = os.path.expanduser(profile)
        hist = os.path.join(profile, "History")
        if os.path.isfile(hist):
            sources.append(BrowserSource(
                BROWSER_DEFS[1], app_id, hist,
                os.path.join(profile, "Favicons"),
            ))
    return [s for s in sources if os.path.isfile(s.history)]


def connect_copy(db_path):
    """Copy db (+wal/shm) to a temp dir and open the copy read-only."""
    if not db_path or not os.path.isfile(db_path):
        return None, None
    tmp = tempfile.mkdtemp(prefix="atmosphera-bridge-")
    base = os.path.basename(db_path)
    for suffix in ("", "-wal", "-shm"):
        src = db_path + suffix
        if os.path.isfile(src):
            try:
                shutil.copyfile(src, os.path.join(tmp, base + suffix))
            except OSError:
                pass
    try:
        conn = sqlite3.connect(f"file:{os.path.join(tmp, base)}?mode=ro", uri=True)
    except sqlite3.Error:
        shutil.rmtree(tmp, ignore_errors=True)
        return None, None
    return conn, tmp


def query_url(hist_conn, defn, title):
    if hist_conn is None or not title:
        return None
    try:
        row = hist_conn.execute(defn["history_sql"], (title,)).fetchone()
        if row:
            return row[0]
        row = hist_conn.execute(defn["history_like_sql"], (title,)).fetchone()
        if row:
            return row[0]
    except sqlite3.Error:
        pass
    return None


def query_favicon(fav_conn, defn, url):
    """(blob, native_width) for the URL's favicon, or None.

    Native width drives the QML-side clamp: the favicon is rendered as a
    small overlay badge and should never be upscaled past its real size.
    Firefox marks SVG icons with width 65535, which reads as "infinite" —
    exactly what a scalable icon wants.
    """
    if fav_conn is None or not url:
        return None
    try:
        row = fav_conn.execute(defn["favicon_sql"], (url,)).fetchone()
        if not row:
            p = urllib.parse.urlparse(url)
            if p.scheme and p.hostname:
                origin = f"{p.scheme}://{p.hostname}"
                if p.port:
                    origin += f":{p.port}"
                row = fav_conn.execute(defn["favicon_host_sql"], (origin,)).fetchone()
        if row and row[0]:
            return (row[0], row[1] or 0)
    except sqlite3.Error:
        pass
    return None


def icon_path_for(url, blob):
    """Write the favicon blob to the cache (once) and return its path."""
    digest = hashlib.sha1(url.encode("utf-8")).hexdigest()[:16]
    path = os.path.join(CACHE_DIR, digest + ".png")
    if not os.path.isfile(path):
        os.makedirs(CACHE_DIR, exist_ok=True)
        try:
            with open(path, "wb") as f:
                f.write(sanitize_svg(blob))
        except OSError:
            return None
    return path


def list_browser_windows(sources):
    out = subprocess.run(
        ["niri", "msg", "-j", "windows"],
        capture_output=True, text=True, timeout=5,
    )
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or "niri msg failed")
    by_app = {s.app_id: s for s in sources}
    windows = []
    for w in json.loads(out.stdout):
        src = by_app.get(w.get("app_id") or "")
        if src is not None:
            windows.append((w, src))
    return windows


def snapshot(sources):
    windows = list_browser_windows(sources)
    if not windows:
        return []

    # One copied DB connection per source, shared by its windows
    conns = {}
    tmps = []
    try:
        for _, src in windows:
            if id(src) in conns:
                continue
            hist_conn, tmp1 = connect_copy(src.history)
            fav_conn, tmp2 = connect_copy(src.favicons)
            conns[id(src)] = (hist_conn, fav_conn)
            tmps += [t for t in (tmp1, tmp2) if t]

        entries = []
        for w, src in windows:
            hist_conn, fav_conn = conns[id(src)]
            title = norm_title(w.get("title"), src.defn["suffixes"])
            url = query_url(hist_conn, src.defn, title)
            if not url:
                continue
            icon = None
            icon_w = 0
            fav = query_favicon(fav_conn, src.defn, url)
            if fav:
                blob, icon_w = fav
                if is_svg(blob):
                    # QtSvg can't render every valid SVG (clip-path around
                    # embedded rasters) — rasterize when a rasterizer is
                    # available; else sanitize + pass through
                    png = rasterize_svg(blob)
                    if png:
                        blob, icon_w = png, 256
                    else:
                        blob = sanitize_svg(blob)
                icon = icon_path_for(url, blob)
            host = urllib.parse.urlparse(url).hostname
            entries.append({
                "winId": w["id"],
                "url": url,
                "host": host,
                "icon": icon,
                "iconW": icon_w,
            })
        entries.sort(key=lambda e: e["winId"])
        return entries
    finally:
        for hist_conn, fav_conn in conns.values():
            for c in (hist_conn, fav_conn):
                if c:
                    c.close()
        for t in tmps:
            shutil.rmtree(t, ignore_errors=True)


def main():
    os.makedirs(CACHE_DIR, exist_ok=True)
    sources = detect_sources()
    last = None
    last_key = None
    interval = POLL_INTERVAL
    while True:
        try:
            windows = list_browser_windows(sources)
            # Skip all work when nothing relevant changed: same window
            # titles AND same DB mtimes means the same result as last time.
            key = (
                tuple(sorted((w["id"], w.get("title")) for w, _ in windows)),
                tuple((s.app_id, s.mtimes()) for s in
                      {id(s): s for _, s in windows}.values()),
            )
            if key != last_key:
                snap = snapshot(sources)
                interval = POLL_INTERVAL
                if snap != last:
                    print(json.dumps(snap), flush=True)
                    last = snap
                last_key = key
        except Exception as exc:
            print(f"browser-bridge: {exc}", file=sys.stderr)
            interval = POLL_INTERVAL_DOWN
            if last != []:
                print("[]", flush=True)
                last = []
            last_key = None
        time.sleep(interval)


if __name__ == "__main__":
    main()
