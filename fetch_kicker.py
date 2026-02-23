#!/usr/bin/env python3
"""Fetch kicker.de pages, handling DataDome bot protection.

Uses primp (TLS-impersonating HTTP client) with a DataDome cookie read from
a browser's cookie store. The cookie is set automatically when you visit
kicker.de in the browser and lasts ~1 year.

Usage:
    python3 fetch_kicker.py <url> [--browser <name>]
    python3 fetch_kicker.py --detect-browsers

Outputs raw HTML to stdout. Exits non-zero on failure.
"""

import json
import sys
import os
import glob
import shutil
import sqlite3
import subprocess
import tempfile
import time

# Browser definitions: binary name, display name, cookie glob patterns
BROWSERS = [
    {
        "bin": "zen-browser",
        "name": "Zen Browser",
        "cookie_globs": [os.path.expanduser("~/.zen/*/cookies.sqlite")],
    },
    {
        "bin": "firefox",
        "name": "Firefox",
        "cookie_globs": [os.path.expanduser("~/.mozilla/firefox/*/cookies.sqlite")],
    },
    {
        "bin": "librewolf",
        "name": "LibreWolf",
        "cookie_globs": [os.path.expanduser("~/.librewolf/*/cookies.sqlite")],
    },
    {
        "bin": "waterfox",
        "name": "Waterfox",
        "cookie_globs": [os.path.expanduser("~/.waterfox/*/cookies.sqlite")],
    },
    {
        "bin": "floorp",
        "name": "Floorp",
        "cookie_globs": [os.path.expanduser("~/.floorp/*/cookies.sqlite")],
    },
    {
        "bin": "chromium",
        "name": "Chromium",
        "cookie_globs": [os.path.expanduser("~/.config/chromium/*/Cookies")],
    },
    {
        "bin": "google-chrome-stable",
        "name": "Google Chrome",
        "cookie_globs": [os.path.expanduser("~/.config/google-chrome/*/Cookies")],
    },
    {
        "bin": "brave-browser",
        "name": "Brave",
        "cookie_globs": [os.path.expanduser("~/.config/BraveSoftware/Brave-Browser/*/Cookies")],
    },
    {
        "bin": "vivaldi-stable",
        "name": "Vivaldi",
        "cookie_globs": [os.path.expanduser("~/.config/vivaldi/*/Cookies")],
    },
]

KICKER_URL = "https://www.kicker.de/bundesliga/spieltag"
COOKIE_REFRESH_WAIT = 15
COOKIE_POLL_INTERVAL = 1


def detect_installed_browsers():
    """Return list of installed browsers with their binary and display name."""
    installed = []
    for browser in BROWSERS:
        if shutil.which(browser["bin"]):
            installed.append({"bin": browser["bin"], "name": browser["name"]})
    return installed


def get_browser(name):
    """Look up a browser by binary name."""
    for browser in BROWSERS:
        if browser["bin"] == name:
            return browser
    return None


def find_datadome_cookie(browser):
    """Read the datadome cookie for kicker.de from a browser's cookie store."""
    for pattern in browser["cookie_globs"]:
        for db_path in glob.glob(pattern):
            cookie = _read_cookie_from_db(db_path)
            if cookie:
                return cookie
    return None


def _read_cookie_from_db(db_path):
    """Extract datadome cookie from a Mozilla cookies.sqlite file."""
    tmp = tempfile.mktemp(suffix=".sqlite")
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


def fetch_with_primp(url, cookie):
    """Fast fetch using primp with TLS impersonation + DataDome cookie."""
    import primp

    client = primp.Client(impersonate="chrome_144", cookie_store=True)
    r = client.get(url, cookies={"datadome": cookie})
    if r.status_code == 403 or "captcha-delivery.com" in r.text[:1000]:
        return None
    if r.status_code != 200:
        return None
    return r.text


def refresh_cookie(browser):
    """Open kicker.de in the browser to refresh the DataDome cookie.

    Opens a tab, waits for the cookie to appear, then returns it.
    """
    print(
        f"[soccerResults] Opening kicker.de in {browser['name']} to refresh cookie...",
        file=sys.stderr,
    )
    subprocess.Popen(
        [browser["bin"], KICKER_URL],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + COOKIE_REFRESH_WAIT
    while time.time() < deadline:
        time.sleep(COOKIE_POLL_INTERVAL)
        cookie = find_datadome_cookie(browser)
        if cookie:
            return cookie
    return None


def main():
    # --detect-browsers: output JSON list of installed browsers
    if "--detect-browsers" in sys.argv:
        print(json.dumps(detect_installed_browsers()))
        return

    if len(sys.argv) < 2:
        print("Usage: fetch_kicker.py <url> [--browser <name>]", file=sys.stderr)
        sys.exit(1)

    url = sys.argv[1]

    # Parse --browser flag
    browser_bin = None
    if "--browser" in sys.argv:
        idx = sys.argv.index("--browser")
        if idx + 1 < len(sys.argv):
            browser_bin = sys.argv[idx + 1]

    # Resolve browser
    browser = get_browser(browser_bin) if browser_bin else None
    if not browser:
        # Fall back to first installed browser
        installed = detect_installed_browsers()
        if installed:
            browser = get_browser(installed[0]["bin"])
    if not browser:
        print("No supported browser found", file=sys.stderr)
        sys.exit(1)

    cookie = find_datadome_cookie(browser)

    # Try fetch with existing cookie
    if cookie:
        html = fetch_with_primp(url, cookie)
        if html and len(html) > 500:
            print(html)
            return

    # Cookie missing or expired — open browser to refresh it
    cookie = refresh_cookie(browser)
    if cookie:
        html = fetch_with_primp(url, cookie)
        if html and len(html) > 500:
            print(html)
            return

    print("Failed to fetch page after cookie refresh", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
