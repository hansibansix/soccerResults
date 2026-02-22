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
    readonly property int refreshIntervalMinutes: parseInt(pluginData.refreshInterval) || 2
    readonly property string defaultLeague: pluginData.league || ""

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
    property string _season: ""
    property bool matchdayLoading: false
    property string matchdayError: ""

    // === Standings state ===
    property var standings: []
    property var standingsGroups: []
    property bool standingsLoading: false
    property string standingsError: ""

    // === Pinned match ===
    property string pinnedMatchId: ""

    // === Goal data ===
    property var _goalQueue: []
    property var _matchGoals: ({})
    property string _currentGoalMatchId: ""

    // === Rate limit / caching ===
    property real _lastPageFetch: 0
    property real _lastMatchdayFetch: 0
    readonly property int _minFetchIntervalMs: 30000          // 30s min between same-endpoint fetches
    readonly property int _matchdayCacheMs: 600000            // 10min — matchday changes slowly

    // === Script path ===
    readonly property string _scriptPath: Qt.resolvedUrl("parse_kicker.py").toString().replace("file://", "")

    // === Pill helpers ===
    readonly property var pillMatch: Api.findPillMatch(matches, matchdayMatches, pinnedMatchId)
    readonly property bool pillLive: pillMatch ? Api.isLive(pillMatch.status) : false

    // === Helpers ===
    function _now() { return Date.now(); }

    function _canFetch(lastFetch, cacheMs) {
        return (_now() - lastFetch) >= Math.max(cacheMs, _minFetchIntervalMs);
    }

    function _resetAllData() {
        matches = [];
        matchdayMatches = [];
        standings = [];
        standingsGroups = [];
        currentMatchday = 0;
        _season = "";
        errorMessage = "";
        matchdayError = "";
        standingsError = "";
        lastUpdated = "";
        _lastPageFetch = 0;
        _lastMatchdayFetch = 0;
        _goalQueue = [];
        _matchGoals = {};
        _currentGoalMatchId = "";
    }

    function _enqueueGoalFetches(matchList, liveOnly) {
        var queue = [];
        for (var i = 0; i < matchList.length; i++) {
            var m = matchList[i];
            if (!m.id) continue;
            if (liveOnly) {
                if (Api.isLive(m.status)) queue.push(m.id);
            } else {
                if (Api.isFinished(m.status) || Api.isLive(m.status)) queue.push(m.id);
            }
        }
        _goalQueue = queue;
        _fetchNextGoal();
    }

    function _fetchNextGoal() {
        if (goalFetcher.running || _goalQueue.length === 0) return;
        var matchId = _goalQueue[0];
        _goalQueue = _goalQueue.slice(1);
        _currentGoalMatchId = matchId;
        var url = Api.buildMatchGoalsUrl(matchId);
        goalFetcher.output = "";
        goalFetcher.command = _buildGoalsFetchCommand(url);
        goalFetcher.running = true;
    }

    function getMatchGoals(matchId) {
        return _matchGoals[matchId] || [];
    }

    function _buildFetchCommand(url) {
        return ["bash", "-c", "curl -sS --connect-timeout 10 --max-time 15 '" + url + "' | python3 '" + _scriptPath + "'"];
    }

    function _buildGoalsFetchCommand(url) {
        return ["bash", "-c", "curl -sS --connect-timeout 10 --max-time 15 '" + url + "' | python3 '" + _scriptPath + "' --goals"];
    }

    function _parseResponse(output) {
        if (!output || output.trim() === "")
            return { error: "No response" };
        try {
            return JSON.parse(output);
        } catch (e) {
            return { error: "Failed to parse response" };
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
        pinnedMatchId = "";
        _resetAllData();
        fetchPage(true);
    }

    // === Fetch: main page (matches + standings + matchday) ===
    Process {
        id: pageFetcher
        property string output: ""
        stdout: SplitParser { onRead: line => { pageFetcher.output += line + "\n"; } }

        onExited: (exitCode) => {
            root.loading = false;
            root.standingsLoading = false;

            if (exitCode !== 0 && !pageFetcher.output.trim()) {
                root.errorMessage = "Failed to fetch data";
                pageFetcher.output = "";
                return;
            }

            var data = root._parseResponse(pageFetcher.output);
            pageFetcher.output = "";

            if (data.error) {
                root.errorMessage = data.error;
                return;
            }

            try {
                var result = Api.parsePageData(JSON.stringify(data));
                if (result.error) {
                    root.errorMessage = result.error;
                    return;
                }

                root.matches = result.matches;
                root.hasLive = Api.hasAnyLive(result.matches);
                root.standings = result.standings;
                root.standingsGroups = [];
                root.errorMessage = "";
                root.standingsError = "";
                root._updateTimestamp();

                if (result.matchday > 0) root.currentMatchday = result.matchday;
                if (result.season) root._season = result.season;

                // Enqueue goal fetches for finished + live matches
                root._enqueueGoalFetches(result.matches, false);
            } catch (e) {
                console.warn("[soccerResults] Parse error: " + e);
                root.errorMessage = "Failed to parse data";
            }
        }
    }

    // === Fetch: match goals (sequential, one at a time) ===
    Process {
        id: goalFetcher
        property string output: ""
        stdout: SplitParser { onRead: line => { goalFetcher.output += line + "\n"; } }

        onExited: (exitCode) => {
            var matchId = root._currentGoalMatchId;
            root._currentGoalMatchId = "";

            if (exitCode === 0 && goalFetcher.output.trim()) {
                var data = root._parseResponse(goalFetcher.output);
                if (data && data.goals && data.goals.length > 0) {
                    var updated = {};
                    for (var k in root._matchGoals) updated[k] = root._matchGoals[k];
                    updated[matchId] = data.goals;
                    root._matchGoals = updated;
                }
            }
            goalFetcher.output = "";

            // Fetch next in queue
            root._fetchNextGoal();
        }
    }

    function fetchPage(force) {
        if (!activeLeague || pageFetcher.running) return;
        if (!force && !_canFetch(_lastPageFetch, _minFetchIntervalMs)) return;

        var url = Api.buildPageUrl(activeLeague);
        if (!url) return;

        loading = true;
        standingsLoading = true;
        _lastPageFetch = _now();
        pageFetcher.output = "";
        pageFetcher.command = _buildFetchCommand(url);
        pageFetcher.running = true;
    }

    // === Fetch: matchday matches ===
    Process {
        id: matchdayFetcher
        property string output: ""
        stdout: SplitParser { onRead: line => { matchdayFetcher.output += line + "\n"; } }

        onExited: (exitCode) => {
            root.matchdayLoading = false;

            if (exitCode !== 0 && !matchdayFetcher.output.trim()) {
                root.matchdayError = "Failed to fetch matchday";
                matchdayFetcher.output = "";
                return;
            }

            var data = root._parseResponse(matchdayFetcher.output);
            matchdayFetcher.output = "";

            if (data.error) {
                root.matchdayError = data.error;
                return;
            }

            try {
                var result = Api.parsePageData(JSON.stringify(data));
                if (result.error) {
                    root.matchdayError = result.error;
                    return;
                }

                root.matchdayMatches = result.matches;
                root.matchdayError = "";
            } catch (e) {
                console.warn("[soccerResults] Matchday parse error: " + e);
                root.matchdayError = "Failed to parse matchday data";
            }
        }
    }

    function fetchMatchday(force) {
        if (!activeLeague || currentMatchday <= 0 || !_season) return;
        if (matchdayFetcher.running) return;
        if (!force && !_canFetch(_lastMatchdayFetch, _matchdayCacheMs)) return;

        var url = Api.buildMatchdayPageUrl(activeLeague, _season, currentMatchday);
        if (!url) return;

        matchdayLoading = true;
        _lastMatchdayFetch = _now();
        matchdayFetcher.output = "";
        matchdayFetcher.command = _buildFetchCommand(url);
        matchdayFetcher.running = true;
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
        running: root.activeLeague !== ""
        repeat: true
        onTriggered: {
            root.fetchPage();
            if (root.currentTab === 1) root.fetchMatchday();
            // Re-queue live matches for goal updates
            if (root.hasLive) root._enqueueGoalFetches(root.matches, true);
        }
    }

    // === Lazy fetch on tab change ===
    onCurrentTabChanged: {
        if (currentTab === 1) {
            if (currentMatchday > 0 && _season && matchdayMatches.length === 0)
                fetchMatchday(true);
        }
        // Standings are loaded with the main page fetch, no separate fetch needed
    }

    // When matchday is resolved, auto-fetch if the matchday tab is active
    onCurrentMatchdayChanged: {
        if (currentMatchday > 0 && _season && currentTab === 1 && matchdayMatches.length === 0)
            fetchMatchday(true);
    }

    // === React to default league setting changes (also handles late pluginData arrival) ===
    onDefaultLeagueChanged: {
        if (defaultLeague) {
            switchLeague(defaultLeague);
        }
    }

    // === Init: only fetch if pluginData was already available ===
    Component.onCompleted: {
        if (defaultLeague) {
            activeLeague = defaultLeague;
            fetchPage(true);
        } else {
            // pluginData not loaded yet — onDefaultLeagueChanged will handle it
            activeLeague = "PL";
        }
    }

    // === Widget properties ===
    ccWidgetIcon: "sports_soccer"
    ccWidgetPrimaryText: Api.leagueName(activeLeague)
    ccWidgetSecondaryText: {
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

            Rectangle {
                visible: root.pillMatch ? Api.pillSuffix(root.pillMatch) !== "" : false
                width: 1
                height: root.iconSize - 2
                radius: 0.5
                color: root.pillLive ? Theme.primary : Theme.surfaceVariantText
                opacity: 0.3
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: root.pillMatch ? Api.pillSuffix(root.pillMatch) !== "" : false
                text: root.pillMatch ? Api.pillSuffix(root.pillMatch) : ""
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale) - 1
                font.weight: Font.Medium
                color: root.pillLive ? Theme.primary : Theme.surfaceVariantText
                opacity: 0.7
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

            StyledText {
                visible: root.pillMatch ? Api.pillSuffix(root.pillMatch) !== "" : false
                text: root.pillMatch ? Api.pillSuffix(root.pillMatch) : ""
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale) - 2
                font.weight: Font.Medium
                color: root.pillLive ? Theme.primary : Theme.surfaceVariantText
                opacity: 0.7
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
            matchGoals: root._matchGoals

            loading: root.loading
            matchdayLoading: root.matchdayLoading
            standingsLoading: root.standingsLoading

            errorMessage: root.errorMessage
            matchdayError: root.matchdayError
            standingsError: root.standingsError

            lastUpdated: root.lastUpdated

            onRefreshRequested: {
                root.fetchPage(true);
                if (root.currentMatchday > 0) root.fetchMatchday(true);
            }
            onLeagueSelected: function(code) { root.switchLeague(code); }
            onTabChanged: function(tab) { root.currentTab = tab; }
            onMatchPinned: function(matchId) {
                root.pinnedMatchId = (root.pinnedMatchId === matchId) ? "" : matchId;
            }
        }
    }
}
