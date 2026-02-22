#!/usr/bin/env python3
"""Parse kicker.de spieltag HTML into JSON for the soccerResults plugin.

Reads HTML from stdin, writes JSON to stdout.
Uses only Python stdlib (html.parser, json, re).

Output format:
{
    "matchday": 23,
    "season": "2025-26",
    "matches": [...],
    "standings": [...]
}
"""

import sys
import re
import json
from html import unescape
from datetime import datetime, timezone, timedelta


def extract_qmconfig(html):
    """Extract matchday and season from the QMConfig JS object."""
    m = re.search(r'var QMConfig\s*=\s*\{(.*?)\}', html, re.DOTALL)
    if not m:
        return 0, ""
    config = m.group(1)
    spieltag = re.search(r'"Spieltag"\s*:\s*"(\d+)"', config)
    saison = re.search(r'"Saison"\s*:\s*"([^"]+)"', config)
    matchday = int(spieltag.group(1)) if spieltag else 0
    season = saison.group(1).replace("/", "-") if saison else ""
    return matchday, season


def extract_json_ld_events(html):
    """Extract SportsEvent JSON-LD blocks in page order."""
    blocks = re.findall(
        r'<script[^>]*type="application/ld\+json"[^>]*>\s*(\{.*?\})\s*</script>',
        html, re.DOTALL
    )
    events = []
    for block in blocks:
        try:
            data = json.loads(unescape(block))
            if data.get("@type") == "SportsEvent":
                events.append(data)
        except (json.JSONDecodeError, ValueError):
            pass
    return events


def parse_iso_date_to_utc(date_str):
    """Convert an ISO 8601 date string (with offset) to UTC ISO format."""
    if not date_str:
        return ""
    try:
        # Python 3.7+ handles timezone offsets in fromisoformat
        dt = datetime.fromisoformat(date_str)
        utc_dt = dt.astimezone(timezone.utc)
        return utc_dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    except (ValueError, AttributeError):
        return date_str


def extract_match_id(url):
    """Extract match slug from a kicker.de match URL path."""
    if not url:
        return ""
    # e.g. /mainz-gegen-hsv-2026-bundesliga-5050950/spielbericht -> mainz-gegen-hsv-2026-bundesliga-5050950
    url = url.strip("/")
    parts = url.rsplit("/", 1)
    return parts[0] if len(parts) > 1 else url


def extract_scores(row_html):
    """Extract full-time and half-time scores from a gameRow block."""
    # Check if this is a scheduled match (dateboard instead of scores)
    if "kick__dateboard" in row_html:
        return None, None, None, None

    # Extract all score values from scoreHolder divs
    scores = re.findall(
        r'scoreBoard__scoreHolder__score">\s*(\d+|-)\s*</div>',
        row_html
    )
    home_full = away_full = home_half = away_half = None

    if len(scores) >= 2:
        home_full = int(scores[0]) if scores[0] != "-" else None
        away_full = int(scores[1]) if scores[1] != "-" else None
    if len(scores) >= 4:
        home_half = int(scores[2]) if scores[2] != "-" else None
        away_half = int(scores[3]) if scores[3] != "-" else None

    return home_full, away_full, home_half, away_half


def extract_status(row_html):
    """Determine match status and live minute from stateCell."""
    # Pause indicator: used for halftime AND end-of-regulation pause
    if "indicator--pause" in row_html:
        minute_m = re.search(
            r'indicator--pause[^>]*>.*?<span>\s*(\d+)\'\s*</span>',
            row_html, re.DOTALL
        )
        minute = minute_m.group(1) if minute_m else None
        # Only treat as halftime if minute <= 45; otherwise it's a live pause (extra time etc.)
        if minute and int(minute) > 45:
            return "IN_PLAY", minute
        return "PAUSED", minute

    # Live match: indicator--live class with minute text
    if "indicator--live" in row_html:
        minute_m = re.search(
            r'indicator--live[^>]*>.*?<span>\s*(\d+)\'\s*</span>',
            row_html, re.DOTALL
        )
        if minute_m:
            return "IN_PLAY", minute_m.group(1)
        return "IN_PLAY", None

    # Live score holder (fallback for live matches without stateCell indicator)
    if "scoreBoard__scoreHolder--live" in row_html:
        return "IN_PLAY", None

    # Scheduled match: Spielinfo or dateboard
    if "icon-Spielinfo" in row_html or "kick__dateboard" in row_html:
        return "SCHEDULED", None

    # Finished match: Bericht, Schema, or Ergebnis
    status_text_m = re.search(
        r'stateCell__indicator--schema__txt">\s*(.*?)\s*</span>',
        row_html, re.DOTALL
    )
    if status_text_m:
        text = status_text_m.group(1).strip()
        if text in ("Bericht", "Schema", "Ergebnis", "Spielbericht"):
            return "FINISHED", None

    # If there are scores but no clear status, assume finished
    if re.search(r'scoreBoard__scoreHolder__score">\s*\d+\s*</div>', row_html):
        return "FINISHED", None

    return "SCHEDULED", None


