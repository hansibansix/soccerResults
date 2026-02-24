#!/usr/bin/env python3
"""Fetch kicker.de pages, handling DataDome bot protection.

Uses curl_cffi (TLS-impersonating HTTP client) with a session that
automatically handles DataDome's cookie-based protection. On the first
request DataDome returns 403 + a Set-Cookie; the session captures it and
the second request succeeds.

Optionally reads a DataDome cookie from a browser's cookie store to
skip the initial 403 round-trip.

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
import sys
import tempfile

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
    """Read the datadome cookie from a browser's cookie store."""
    if browser:
        if browser["cookie_glob"]:
            cookie = _scan_cookie_glob(browser["cookie_glob"])
            if cookie:
                return cookie
        if browser["pcc_type"]:
            cookie = _read_cookie_pycookiecheat(browser["pcc_type"])
            if cookie:
                return cookie

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


def _is_valid_html(r):
    """Check if the response is a successful, non-captcha HTML page."""
    return (
        r.status_code == 200
        and "captcha-delivery.com" not in r.text[:1000]
    )


def _fetch(url, cookie=None):
    """Fetch a kicker.de URL, handling DataDome bot protection.

    Uses a curl_cffi session with TLS impersonation. If the first request
    gets a 403 (DataDome challenge), the session captures the Set-Cookie
    and retries automatically.

    A stale browser cookie poisons the session (DataDome rejects all
    subsequent requests), so the browser cookie attempt uses a separate
    session from the fresh fallback.
    """
    from curl_cffi import requests

    # Try with a browser cookie first (avoids the 403 round-trip)
    if cookie:
        session = requests.Session(impersonate="chrome")
        r = session.get(url, cookies={"datadome": cookie})
        if _is_valid_html(r):
            return r.text

    # Fresh session — first request seeds the datadome cookie via Set-Cookie
    session = requests.Session(impersonate="chrome")
    r = session.get(url)
    if _is_valid_html(r):
        return r.text

    # Retry — the session now has the datadome cookie from the 403
    if r.status_code == 403:
        r = session.get(url)
        if _is_valid_html(r):
            return r.text

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
    cookie = find_datadome_cookie(browser) if browser else None
    html = _fetch(url, cookie)

    if html:
        print(html)
    else:
        print("Failed to fetch page", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
