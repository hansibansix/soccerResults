import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "SoccerApi.js" as Api

PluginComponent {
    id: root
    layerNamespacePlugin: "soccer-results"
    popoutWidth: 420
    popoutHeight: 600

    // === Settings (read-only from pluginData) ===
    readonly property string apiKey: pluginData.apiKey || ""
    readonly property int refreshIntervalMinutes: parseInt(pluginData.refreshInterval) || 2
    readonly property string defaultLeague: pluginData.league || "PL"

    // === Active league (runtime, changeable from popout) ===
    property string activeLeague: ""

    // === Tab state ===
    property int currentTab: 0  // 0=Today, 1=Matchday, 2=Table

    // === Today's matches state ===
    property var matches: []
    property bool loading: false
    property string errorMessage: ""
    property string lastUpdated: ""
    property bool hasLive: false

    // === Matchday state ===
    property var matchdayMatches: []
    property int currentMatchday: 0
    property bool matchdayLoading: false
    property string matchdayError: ""

    // === Standings state ===
    property var standings: []
    property var standingsGroups: []
    property bool standingsLoading: false
    property string standingsError: ""

    // === Pinned match ===
    property int pinnedMatchId: 0

    // === Rate limit / caching ===
    property real _lastMatchFetch: 0
    property real _lastStandingsFetch: 0
    property real _lastMatchdayFetch: 0
    property bool _rateLimited: false
    readonly property int _minFetchIntervalMs: 30000          // 30s min between same-endpoint fetches
    readonly property int _standingsCacheMs: 1800000          // 30min — standings change ~weekly
    readonly property int _matchdayCacheMs: 600000            // 10min — matchday changes slowly
    readonly property int _rateLimitBackoffMs: 120000         // 2min backoff after 429

    // === Pill helpers ===
    readonly property var pillMatch: Api.findPillMatch(matches, pinnedMatchId)
    readonly property bool pillLive: pillMatch ? Api.isLive(pillMatch.status) : false

    // === Helpers ===
    function _now() { return Date.now(); }

    function _canFetch(lastFetch, cacheMs) {
        if (_rateLimited) return false;
        return (_now() - lastFetch) >= Math.max(cacheMs, _minFetchIntervalMs);
    }

    function _resetAllData() {
        matches = [];
        matchdayMatches = [];
        standings = [];
        standingsGroups = [];
        currentMatchday = 0;
        errorMessage = "";
        matchdayError = "";
        standingsError = "";
        lastUpdated = "";
        _lastMatchFetch = 0;
        _lastStandingsFetch = 0;
        _lastMatchdayFetch = 0;
    }

    function _buildCurlCommand(url) {
        return [
            "curl", "-sS", "--connect-timeout", "10", "--max-time", "15",
            "-w", "\nHTTP_STATUS:%{http_code}",
            "-H", "X-Auth-Token: " + apiKey,
            url
        ];
    }

    function _parseApiResponse(raw, exitCode) {
        var idx = raw.lastIndexOf("HTTP_STATUS:");
        var httpCode = idx >= 0 ? parseInt(raw.substring(idx + 12)) : 0;
        var body = idx >= 0 ? raw.substring(0, idx) : raw;

        if (exitCode !== 0 || !body)
            return { error: "Failed to fetch data" };
        if (httpCode === 401 || httpCode === 403)
            return { error: "Invalid API key" };
        if (httpCode === 429) {
            _rateLimited = true;
            rateLimitTimer.restart();
            return { error: "Rate limited — retrying in 2min" };
        }
        if (httpCode >= 400)
            return { error: "API error (HTTP " + httpCode + ")" };

        _rateLimited = false;
        return { body: body, error: null };
    }

    function _handleFetchResult(fetcher, exitCode, onSuccess, onError) {
        var parsed = _parseApiResponse(fetcher.output, exitCode);
        fetcher.output = "";
        if (parsed.error) { onError(parsed.error); return; }
        try {
            onSuccess(parsed.body);
        } catch (e) {
            console.warn("[soccerResults] Parse error: " + e);
            onError("Failed to parse data");
        }
    }

    function _updateTimestamp() {
        var now = new Date();
        lastUpdated = ("0" + now.getHours()).slice(-2) + ":" +
                      ("0" + now.getMinutes()).slice(-2);
    }

    function switchLeague(code) {
        if (code === activeLeague) return;
        activeLeague = code;
        pinnedMatchId = 0;
        _resetAllData();
        fetchMatches(true);
        fetchStandings(true);
    }

    // === Fetch: today's matches ===
    Process {
        id: matchFetcher
        property string output: ""
        stdout: SplitParser { onRead: line => { matchFetcher.output += line; } }

        onExited: (exitCode) => {
            root.loading = false;
            root._handleFetchResult(matchFetcher, exitCode, function(body) {
                var result = Api.parseMatches(body);
                root.matches = result;
                root.hasLive = Api.hasAnyLive(result);
                root.errorMessage = "";
                root._updateTimestamp();
                // Derive matchday from today's matches (most accurate)
                var md = Api.extractMatchday(result);
                if (md > 0) root.currentMatchday = md;
                else if (root.currentMatchday === 0) root.fetchUpcomingMatchday();
            }, function(err) { root.errorMessage = err; });
        }
    }

    function fetchMatches(force) {
        if (!apiKey) { errorMessage = "Set API key in settings"; return; }
        if (!activeLeague || matchFetcher.running) return;
        if (!force && !_canFetch(_lastMatchFetch, _minFetchIntervalMs)) return;

        loading = true;
        _lastMatchFetch = _now();
        matchFetcher.output = "";
        matchFetcher.command = _buildCurlCommand(Api.buildMatchesUrl(activeLeague));
        matchFetcher.running = true;
    }

    // === Fetch: matchday matches ===
    Process {
        id: matchdayFetcher
        property string output: ""
        stdout: SplitParser { onRead: line => { matchdayFetcher.output += line; } }

        onExited: (exitCode) => {
            root.matchdayLoading = false;
            root._handleFetchResult(matchdayFetcher, exitCode, function(body) {
                root.matchdayMatches = Api.parseMatchdayResponse(body).matches;
                root.matchdayError = "";
            }, function(err) { root.matchdayError = err; });
        }
    }

    function fetchMatchday(force) {
        if (!apiKey || !activeLeague || currentMatchday <= 0) return;
        if (matchdayFetcher.running) return;
        if (!force && !_canFetch(_lastMatchdayFetch, _matchdayCacheMs)) return;

        matchdayLoading = true;
        _lastMatchdayFetch = _now();
        matchdayFetcher.output = "";
        matchdayFetcher.command = _buildCurlCommand(Api.buildMatchdayUrl(activeLeague, currentMatchday));
        matchdayFetcher.running = true;
    }

    // === Fetch: standings ===
    Process {
        id: standingsFetcher
        property string output: ""
        stdout: SplitParser { onRead: line => { standingsFetcher.output += line; } }

        onExited: (exitCode) => {
            root.standingsLoading = false;
            root._handleFetchResult(standingsFetcher, exitCode, function(body) {
                var result = Api.parseStandings(body);
                root.standings = result.standings;
                root.standingsGroups = result.groups;
                root.standingsError = "";
            }, function(err) { root.standingsError = err; });
        }
    }

    function fetchStandings(force) {
        if (!apiKey || !activeLeague) return;
        if (standingsFetcher.running) return;
        if (!force && !_canFetch(_lastStandingsFetch, _standingsCacheMs)) return;

        standingsLoading = true;
        _lastStandingsFetch = _now();
        standingsFetcher.output = "";
        standingsFetcher.command = _buildCurlCommand(Api.buildStandingsUrl(activeLeague));
        standingsFetcher.running = true;
    }

    // === Fetch: upcoming matchday (lightweight, resolves correct matchday number) ===
    Process {
        id: upcomingFetcher
        property string output: ""
        stdout: SplitParser { onRead: line => { upcomingFetcher.output += line; } }

        onExited: (exitCode) => {
            root._handleFetchResult(upcomingFetcher, exitCode, function(body) {
                var md = Api.parseUpcomingMatchday(body);
                if (md > 0) root.currentMatchday = md;
            }, function(err) { /* silent — matchday tab will show error if needed */ });
        }
    }

    function fetchUpcomingMatchday() {
        if (!apiKey || !activeLeague || upcomingFetcher.running) return;
        if (currentMatchday > 0) return; // already resolved
        upcomingFetcher.output = "";
        upcomingFetcher.command = _buildCurlCommand(Api.buildUpcomingUrl(activeLeague));
        upcomingFetcher.running = true;
    }

    // === Polling timer ===
    Timer {
        id: pollTimer
        // Live: 60s, has matches: 5min, no matches: 15min
        interval: {
            if (root.hasLive) return 60000;
            if (root.matches.length > 0) return Math.max(root.refreshIntervalMinutes * 60 * 1000, 180000);
            return 900000; // 15min when no matches today
        }
        running: root.apiKey !== "" && root.activeLeague !== "" && !root._rateLimited
        repeat: true
        onTriggered: {
            // Always refresh today's matches
            root.fetchMatches();
            // Only refresh standings/matchday when their tab is active
            if (root.currentTab === 2) root.fetchStandings();
            if (root.currentTab === 1) root.fetchMatchday();
        }
    }

    // === Rate limit backoff timer ===
    Timer {
        id: rateLimitTimer
        interval: root._rateLimitBackoffMs
        repeat: false
        onTriggered: {
            root._rateLimited = false;
            console.log("[soccerResults] Rate limit backoff expired, resuming fetches");
            root.fetchMatches(true);
        }
    }

    // === Lazy fetch on tab change ===
    onCurrentTabChanged: {
        if (currentTab === 1) {
            if (currentMatchday === 0) fetchUpcomingMatchday();
            else if (matchdayMatches.length === 0) fetchMatchday(true);
        }
        if (currentTab === 2 && standings.length === 0 && standingsGroups.length === 0) {
            fetchStandings(true);
        }
    }

    // When matchday is resolved, auto-fetch if the matchday tab is active
    onCurrentMatchdayChanged: {
        if (currentMatchday > 0 && currentTab === 1 && matchdayMatches.length === 0)
            fetchMatchday(true);
    }

    // === React to API key changes from settings ===
    onApiKeyChanged: {
        if (apiKey && activeLeague) {
            _resetAllData();
            fetchMatches(true);
            fetchStandings(true);
        }
    }

    // === Init: set activeLeague from settings default ===
    Component.onCompleted: {
        activeLeague = defaultLeague;
        if (apiKey) {
            fetchMatches(true);
            // Standings needed for currentMatchday; matchday deferred until tab opened
            fetchStandings(true);
        }
    }

    // === Widget properties ===
    ccWidgetIcon: "sports_soccer"
    ccWidgetPrimaryText: Api.leagueName(activeLeague)
    ccWidgetSecondaryText: {
        if (!apiKey) return "Set API key";
        if (loading && matches.length === 0) return "Loading...";
        if (errorMessage) return errorMessage;
        if (pillMatch) return Api.pillText(pillMatch);
        return "No matches today";
    }
    ccWidgetIsActive: matches.length > 0

    // === Bar pills ===
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            Image {
                source: root.pillMatch ? root.pillMatch.homeCrest || "" : ""
                sourceSize.width: root.iconSize
                sourceSize.height: root.iconSize
                width: root.iconSize
                height: root.iconSize
                fillMode: Image.PreserveAspectFit
                visible: source !== ""
                anchors.verticalCenter: parent.verticalCenter
            }

            DankIcon {
                name: "sports_soccer"
                size: root.iconSize
                color: root.pillLive ? Theme.primary : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.pillMatch || !root.pillMatch.homeCrest
            }

            StyledText {
                text: root.pillMatch ? Api.scoreText(root.pillMatch) : (root.errorMessage || "--")
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale)
                font.weight: root.pillLive ? Font.Bold : Font.Normal
                color: root.pillLive ? Theme.primary : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            Image {
                source: root.pillMatch ? root.pillMatch.awayCrest || "" : ""
                sourceSize.width: root.iconSize
                sourceSize.height: root.iconSize
                width: root.iconSize
                height: root.iconSize
                fillMode: Image.PreserveAspectFit
                visible: source !== ""
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 2

            Image {
                source: root.pillMatch ? root.pillMatch.homeCrest || "" : ""
                sourceSize.width: root.iconSize
                sourceSize.height: root.iconSize
                width: root.iconSize
                height: root.iconSize
                fillMode: Image.PreserveAspectFit
                visible: source !== ""
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.pillMatch ? Api.scoreText(root.pillMatch) : "--"
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale)
                font.weight: root.pillLive ? Font.Bold : Font.Normal
                color: root.pillLive ? Theme.primary : Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Image {
                source: root.pillMatch ? root.pillMatch.awayCrest || "" : ""
                sourceSize.width: root.iconSize
                sourceSize.height: root.iconSize
                width: root.iconSize
                height: root.iconSize
                fillMode: Image.PreserveAspectFit
                visible: source !== ""
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // === Popout ===
    popoutContent: Component {
        SoccerPopout {
            matches: root.matches
            matchdayMatches: root.matchdayMatches
            currentMatchday: root.currentMatchday
            standings: root.standings
            standingsGroups: root.standingsGroups
            activeLeague: root.activeLeague
            currentTab: root.currentTab
            pinnedMatchId: root.pinnedMatchId

            loading: root.loading
            matchdayLoading: root.matchdayLoading
            standingsLoading: root.standingsLoading

            errorMessage: root.errorMessage
            matchdayError: root.matchdayError
            standingsError: root.standingsError

            lastUpdated: root.lastUpdated

            onRefreshRequested: {
                root.fetchMatches(true);
                root.fetchStandings(true);
                if (root.currentMatchday > 0) root.fetchMatchday(true);
            }
            onLeagueSelected: function(code) { root.switchLeague(code); }
            onTabChanged: function(tab) { root.currentTab = tab; }
            onMatchPinned: function(matchId) {
                root.pinnedMatchId = (root.pinnedMatchId === matchId) ? 0 : matchId;
            }
        }
    }
}