def extract_logos(row_html):
    """Extract home and away team logo URLs from gameRow."""
    logos = re.findall(
        r'gameCell__team__logo.*?<img[^>]+src="([^"]+)"',
        row_html, re.DOTALL
    )
    home_crest = logos[0] if len(logos) >= 1 else ""
    away_crest = logos[1] if len(logos) >= 2 else ""
    return home_crest, away_crest


def extract_matchday_from_row(row_html):
    """Extract matchday from oddsServe data attribute."""
    m = re.search(r'data-matchday="(\d+)"', row_html)
    return int(m.group(1)) if m else 0


def extract_matches(html, json_ld_events, page_matchday):
    """Parse all match rows, correlating with JSON-LD event data."""
    # Split HTML at gameRow boundaries
    rows = re.split(r'<div class="kick__v100-gameList__gameRow">', html)
    rows = rows[1:]  # skip content before first gameRow

    matches = []
    event_idx = 0

    for row in rows:
        match = {
            "id": "",
            "status": "SCHEDULED",
            "matchday": 0,
            "homeTeam": "",
            "awayTeam": "",
            "homeCrest": "",
            "awayCrest": "",
            "homeScore": None,
            "awayScore": None,
            "halfHome": None,
            "halfAway": None,
            "minute": None,
            "utcDate": "",
        }

        # Correlate with JSON-LD event (they appear in the same order)
        if event_idx < len(json_ld_events):
            event = json_ld_events[event_idx]
            event_idx += 1
            match["homeTeam"] = unescape(event.get("homeTeam", {}).get("name", ""))
            match["awayTeam"] = unescape(event.get("awayTeam", {}).get("name", ""))
            match["utcDate"] = parse_iso_date_to_utc(event.get("startDate", ""))
            match["id"] = extract_match_id(event.get("url", ""))

        # Scores
        home_full, away_full, home_half, away_half = extract_scores(row)
        match["homeScore"] = home_full
        match["awayScore"] = away_full
        match["halfHome"] = home_half
        match["halfAway"] = away_half

        # Status and minute
        status, minute = extract_status(row)
        match["status"] = status
        match["minute"] = minute

        # Team logos
        home_crest, away_crest = extract_logos(row)
        match["homeCrest"] = home_crest
        match["awayCrest"] = away_crest

        # Matchday (from oddsServe, falling back to page-level QMConfig)
        match["matchday"] = extract_matchday_from_row(row) or page_matchday

        matches.append(match)

    return matches


