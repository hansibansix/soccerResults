.pragma library

var _baseUrl = "https://api.football-data.org/v4/competitions/";

var leagueNames = {
    "PL": "Premier League",
    "PD": "La Liga",
    "BL1": "Bundesliga",
    "SA": "Serie A",
    "FL1": "Ligue 1",
    "CL": "Champions League"
};

var _statusLabels = {
    "SCHEDULED": "Scheduled",
    "TIMED": "Scheduled",
    "IN_PLAY": "Live",
    "PAUSED": "Half Time",
    "FINISHED": "Full Time",
    "POSTPONED": "Postponed",
    "CANCELLED": "Cancelled",
    "SUSPENDED": "Suspended",
    "AWARDED": "Awarded"
};

function leagueName(code) {
    return leagueNames[code] || code;
}

function _pad2(n) { return ("0" + n).slice(-2); }

function todayDateString() {
    var d = new Date();
    return d.getFullYear() + "-" + _pad2(d.getMonth() + 1) + "-" + _pad2(d.getDate());
}

function buildMatchesUrl(leagueCode) {
    var today = todayDateString();
    return _baseUrl + leagueCode + "/matches?dateFrom=" + today + "&dateTo=" + today;
}

function buildMatchdayUrl(leagueCode, matchday) {
    return _baseUrl + leagueCode + "/matches?matchday=" + matchday;
}

function buildStandingsUrl(leagueCode) {
    return _baseUrl + leagueCode + "/standings";
}

function parseMatch(m) {
    return {
        id: m.id,
        status: m.status,
        homeTeam: m.homeTeam.shortName || m.homeTeam.name,
        awayTeam: m.awayTeam.shortName || m.awayTeam.name,
        homeCrest: m.homeTeam.crest || "",
        awayCrest: m.awayTeam.crest || "",
        homeScore: m.score.fullTime.home,
        awayScore: m.score.fullTime.away,
        halfHome: m.score.halfTime.home,
        halfAway: m.score.halfTime.away,
        minute: m.minute || null,
        utcDate: m.utcDate
    };
}

function _parseMatchList(resp) {
    if (!resp.matches) return [];
    var matches = [];
    for (var i = 0; i < resp.matches.length; i++)
        matches.push(parseMatch(resp.matches[i]));
    return sortMatches(matches);
}

function parseMatches(jsonString) {
    return _parseMatchList(JSON.parse(jsonString));
}

function parseMatchdayResponse(jsonString) {
    return { matches: _parseMatchList(JSON.parse(jsonString)) };
}

function parseStandings(jsonString) {
    var resp = JSON.parse(jsonString);
    var result = { standings: [], currentMatchday: 0, groups: [] };

    if (resp.season)
        result.currentMatchday = resp.season.currentMatchday || 0;

    if (!resp.standings) return result;

    for (var i = 0; i < resp.standings.length; i++) {
        var s = resp.standings[i];
        if (s.type !== "TOTAL") continue;

        var rows = [];
        for (var j = 0; j < s.table.length; j++) {
            var t = s.table[j];
            rows.push({
                position: t.position,
                team: t.team.shortName || t.team.name,
                tla: t.team.tla || "",
                played: t.playedGames,
                won: t.won,
                drawn: t.draw,
                lost: t.lost,
                gf: t.goalsFor,
                ga: t.goalsAgainst,
                gd: t.goalDifference,
                points: t.points,
                form: t.form || ""
            });
        }

        if (s.group)
            result.groups.push({ label: s.group, rows: rows });
        else
            result.standings = rows;
    }

    return result;
}

function sortMatches(matches) {
    var live = [], upcoming = [], finished = [], other = [];
    for (var i = 0; i < matches.length; i++) {
        var m = matches[i];
        if (isLive(m.status)) live.push(m);
        else if (isUpcoming(m.status)) upcoming.push(m);
        else if (isFinished(m.status)) finished.push(m);
        else other.push(m);
    }
    return live.concat(upcoming).concat(finished).concat(other);
}

function isLive(status) {
    return status === "IN_PLAY" || status === "PAUSED";
}

function isUpcoming(status) {
    return status === "SCHEDULED" || status === "TIMED";
}

function isFinished(status) {
    return status === "FINISHED";
}

function matchStatusLabel(status) {
    return _statusLabels[status] || status || "Unknown";
}

function estimateMinute(match) {
    if (!match || !match.utcDate) return "";
    if (match.status === "PAUSED") return "HT";
    if (match.status !== "IN_PLAY") return "";
    var elapsed = Math.floor((Date.now() - new Date(match.utcDate).getTime()) / 60000);
    if (elapsed < 0) return "";
    if (elapsed <= 45) return elapsed + "'";
    if (elapsed <= 60) return "HT";
    var secondHalf = elapsed - 15;
    return (secondHalf > 90 ? "90+" : secondHalf) + "'";
}

function formatKickoff(utcDateString) {
    if (!utcDateString) return "--";
    var d = new Date(utcDateString);
    return d.getHours() + ":" + _pad2(d.getMinutes());
}

function formatMatchDate(utcDateString) {
    if (!utcDateString) return "";
    var d = new Date(utcDateString);
    var months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
    var days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
    return days[d.getDay()] + " " + d.getDate() + " " + months[d.getMonth()];
}

function scoreText(match) {
    if (!match) return "--";
    if (isUpcoming(match.status)) return formatKickoff(match.utcDate);
    if (match.homeScore === null || match.awayScore === null) return "--";
    return match.homeScore + " - " + match.awayScore;
}

function pillText(match) {
    if (!match) return "";
    return abbreviate(match.homeTeam) + " " + scoreText(match) + " " + abbreviate(match.awayTeam);
}

function abbreviate(name) {
    if (!name) return "???";
    if (name.length <= 3) return name.toUpperCase();
    return name.substring(0, 3).toUpperCase();
}

function hasAnyLive(matches) {
    for (var i = 0; i < matches.length; i++) {
        if (isLive(matches[i].status)) return true;
    }
    return false;
}

// Group matches by date — returns flat array with header and match items
function groupByDate(matches) {
    if (!matches || matches.length === 0) return [];
    var result = [];
    var lastDate = "";
    for (var i = 0; i < matches.length; i++) {
        var m = matches[i];
        var dateStr = formatMatchDate(m.utcDate);
        if (dateStr !== lastDate) {
            result.push({ type: "header", dateLabel: dateStr });
            lastDate = dateStr;
        }
        var item = {};
        for (var k in m) item[k] = m[k];
        item.type = "match";
        result.push(item);
    }
    return result;
}

function findPillMatch(matches, pinnedId) {
    if (!matches || matches.length === 0) return null;
    if (pinnedId) {
        for (var i = 0; i < matches.length; i++)
            if (matches[i].id === pinnedId) return matches[i];
    }
    // Priority: live > upcoming > finished > first
    var checks = [isLive, isUpcoming, isFinished];
    for (var c = 0; c < checks.length; c++) {
        for (var j = 0; j < matches.length; j++)
            if (checks[c](matches[j].status)) return matches[j];
    }
    return matches[0];
}
