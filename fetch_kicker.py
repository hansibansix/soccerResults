#!/usr/bin/env python3
"""Fetch kicker.de pages, handling DataDome bot protection.

Uses primp (TLS-impersonating HTTP client) with a DataDome cookie read from
a browser's cookie store. Mozilla-based browsers are read directly from
their SQLite cookie DB. Chromium-based browsers use pycookiecheat to decrypt
the encrypted cookie store. The cookie is set automatically when you visit
kicker.de in the browser and lasts ~1 year.

Usage:
    python3 fetch_kicker.py <url> [--browser <name>]
    python3 fetch_kicker.py --detect-browsers

Outputs raw HTML to stdout. Exits non-zero on failure.
"""

import glob
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time

_HOME = os.path.expanduser("~")

# (binary, display name, cookie glob or None for Chromium-based, pycookiecheat BrowserType name or None)
_BROWSER_DEFS = [
    ("zen-browser",          "Zen Browser",   f"{_HOME}/.zen/*/cookies.sqlite",           None),
    ("firefox",              "Firefox",        f"{_HOME}/.mozilla/firefox/*/cookies.sqlite", "FIREFOX"),
    ("librewolf",            "LibreWolf",      f"{_HOME}/.librewolf/*/cookies.sqlite",     None),
    ("waterfox",             "Waterfox",       f"{_HOME}/.waterfox/*/cookies.sqlite",      None),
    ("floorp",               "Floorp",         f"{_HOME}/.floorp/*/cookies.sqlite",        None),
    ("chromium",             "Chromium",       None,                                        "CHROMIUM"),
    ("google-chrome-stable", "Google Chrome",  None,                                        "CHROME"),
    ("brave-browser",        "Brave",          None,                                        "BRAVE"),
    ("brave-browser-beta",   "Brave Beta",     None,                                        "BRAVE"),
    ("brave-browser-nightly","Brave Nightly",  None,                                        "BRAVE"),
    ("vivaldi-stable",       "Vivaldi",        None,                                        "CHROMIUM"),
]

_BROWSERS = {b[0]: {"bin": b[0], "name": b[1], "cookie_glob": b[2], "pcc_type": b[3]} for b in _BROWSER_DEFS}
_KICKER_URL = "https://www.kicker.de/bundesliga/spieltag"
_COOKIE_REFRESH_WAIT = 15


def detect_installed_browsers():
    return [
        {"bin": b[0], "name": b[1]}
        for b in _BROWSER_DEFS
        if shutil.which(b[0])
    ]


def _read_cookie_from_db(db_path):
    fd, tmp = tempfile.mkstemp(suffix=".sqlite")
    os.close(fd)
    try:
        shutil.copy2(db_path, tmp)
        conn = sqlite3.connect(tmp)
        cur = conn.cursor()
        cur.execute(
            "SELECT value FROM moz_cookies "
            "WHERE name = 'datadome' AND host LIKE '%kicker%' "
            "ORDER BY expiry DESC LIMIT 1"
        )
        row = cur.fetchone()
        conn.close()
        return row[0] if row else None
    except (sqlite3.Error, OSError):
        return None
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def _scan_cookie_glob(pattern):
    for db_path in glob.glob(pattern):
        cookie = _read_cookie_from_db(db_path)
        if cookie:
            return cookie
    return None


def _read_cookie_pycookiecheat(pcc_type_name):
    """Read the datadome cookie using pycookiecheat (for Chromium-based browsers)."""
    try:
        from pycookiecheat import get_cookies, BrowserType
        browser_type = BrowserType[pcc_type_name]
        cookies = get_cookies(_KICKER_URL, browser=browser_type)
        return cookies.get("datadome")
    except Exception:
        return None


def find_datadome_cookie(browser=None):
    """Read the datadome cookie from a browser's cookie store.

    Tries Mozilla cookie DB first, then pycookiecheat for Chromium-based,
    then falls back to scanning all other browsers.
    """
    # Try the selected browser first
    if browser:
        if browser["cookie_glob"]:
            cookie = _scan_cookie_glob(browser["cookie_glob"])
            if cookie:
                return cookie
        if browser["pcc_type"]:
            cookie = _read_cookie_pycookiecheat(browser["pcc_type"])
            if cookie:
                return cookie

    # Fall back to all other browsers
    for b in _BROWSERS.values():
        if b is browser:
            continue
        if b["cookie_glob"]:
            cookie = _scan_cookie_glob(b["cookie_glob"])
            if cookie:
                return cookie
        if b["pcc_type"]:
            cookie = _read_cookie_pycookiecheat(b["pcc_type"])
            if cookie:
                return cookie
    return None


def _fetch(url, cookie):
    import primp

    r = primp.Client(impersonate="chrome_144", cookie_store=True).get(
        url, cookies={"datadome": cookie}
    )
    if r.status_code == 403 or "captcha-delivery.com" in r.text[:1000]:
        return None
    return r.text if r.status_code == 200 else None


def _refresh_cookie(browser):
    print(
        f"[soccerResults] Opening kicker.de in {browser['name']} to refresh cookie...",
        file=sys.stderr,
    )
    subprocess.Popen(
        [browser["bin"], _KICKER_URL],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + _COOKIE_REFRESH_WAIT
    while time.time() < deadline:
        time.sleep(1)
        cookie = find_datadome_cookie()
        if cookie:
            return cookie
    return None


def _resolve_browser(name):
    if name and name in _BROWSERS:
        return _BROWSERS[name]
    installed = detect_installed_browsers()
    return _BROWSERS[installed[0]["bin"]] if installed else None


def main():
    if "--detect-browsers" in sys.argv:
        print(json.dumps(detect_installed_browsers()))
        return

    if len(sys.argv) < 2:
        print("Usage: fetch_kicker.py <url> [--browser <name>]", file=sys.stderr)
        sys.exit(1)

    url = sys.argv[1]
    browser_name = None
    if "--browser" in sys.argv:
        idx = sys.argv.index("--browser")
        if idx + 1 < len(sys.argv):
            browser_name = sys.argv[idx + 1]

    browser = _resolve_browser(browser_name)
    if not browser:
        print("No supported browser found", file=sys.stderr)
        sys.exit(1)

    cookie = find_datadome_cookie(browser)
    html = _fetch(url, cookie) if cookie else None

    if not html:
        cookie = _refresh_cookie(browser)
        html = _fetch(url, cookie) if cookie else None

    if html:
        print(html)
    else:
        print("Failed to fetch page", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