def extract_standings(html):
    """Extract league standings from the ranking table.

    Handles both the compact sidebar table (7 columns) from /spieltag
    and the full table (11 columns) from /tabelle.
    """
    # Find the first ranking table (class contains kick__table--ranking)
    table_m = re.search(
        r'<table[^>]*class="[^"]*kick__table--ranking[^"]*"[^>]*>(.*?)</table>',
        html, re.DOTALL
    )
    if not table_m:
        return []

    table_html = table_m.group(1)
    standings = []

    rows = re.findall(r'<tr[^>]*>(.*?)</tr>', table_html, re.DOTALL)

    for row in rows:
        if '<th' in row:
            continue

        tds = re.findall(r'<td[^>]*>(.*?)</td>', row, re.DOTALL)
        if len(tds) < 7:
            continue

        position = extract_text(tds[0]).strip()
        if not position or not position.isdigit():
            continue

        # Detect full table (11 cols) vs compact sidebar (7 cols)
        is_full = len(tds) >= 11

        # Trend: td[1] icon class
        trend = ""
        trend_td = tds[1]
        if "DropUp" in trend_td:
            trend = "up"
        elif "DropDown" in trend_td:
            trend = "down"
        elif "DropNull" in trend_td:
            trend = "same"

        # Team logo: td[2] <img> src
        crest = ""
        img_m = re.search(r'<img[^>]+src="([^"]+)"', tds[2])
        if img_m:
            crest = img_m.group(1)

        team_name = extract_team_name(tds[3])

        if is_full:
            # Full /tabelle layout:
            # td[4]=Sp, td[5]=S (desktop) or S-U-N (mobile), td[6]=U, td[7]=N
            # td[8]=Tore, td[9]=Diff, td[10]=Punkte
            played = extract_text(tds[4]).strip()

            # W/D/L: try mobile "19-3-1" first, fall back to individual columns
            wdl_text = ""
            mobile_m = re.search(r'kick__table--show-mobile[^>]*>\s*(\d+-\d+-\d+)\s*<', tds[5])
            if mobile_m:
                wdl_text = mobile_m.group(1)
            won, drawn, lost = 0, 0, 0
            if wdl_text:
                parts = wdl_text.split("-")
                if len(parts) == 3:
                    won, drawn, lost = safe_int(parts[0]), safe_int(parts[1]), safe_int(parts[2])
            else:
                # Desktop columns
                desktop_m = re.search(r'kick__table--show-desktop[^>]*>\s*(\d+)\s*<', tds[5])
                won = safe_int(desktop_m.group(1)) if desktop_m else safe_int(extract_text(tds[5]))
                drawn = safe_int(extract_text(tds[6]))
                lost = safe_int(extract_text(tds[7]))

            # Goals: "85:21"
            goals_text = extract_text(tds[8]).strip()
            gf, ga = 0, 0
            if ":" in goals_text:
                gf_s, ga_s = goals_text.split(":", 1)
                gf, ga = safe_int(gf_s), safe_int(ga_s)

            gd = safe_int(extract_text(tds[9]).strip())
            points = safe_int(extract_text(tds[10]).strip())
        else:
            # Compact sidebar: td[4]=played, td[5]=diff, td[6]=points
            played = extract_text(tds[4]).strip()
            won, drawn, lost = 0, 0, 0
            gf, ga = 0, 0
            gd = safe_int(extract_text(tds[5]).strip())
            points = safe_int(extract_text(tds[6]).strip())

        standings.append({
            "position": int(position),
            "team": team_name,
            "crest": crest,
            "trend": trend,
            "played": safe_int(played),
            "won": won,
            "drawn": drawn,
            "lost": lost,
            "gf": gf,
            "ga": ga,
            "gd": gd,
            "points": points,
        })

    return standings


def extract_team_name(td_html):
    """Extract team name from a standings table td, preferring desktop variant."""
    # Look for desktop span first
    desktop_m = re.search(
        r'kick__table--show-desktop">\s*(.*?)\s*</span>',
        td_html, re.DOTALL
    )
    if desktop_m:
        return unescape(extract_text(desktop_m.group(1)))

    # Fall back to any link text
    link_m = re.search(r'<a[^>]*>(.*?)</a>', td_html, re.DOTALL)
    if link_m:
        return unescape(extract_text(link_m.group(1)))

    return unescape(extract_text(td_html))


def extract_text(html_fragment):
    """Strip all HTML tags and return plain text."""
    return re.sub(r'<[^>]+>', '', html_fragment).strip()


def safe_int(s):
    """Convert string to int, handling +/- prefixes and empty strings."""
    s = s.strip().lstrip("+")
    try:
        return int(s)
    except (ValueError, TypeError):
        return 0


