# Soccer Results

Live soccer scores, standings, and match details from [kicker.de](https://www.kicker.de) — as a DankMaterialShell desktop widget.

## Features

- **Live scores** with adaptive auto-refresh (60s during live play, configurable otherwise)
- **Today's matches** filtered by current date with status indicators
- **Matchday navigation** — browse past and future matchdays
- **Full standings table** with zone indicators (CL, EL, ECL, promotion, relegation)
- **Goal details** — expandable scorer list per match with minute and running score
- **Live mode** — scan all 8 leagues simultaneously for live matches
- **Pin a match** — track any match in the bar pill, even across league switches
- **Favorite team** — auto-scan all leagues for your team's live match
- **Match links** — open the kicker.de live ticker for any match

## Supported Leagues

| Code | League | Country |
|------|--------|---------|
| PL | Premier League | England |
| PD | La Liga | Spain |
| BL1 | Bundesliga | Germany |
| BL2 | 2. Bundesliga | Germany |
| BL3 | 3. Liga | Germany |
| SA | Serie A | Italy |
| FL1 | Ligue 1 | France |
| CL | Champions League | International |

Bundesliga leagues (BL1/BL2/BL3) get dedicated sub-tabs for quick switching between divisions.

## Bar Pill

The pill displays the highest-priority match:

1. **Pinned match** (always shown if set)
2. **Favorite team's live match** (auto-detected across all leagues)
3. **Soccer icon** (fallback when no match to display)

Layout: `[Home Crest] [Score] [Away Crest] | [Status]`

- Crests load from kicker.de match data
- Score shows kickoff time if upcoming, live score if in play, final score if finished
- Status suffix: match minute (e.g. `45'`), `HT` (half-time), or `FT` (full-time)
- Live matches use the primary accent color with a pulsing indicator

## Popout

### Today

Matches filtered to the current date. Shows upcoming kickoff times, live scores with minute indicators, and finished results.

### Matchday

Full matchday lineup with navigation to browse previous/next matchdays. Matches grouped by date with section headers.

### Table

Full league standings with zone-colored position indicators:

- **Green** — Champions League qualification / promotion
- **Gold** — Europa League, Conference League, promotion/relegation playoff
- **Red** — Direct relegation

Columns: Pos, Trend, Team, P, W-D-L, Goals, GD, Pts.

### Live Mode

Toggle to scan all 8 leagues for live matches at once. Results grouped by league with count badges. Uses a 2-minute cache between scans.

## Polling

| Condition | Interval |
|-----------|----------|
| Live match active (any league, pinned, or favorite) | 60s |
| Matches today but none live | Configurable (default 2 min) |
| No matches today | 15 min |

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| League | PL | Default league on startup |
| Favorite Team | — | Team name to auto-track across all leagues |
| Refresh Interval | 2 min | Minutes between auto-refreshes when no live match |
| Cookie Browser | Auto | Browser to read DataDome cookies from |

## Architecture

```
SoccerResults.qml    State management, process orchestration, bar pill
SoccerPopout.qml     Popout UI (tabs, league selector, live toggle)
SoccerApi.js         Shared helpers (URL builders, status checks, formatting)
MatchCard.qml        Individual match card with score, goals, pin, link
TeamDisplay.qml      Team crest + name component
StandingRow.qml      Standings table row with zone indicators
fetch_kicker.py      DataDome-aware HTML fetcher (primp + browser cookies)
parse_kicker.py      HTML parser (matches, goals, standings → JSON)
```

### Data Flow

```
Timer / user action
  → fetch_kicker.py  (HTTP with TLS impersonation + DataDome cookie)
  → parse_kicker.py  (HTML → JSON via stdin/stdout pipe)
  → SoccerApi.js     (sort, filter, format)
  → QML properties   → UI
```

### Process Orchestration

The plugin runs several independent fetch pipelines:

- **Page fetcher** — main league page (matches + standings), 30s min cache
- **Matchday fetcher** — specific matchday page, 10min cache
- **Standings fetcher** — dedicated standings endpoint
- **Goal fetcher** — sequential per-match goal details from `/schema` pages
- **Pinned fetcher** — keeps pinned match updated if it's in a different league
- **Favorite fetcher** — scans all leagues for favorite team (10min between full scans)
- **Live fetcher** — scans all leagues for live matches (2min cache)

Generation tracking prevents stale results from overwriting current data on league switches.

## Installation

```bash
# Clone into the DMS plugins directory
git clone https://github.com/hansibansix/soccerResults.git \
    ~/.config/DankMaterialShell/plugins/soccerResults

# Install Python dependencies
pip install primp pycookiecheat

# Visit kicker.de once in your browser to establish a DataDome cookie
# Then restart DMS
dms restart
```

The plugin auto-detects your installed browser for cookie access. To use a specific browser, set **Cookie Browser** in the plugin settings.

## Requirements

- Python 3.7+
- [primp](https://pypi.org/project/primp/) — TLS-impersonating HTTP client
- [pycookiecheat](https://pypi.org/project/pycookiecheat/) — browser cookie decryption (Chromium-based browsers)
- A supported browser with a kicker.de session (for DataDome cookie)

### Supported Browsers

| Browser | Cookie Method |
|---------|--------------|
| Zen Browser | SQLite |
| Firefox | SQLite + pycookiecheat |
| LibreWolf | SQLite |
| Waterfox | SQLite |
| Floorp | SQLite |
| Chromium | pycookiecheat |
| Google Chrome | pycookiecheat |
| Brave | pycookiecheat |
| Vivaldi | pycookiecheat |

Mozilla-based browsers store cookies in plain SQLite and are read directly. Chromium-based browsers encrypt their cookie store; `pycookiecheat` handles decryption via the system keyring.
