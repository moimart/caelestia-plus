#!/usr/bin/env python3
"""The favicon of the page a browser window shows, for the bar.

    favicon.py <window class> <window title>

For web app windows (chrome-web.whatsapp.com__-Default) it's the site's icon.
Prints the path of a PNG (cached in ~/.cache/caelestia/favicons), or nothing.

No browser tells other programs which page a window shows, but its window
title is the page's title, and its own history knows which address had that
title and which icon that address has. So: the newest page in history with
this title, then its favicon (or, failing that, its site's). The databases
are opened read-only and immutable, so a running browser is never disturbed;
nothing goes over the network. Private windows aren't in history, so they
get nothing (and the bar shows the browser's own icon).
"""

import hashlib
import os
import re
import sqlite3
import sys
import urllib.parse
from pathlib import Path

home = Path.home()
config = Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config")
cache = Path(os.environ.get("XDG_CACHE_HOME") or home / ".cache") / "caelestia" / "favicons"

# Window class -> (profile root, title suffix)
CHROMIUM = {
    "google-chrome": (config / "google-chrome", "Google Chrome"),
    "google-chrome-beta": (config / "google-chrome-beta", "Google Chrome Beta"),
    "chromium": (config / "chromium", "Chromium"),
    "brave-browser": (config / "BraveSoftware" / "Brave-Browser", "Brave"),
    "microsoft-edge": (config / "microsoft-edge", "Microsoft​ Edge"),
    "vivaldi-stable": (config / "vivaldi", "Vivaldi"),
}
FIREFOX = {"firefox": [home / ".mozilla" / "firefox", config / "mozilla" / "firefox"]}
# Web app windows ("--app=URL" or installed): "<browser>-<host>__<path>-<profile>"
WEBAPP = re.compile(r"^(chrome|chromium|brave|msedge|vivaldi)-([^_]+)__")
WEBAPP_BROWSER = {"chrome": "google-chrome", "chromium": "chromium", "brave": "brave-browser",
                  "msedge": "microsoft-edge", "vivaldi": "vivaldi-stable"}


def connect(path: Path):
    return sqlite3.connect(f"file:{urllib.parse.quote(str(path))}?immutable=1", uri=True)


def site_prefix(url: str) -> str:
    u = urllib.parse.urlsplit(url)
    return f"{u.scheme}://{u.netloc}/"


def best(rows):
    """The bitmap to use from [(width, png bytes)]: 32 px if there is one,
    else the smallest bigger one, else the biggest."""
    rows = [r for r in rows if r[1]]
    if not rows:
        return None
    bigger = sorted((r for r in rows if r[0] >= 32), key=lambda r: r[0])
    return (bigger[0] if bigger else max(rows, key=lambda r: r[0]))[1]


def chromium(root: Path, suffix: str, title: str):
    title = re.sub(rf" - {re.escape(suffix)}( - .*)?$", "", title)
    found = None  # (last visit, profile, url)
    for profile in [root / "Default", *sorted(root.glob("Profile *"))]:
        if not (profile / "History").exists():
            continue
        try:
            with connect(profile / "History") as db:
                row = db.execute(
                    "SELECT last_visit_time, url FROM urls WHERE title = ? ORDER BY last_visit_time DESC LIMIT 1",
                    (title,)).fetchone()
        except sqlite3.Error:
            continue
        if row and (not found or row[0] > found[0]):
            found = (row[0], profile, row[1])
    if not found:
        return None
    _, profile, url = found
    try:
        with connect(profile / "Favicons") as db:
            query = ("SELECT b.width, b.image_data FROM icon_mapping m JOIN favicon_bitmaps b ON b.icon_id = m.icon_id "
                     "WHERE m.page_url {} ORDER BY b.last_updated DESC")
            png = best(db.execute(query.format("= ?"), (url,)).fetchall())
            if png is None:
                png = best(db.execute(query.format("LIKE ?"), (site_prefix(url) + "%",)).fetchall())
    except sqlite3.Error:
        return None
    return png


def chromium_site(root: Path, host: str):
    """The newest favicon any profile has for a site, for web app windows."""
    for profile in [root / "Default", *sorted(root.glob("Profile *"))]:
        if not (profile / "Favicons").exists():
            continue
        try:
            with connect(profile / "Favicons") as db:
                png = best(db.execute(
                    "SELECT b.width, b.image_data FROM icon_mapping m JOIN favicon_bitmaps b ON b.icon_id = m.icon_id "
                    "WHERE m.page_url LIKE ? ORDER BY b.last_updated DESC", (f"https://{host}/%",)).fetchall())
        except sqlite3.Error:
            continue
        if png is not None:
            return png
    return None


def firefox(roots, title: str):
    title = re.sub(r" [—-] Mozilla Firefox( Private Browsing)?$", "", title)
    for root in roots:
        for profile in sorted(root.glob("*"), key=lambda p: -(p / "places.sqlite").stat().st_mtime if (p / "places.sqlite").exists() else 0):
            if not (profile / "places.sqlite").exists():
                continue
            try:
                with connect(profile / "places.sqlite") as db:
                    row = db.execute("SELECT url FROM moz_places WHERE title = ? ORDER BY last_visit_date DESC LIMIT 1",
                                     (title,)).fetchone()
                if not row:
                    continue
                with connect(profile / "favicons.sqlite") as db:
                    query = ("SELECT i.width, i.data FROM moz_pages_w_icons p JOIN moz_icons_to_pages ip ON ip.page_id = p.id "
                             "JOIN moz_icons i ON i.id = ip.icon_id WHERE p.page_url {}")
                    png = best(db.execute(query.format("= ?"), (row[0],)).fetchall())
                    if png is None:
                        png = best(db.execute(query.format("LIKE ?"), (site_prefix(row[0]) + "%",)).fetchall())
                if png is not None:
                    return png
            except (sqlite3.Error, OSError):
                continue
    return None


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: favicon.py <window class> <window title>")
    cls, title = sys.argv[1], sys.argv[2]
    webapp = WEBAPP.match(cls)
    if webapp:
        png = chromium_site(CHROMIUM[WEBAPP_BROWSER[webapp[1]]][0], webapp[2])
    elif cls in CHROMIUM:
        png = chromium(*CHROMIUM[cls], title)
    elif cls in FIREFOX:
        png = firefox(FIREFOX[cls], title)
    else:
        return
    # Only real images: PNG, or an ICO/SVG Firefox might store
    if not png or not (png.startswith(b"\x89PNG") or png[:4] == b"\0\0\1\0" or png.lstrip().startswith(b"<")):
        return
    ext = ".png" if png.startswith(b"\x89PNG") else (".ico" if png[:4] == b"\0\0\1\0" else ".svg")
    cache.mkdir(parents=True, exist_ok=True)
    path = cache / (hashlib.sha1(png).hexdigest()[:16] + ext)
    if not path.exists():
        tmp = path.with_suffix(".tmp")
        tmp.write_bytes(png)
        tmp.replace(path)
    print(path)


if __name__ == "__main__":
    main()
