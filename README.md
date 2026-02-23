# Soccer Results

Live soccer scores, standings, and match details from [kicker.de](https://www.kicker.de).

## Features

- **Live scores** with auto-refresh (60s when live, configurable otherwise)
- **Today's matches** filtered by current date with status indicators
- **Matchday navigation** — browse past and future matchdays
- **Full standings table** with league zone indicators (CL/EL/ECL/relegation)
- **Goal details** — expandable scorer list per match
- **Live mode** — scan all leagues for live matches at once
- **Pin a match** — track any match across leagues in the bar pill
- **Favorite team** — auto-scan all leagues for your team's live match
- **Match links** — click to open the kicker.de ticker for any match

## Supported Leagues

| Code | League |
|------|--------|
| PL | Premier League |
| PD | La Liga |
| BL1 | Bundesliga |
| BL2 | 2. Bundesliga |
| BL3 | 3. Liga |
| SA | Serie A |
| FL1 | Ligue 1 |
| CL | Champions League |

## Settings

- **League** — default league to show on startup
- **Favorite Team** — team name to auto-track across all leagues
- **Refresh Interval** — minutes between auto-refreshes (default: 2)
- **Cookie Browser** — browser to read DataDome cookies from (auto-detected)

## Architecture

```
SoccerResults.qml    State management, process orchestration, bar pill
SoccerPopout.qml     Popout UI (tabs, league selector, live toggle)
SoccerApi.js         Shared helpers (URL builders, status checks, formatting)
MatchCard.qml        Individual match card with score, goals, pin, link
TeamDisplay.qml      Team crest + name component
StandingRow.qml      Standings table row with zone indicators
fetch_kicker.py      DataDome-aware HTML fetcher (primp + browser cookies)
parse_kicker.py      HTML parser (matches, goals, standings)
```

## Data Flow

```
Timer/user action
  -> fetch_kicker.py (HTTP with DataDome cookie)
  -> parse_kicker.py (HTML -> JSON via stdin/stdout)
  -> SoccerApi.js (sort, filter, group, format)
  -> QML properties -> UI
```

## Requirements

- Python 3.7+
- [primp](https://pypi.org/project/primp/) — TLS-impersonating HTTP client
- [pycookiecheat](https://pypi.org/project/pycookiecheat/) — browser cookie decryption
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

Mozilla-based browsers store cookies in plain SQLite and are read directly. Chromium-based browsers encrypt their cookie store; `pycookiecheat` handles decryption via the system keyring. Firefox supports both methods.