def extract_goals(html):
    """Extract goal events from a match /schema page."""
    goals = []

    # Isolate the timeline section to avoid matching icons in footer/nav
    timeline_m = re.search(
        r'<div class="kick__game-timeline\s*"(.*?)(?=<div class="kick__v100|<section|<footer)',
        html, re.DOTALL
    )
    if not timeline_m:
        return goals
    timeline_html = timeline_m.group(0)

    # Find each event-icon block within the timeline.
    # Only match standalone Fussball icons (not inside icon-array stacks).
    for event_m in re.finditer(
        r'kick__game-timeline__event-icon\s+(kick__js_overlay-card-trigger\s+kick__game-timeline__event-icon--team-(top|bottom))'
        r'[^>]*data-overlay-id="([^"]+)"[^>]*>'
        r'<span\s+class="kick__ticker-icon[^"]*kick__icon-Fussball"',
        timeline_html
    ):
        side = "home" if event_m.group(2) == "top" else "away"
        overlay_id = event_m.group(3)

        # Find the overlay box content (appears later in the full HTML).
        # Each overlay ID has two instances (mobile + desktop); find the one with content.
        overlay_m = re.search(
            r'id="' + re.escape(overlay_id) + r'"[^>]*>'
            r'.*?overlay-box__header">(.*?)</div>'
            r'.*?overlay-box__content">(.*?)</p>',
            html, re.DOTALL
        )
        if not overlay_m:
            continue

        header = overlay_m.group(1)
        content_html = overlay_m.group(2)
        content_text = re.sub(r'<[^>]+>', ' ', content_html).strip()
        content_text = re.sub(r'\s+', ' ', content_text)

        # Must be a goal — overlay content starts with "Tor" or "Eigentor"
        if not re.match(r'(Tor|Eigentor)\s', content_text):
            continue

        # Extract minute from header: "21:22 - 42. Spielminute" or "90. + 3 Spielminute"
        minute_m = re.search(r'(\d+)\.\s*(?:\+\s*(\d+)\s*)?Spielminute', header)
        if minute_m:
            minute = minute_m.group(1)
            if minute_m.group(2):
                minute += "+" + minute_m.group(2)
        else:
            minute = ""

        # Extract player name from <a> tag
        player_m = re.search(r'<a[^>]*>([^<]+)</a>', content_html)
        player = player_m.group(1).strip() if player_m else ""

        # Extract running score: "Tor 1:0" or "Eigentor 2:1"
        score_m = re.search(r'(?:Tor|Eigentor)\s+(\d+:\d+)', content_text)
        score = score_m.group(1) if score_m else ""

        if minute or player:
            goals.append({
                "minute": minute,
                "player": player,
                "score": score,
                "side": side,
            })

    return goals


def main_goals():
    """Parse a match /schema page for goal events."""
    html = sys.stdin.read()

    if not html or len(html) < 200:
        json.dump({"goals": []}, sys.stdout)
        return

    if "<title>403" in html or "<title>404" in html or "Access Denied" in html:
        json.dump({"goals": []}, sys.stdout)
        return

    try:
        goals = extract_goals(html)
        json.dump({"goals": goals}, sys.stdout, ensure_ascii=False)
    except Exception as e:
        json.dump({"goals": [], "error": "Parse error: " + str(e)}, sys.stdout)


def main():
    html = sys.stdin.read()

    if not html or len(html) < 500:
        json.dump({"error": "Empty or invalid response from kicker.de"}, sys.stdout)
        return

    # Check for common error indicators
    if "<title>403" in html or "<title>404" in html or "Access Denied" in html:
        json.dump({"error": "kicker.de returned an error page"}, sys.stdout)
        return

    try:
        matchday, season = extract_qmconfig(html)
        json_ld_events = extract_json_ld_events(html)
        matches = extract_matches(html, json_ld_events, matchday)
        standings = extract_standings(html)

        result = {
            "matchday": matchday,
            "season": season,
            "matches": matches,
            "standings": standings,
        }

        json.dump(result, sys.stdout, ensure_ascii=False)

    except Exception as e:
        json.dump({"error": "Parse error: " + str(e)}, sys.stdout)


def main_standings():
    """Parse a /tabelle page for standings only."""
    html = sys.stdin.read()

    if not html or len(html) < 500:
        json.dump({"standings": []}, sys.stdout)
        return

    if "<title>403" in html or "<title>404" in html or "Access Denied" in html:
        json.dump({"standings": []}, sys.stdout)
        return

    try:
        standings = extract_standings(html)
        json.dump({"standings": standings}, sys.stdout, ensure_ascii=False)
    except Exception as e:
        json.dump({"standings": [], "error": "Parse error: " + str(e)}, sys.stdout)


if __name__ == "__main__":
    if "--goals" in sys.argv:
        main_goals()
    elif "--standings" in sys.argv:
        main_standings()
    else:
        main()
