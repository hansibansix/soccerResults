.pragma library

var _kickerBase = "https://www.kicker.de/";

var leagueMap = {
    "PL":  { slug: "premier-league",   name: "Premier League" },
    "PD":  { slug: "la-liga",          name: "La Liga" },
    "BL1": { slug: "bundesliga",       name: "Bundesliga" },
    "BL2": { slug: "2-bundesliga",     name: "2. Bundesliga" },
    "BL3": { slug: "3-liga",           name: "3. Liga" },
    "SA":  { slug: "serie-a",          name: "Serie A" },
    "FL1": { slug: "ligue-1",          name: "Ligue 1" },
    "CL":  { slug: "champions-league", name: "Champions League" }
};

var bundesligaCodes = ["BL1", "BL2", "BL3"];

function isBundesliga(code) {
    return bundesligaCodes.indexOf(code) >= 0;
}

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
    var entry = leagueMap[code];
    return entry ? entry.name : code;
}

function buildPageUrl(leagueCode) {
    var entry = leagueMap[leagueCode];
    if (!entry) return "";
    return _kickerBase + entry.slug + "/spieltag";
}

function buildMatchGoalsUrl(matchId) {
    if (!matchId) return "";
    return _kickerBase + matchId + "/schema";
}

function buildMatchdayPageUrl(leagueCode, season, matchday) {
    var entry = leagueMap[leagueCode];
    if (!entry) return "";
    return _kickerBase + entry.slug + "/spieltag/" + season + "/" + matchday;
}

function parsePageData(data) {
    if (data.error)
        return { error: data.error };

    return {
        matches: sortMatches(data.matches || []),
        standings: data.standings || [],
        matchday: data.matchday || 0,
        season: data.season || ""
    };
}

function _pad2(n) { return ("0" + n).slice(-2); }

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

function filterToday(matches) {
    if (!matches || matches.length === 0) return [];
    var now = new Date();
    var todayStr = now.getFullYear() + "-" + _pad2(now.getMonth() + 1) + "-" + _pad2(now.getDate());
    var result = [];
    for (var i = 0; i < matches.length; i++) {
        var m = matches[i];
        if (!m.utcDate) continue;
        var matchDate = new Date(m.utcDate);
        var localStr = matchDate.getFullYear() + "-" + _pad2(matchDate.getMonth() + 1) + "-" + _pad2(matchDate.getDate());
        if (localStr === todayStr) result.push(m);
    }
    return result;
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
    var text = abbreviate(match.homeTeam) + " " + scoreText(match) + " " + abbreviate(match.awayTeam);
    if (match.status === "PAUSED")
        text += " HT";
    else if (isLive(match.status) && match.minute)
        text += " " + match.minute + "'";
    else if (isFinished(match.status))
        text += " FT";
    return text;
}

function pillSuffix(match) {
    if (!match) return "";
    if (match.status === "PAUSED") return "HT";
    if (isLive(match.status) && match.minute) return match.minute + "'";
    if (isFinished(match.status)) return "FT";
    return "";
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

function findFavoriteTeamMatch(matches, teamName) {
    if (!matches || !teamName) return null;
    var needle = teamName.toLowerCase();
    for (var i = 0; i < matches.length; i++) {
        var m = matches[i];
        if ((m.homeTeam && m.homeTeam.toLowerCase().indexOf(needle) >= 0) ||
            (m.awayTeam && m.awayTeam.toLowerCase().indexOf(needle) >= 0))
            return m;
    }
    return null;
}

function findPillMatch(pinnedData, favoriteData) {
    // Pinned match always wins if available
    if (pinnedData && pinnedData.id) return pinnedData;
    // Favorite team's live match takes second priority
    if (favoriteData && favoriteData.id && isLive(favoriteData.status)) return favoriteData;
    // No pinned or favorite-live — show icon only
    return null;
}
