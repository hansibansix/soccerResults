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
    readonly property string cookieBrowser: pluginData.cookieBrowser || ""

    // === Active league (runtime, changeable from popout) ===
    property string activeLeague: ""

    // === Tab state ===
    property int currentTab: 0  // 0=Today, 1=Matchday, 2=Table
    property bool liveMode: false

    // === Today's matches state ===
    property var matches: []
    property bool loading: false
    property string errorMessage: ""
    property string lastUpdated: ""
    property bool hasLive: false

    // === Matchday state ===
    property var matchdayMatches: []
    property int currentMatchday: 0
    property int _defaultMatchday: 0  // the "current" matchday from the API
    property string _season: ""
    property bool matchdayLoading: false
    property string matchdayError: ""

    // === Standings state ===
    property var standings: []
    property var standingsGroups: []
    property bool standingsLoading: false
    property string standingsError: ""

    // === Live scan state (all-league live matches) ===
    property var liveMatches: []
    property bool liveLoading: false
    property string liveError: ""
    property var _liveLeagueQueue: []
    property int _liveLeagueQueueIdx: 0
    property real _lastLiveScan: 0
    readonly property int _liveScanCacheMs: 120000  // 2 min — live data is time-sensitive

    // === Favorite team ===
    readonly property string favoriteTeam: pluginData.favoriteTeam || ""
    property var _favoriteMatchData: null
    property var _favoriteLeagueQueue: []
    property int _favoriteLeagueQueueIdx: 0
    property string _favoriteLeagueCache: ""        // league where team was last found
    property string _currentFavFetchLeague: ""      // league currently being fetched
    property real _lastFavoriteScan: 0
    readonly property int _favoriteScanIntervalMs: 600000   // 10 min between full scans

    // === Pinned match ===
    property string pinnedMatchId: ""
    property string _pinnedLeague: ""
    property var _pinnedMatchData: null

    // === Goal data ===
    property var _goalQueue: []
    property int _goalQueueIdx: 0
    property var _matchGoals: ({})
    property string _currentGoalMatchId: ""

    // === Rate limit / caching ===
    property string _fetchingLeague: ""                               // league pageFetcher is currently fetching
    property int _fetchGeneration: 0                                  // incremented on each league switch to discard stale results
    property real _lastPageFetch: 0
    property real _lastMatchdayFetch: 0
    readonly property int _minFetchIntervalMs: 30000          // 30s min between same-endpoint fetches
    readonly property int _matchdayCacheMs: 600000            // 10min — matchday changes slowly
    property real _lastStandingsFetch: 0
    readonly property int _standingsCacheMs: 600000           // 10min — standings change slowly

    // === Script paths ===
    readonly property string _scriptPath: Qt.resolvedUrl("parse_kicker.py").toString().replace("file://", "")
    readonly property string _fetchScriptPath: Qt.resolvedUrl("fetch_kicker.py").toString().replace("file://", "")

    // === Pill helpers ===
    readonly property var pillMatch: Api.findPillMatch(_pinnedMatchData, _favoriteMatchData)
    readonly property bool pillLive: pillMatch ? Api.isLive(pillMatch.status) : false

    // === Helpers ===
    function _now() { return Date.now(); }

    function _canFetch(lastFetch, cacheMs) {
        return (_now() - lastFetch) >= Math.max(cacheMs, _minFetchIntervalMs);
    }

    function _resetFavoriteState() {
        _favoriteMatchData = null;
        _favoriteLeagueQueue = [];
        _favoriteLeagueQueueIdx = 0;
        _favoriteLeagueCache = "";
        _currentFavFetchLeague = "";
        _lastFavoriteScan = 0;
    }

    function _resetAllData() {
        _resetLeagueData();
        _resetFavoriteState();
    }

    function _resetLeagueData() {
        matches = [];
        matchdayMatches = [];
        standings = [];
        standingsGroups = [];
        currentMatchday = 0;
        _defaultMatchday = 0;
        _season = "";
        errorMessage = "";
        matchdayError = "";
        standingsError = "";
        lastUpdated = "";
        _lastPageFetch = 0;
        _lastMatchdayFetch = 0;
        _lastStandingsFetch = 0;
        _goalQueue = [];
        _goalQueueIdx = 0;
        _matchGoals = {};
        _currentGoalMatchId = "";
    }

    function _enqueueGoalFetches(matchList, liveOnly) {
        var queue = [];
        for (var i = 0; i < matchList.length; i++) {
            var m = matchList[i];
            if (!m.id) continue;
            if (Api.isLive(m.status)) {
                queue.push(m.id);
            } else if (!liveOnly && Api.isFinished(m.status) && !_matchGoals[m.id]) {
                // Only fetch finished match goals if not already cached
                queue.push(m.id);
            }
        }
        _goalQueue = queue;
        _goalQueueIdx = 0;
        _fetchNextGoal();
    }

    function _fetchNextGoal() {
        if (goalFetcher.running || _goalQueueIdx >= _goalQueue.length) return;
        var matchId = _goalQueue[_goalQueueIdx];
        _goalQueueIdx++;
        _currentGoalMatchId = matchId;
        var url = Api.buildMatchGoalsUrl(matchId);
        goalFetcher.output = "";
        goalFetcher.command = _buildFetchCommand(url, "--goals");
        goalFetcher.running = true;
    }

    function getMatchGoals(matchId) {
        return _matchGoals[matchId] || [];
    }

    readonly property string _browserArg: cookieBrowser ? " --browser '" + cookieBrowser + "'" : ""

    function _buildFetchCommand(url, parserFlag) {
        var flagStr = parserFlag ? " " + parserFlag : "";
        return ["bash", "-c", "python3 '" + _fetchScriptPath + "' '" + url + "'" + _browserArg + " | python3 '" + _scriptPath + "'" + flagStr];
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

    function _parsePageResult(fetcherOutput, exitCode) {
        if (exitCode !== 0 && !fetcherOutput.trim()) return null;
        var data = _parseResponse(fetcherOutput);
        if (data.error) return null;
        try {
            var result = Api.parsePageData(data);
            return result.error ? null : result;
        } catch (e) {
            return null;
        }
    }

    function _updateTimestamp() {
        var now = new Date();
        lastUpdated = ("0" + now.getHours()).slice(-2) + ":" +
                      ("0" + now.getMinutes()).slice(-2);
    }

    function switchLeague(code) {
        if (code === activeLeague) return;
        _fetchGeneration++;
        activeLeague = code;
        _resetLeagueData();
        loading = true;
        if (pageFetcher.running) {
            // Kill stale fetch — onExited will detect stale generation and re-fetch
            pageFetcher.running = false;
        }
        if (standingsFetcher.running) {
            standingsFetcher.running = false;
        }
        // Always schedule a fetch — Qt.callLater ensures it runs after any pending onExited
        Qt.callLater(fetchPage, true);
        // If already on Table tab, fetch standings for the new league
        if (currentTab === 2) Qt.callLater(fetchStandings, true);
    }

    function pinMatch(matchId, leagueCode) {
        if (pinnedMatchId === matchId) {
            // Unpin
            pinnedMatchId = "";
            _pinnedLeague = "";
            _pinnedMatchData = null;
            return;
        }
        pinnedMatchId = matchId;
        _pinnedLeague = leagueCode || activeLeague;
        // Find the match data in current lists
        var allMatches = (matches || []).concat(matchdayMatches || []).concat(liveMatches || []);
        for (var i = 0; i < allMatches.length; i++) {
            if (allMatches[i].id === matchId) {
                _pinnedMatchData = allMatches[i];
                return;
            }
        }
    }

    function _updatePinnedFromMatches(matchList) {
        if (!pinnedMatchId) return;
        for (var i = 0; i < matchList.length; i++) {
            if (matchList[i].id === pinnedMatchId) {
                _pinnedMatchData = matchList[i];
                // Auto-unpin when match is no longer live
                if (Api.isFinished(matchList[i].status)) {
                    pinnedMatchId = "";
                    _pinnedLeague = "";
                    _pinnedMatchData = null;
                }
                return;
            }
        }
    }

    function _fetchPinnedMatch() {
        if (!pinnedMatchId || !_pinnedLeague || pinnedFetcher.running) return;
        // If pinned match is in the active league, it gets updated via pageFetcher already
        if (_pinnedLeague === activeLeague) return;
        var url = Api.buildPageUrl(_pinnedLeague);
        if (!url) return;
        pinnedFetcher.output = "";
        pinnedFetcher.command = _buildFetchCommand(url);
        pinnedFetcher.running = true;
    }

    function _updateFavoriteFromMatches(matchList, leagueCode) {
        if (!favoriteTeam) return;
        var found = Api.findFavoriteTeamMatch(matchList, favoriteTeam);
        if (!found) return;
        // Don't overwrite a live match with an upcoming one from another league scan
        if (_favoriteMatchData && Api.isLive(_favoriteMatchData.status) &&
            !Api.isLive(found.status) && !Api.isFinished(found.status)) return;
        _favoriteMatchData = found;
        if (leagueCode) _favoriteLeagueCache = leagueCode;
    }

    function _fetchFavoriteMatch() {
        if (!favoriteTeam || favoriteFetcher.running) return;

        // 1) If favorite is already live in a cached league, just refresh that one
        if (_favoriteIsLive && _favoriteLeagueCache) {
            if (_favoriteLeagueCache === activeLeague) {
                _updateFavoriteFromMatches(matches, activeLeague);
            } else {
                _startFavoriteFetch(_favoriteLeagueCache);
            }
            return;
        }

        // 2) Check active league (free — already fetched by pageFetcher)
        _updateFavoriteFromMatches(matches, activeLeague);
        if (_favoriteMatchData && Api.isLive(_favoriteMatchData.status)) return;

        // 3) Full scan of other leagues — rate-limited
        if (_favoriteLeagueQueueIdx < _favoriteLeagueQueue.length) return;
        if (_lastFavoriteScan > 0 && (_now() - _lastFavoriteScan) < _favoriteScanIntervalMs) return;
        _lastFavoriteScan = _now();

        var codes = Object.keys(Api.leagueMap);
        var queue = [];
        for (var i = 0; i < codes.length; i++) {
            if (codes[i] !== activeLeague) queue.push(codes[i]);
        }
        _favoriteLeagueQueue = queue;
        _favoriteLeagueQueueIdx = 0;
        _fetchNextFavoriteLeague();
    }

    function _startFavoriteFetch(leagueCode) {
        var url = Api.buildPageUrl(leagueCode);
        if (!url) return;
        _currentFavFetchLeague = leagueCode;
        _favoriteLeagueQueue = [];
        _favoriteLeagueQueueIdx = 0;
        favoriteFetcher.output = "";
        favoriteFetcher.command = _buildFetchCommand(url);
        favoriteFetcher.running = true;
    }

    function _fetchNextFavoriteLeague() {
        if (favoriteFetcher.running || _favoriteLeagueQueueIdx >= _favoriteLeagueQueue.length) return;
        // Stop scanning if we found a live match
        if (_favoriteMatchData && Api.isLive(_favoriteMatchData.status)) return;
        var code = _favoriteLeagueQueue[_favoriteLeagueQueueIdx];
        _favoriteLeagueQueueIdx++;
        _currentFavFetchLeague = code;
        var url = Api.buildPageUrl(code);
        if (!url) { _fetchNextFavoriteLeague(); return; }
        favoriteFetcher.output = "";
        favoriteFetcher.command = _buildFetchCommand(url);
        favoriteFetcher.running = true;
    }

    // === Fetch: main page (matches + standings + matchday) ===
    Process {
        id: pageFetcher
        property string output: ""
        property int generation: 0
        stdout: SplitParser { onRead: line => { pageFetcher.output += line + "\n"; } }

        onExited: (exitCode) => {
            root._fetchingLeague = "";

            // Stale fetch (league changed since this fetch started) — discard and re-fetch
            if (pageFetcher.generation !== root._fetchGeneration) {
                pageFetcher.output = "";
                // Process is now dead, so fetchPage can start a new one
                Qt.callLater(root.fetchPage, true);
                return;
            }

            root.loading = false;

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
                var result = Api.parsePageData(data);
                if (result.error) {
                    root.errorMessage = result.error;
                    return;
                }

                root.matches = result.matches;
                root.hasLive = Api.hasAnyLive(result.matches);
                root.errorMessage = "";
                root._updateTimestamp();

                // Use standings from /spieltag if we don't have any yet
                if (result.standings && result.standings.length > 0 && root.standings.length === 0) {
                    root.standings = result.standings;
                    root.standingsError = "";
                }

                // Set season before matchday so onCurrentMatchdayChanged sees _season
                if (result.season) root._season = result.season;
                if (result.matchday > 0) {
                    root._defaultMatchday = result.matchday;
                    // Only update currentMatchday if user hasn't navigated away
                    if (root.currentMatchday === 0 || root.currentMatchday === root._defaultMatchday)
                        root.currentMatchday = result.matchday;
                }

                // Reuse page matches for Matchday tab when on the default matchday
                if (root.currentTab === 1 && root.matchdayMatches.length === 0 &&
                    root.currentMatchday > 0 && root.currentMatchday === root._defaultMatchday) {
                    root.matchdayMatches = result.matches;
                    root.matchdayError = "";
                } else if (root.currentTab === 1 && root.matchdayMatches.length === 0 &&
                    root.currentMatchday > 0 && root._season) {
                    Qt.callLater(root.fetchMatchday, true);
                }

                // Enqueue goal fetches for finished + live matches
                root._enqueueGoalFetches(result.matches, false);

                // Update pinned match if it's in this league
                root._updatePinnedFromMatches(result.matches);
                // Fetch pinned match separately if in different league
                root._fetchPinnedMatch();

                // Scan all leagues for favorite team's live match
                root._fetchFavoriteMatch();
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
                    var updated = Object.assign({}, root._matchGoals);
                    updated[matchId] = data.goals;
                    root._matchGoals = updated;
                }
            }
            goalFetcher.output = "";

            // Fetch next in queue
            root._fetchNextGoal();
        }
    }

    // === Fetch: pinned match (when in different league) ===
    Process {
        id: pinnedFetcher
        property string output: ""
        stdout: SplitParser { onRead: line => { pinnedFetcher.output += line + "\n"; } }

        onExited: (exitCode) => {
            var result = root._parsePageResult(pinnedFetcher.output, exitCode);
            pinnedFetcher.output = "";
            if (result) root._updatePinnedFromMatches(result.matches);
        }
    }

    // === Fetch: favorite team match (scans all leagues sequentially) ===
    Process {
        id: favoriteFetcher
        property string output: ""
        stdout: SplitParser { onRead: line => { favoriteFetcher.output += line + "\n"; } }

        onExited: (exitCode) => {
            var league = root._currentFavFetchLeague;
            root._currentFavFetchLeague = "";

            var result = root._parsePageResult(favoriteFetcher.output, exitCode);
            favoriteFetcher.output = "";
            if (result) root._updateFavoriteFromMatches(result.matches, league);
            root._fetchNextFavoriteLeague();
        }
    }

    // === Fetch: live matches across all leagues ===
    property var _liveAccumulator: []

    Process {
        id: liveFetcher
        property string output: ""
        stdout: SplitParser { onRead: line => { liveFetcher.output += line + "\n"; } }

        onExited: (exitCode) => {
            var idx = root._liveLeagueQueueIdx - 1;
            var code = (idx >= 0 && idx < root._liveLeagueQueue.length)
                ? root._liveLeagueQueue[idx] : "";

            var result = root._parsePageResult(liveFetcher.output, exitCode);
            liveFetcher.output = "";
            if (result) {
                var live = Api.filterLive(result.matches);
                if (live.length > 0) {
                    var name = Api.leagueName(code);
                    for (var i = 0; i < live.length; i++) {
                        live[i]._leagueCode = code;
                        live[i]._leagueName = name;
                    }
                    root._liveAccumulator = root._liveAccumulator.concat(live);
                }
            }
            root._fetchNextLiveLeague();
        }
    }

    function fetchLiveMatches(force) {
        if (liveFetcher.running) return;
        if (!force && !_canFetch(_lastLiveScan, _liveScanCacheMs)) return;

        _lastLiveScan = _now();
        liveLoading = true;
        liveError = "";

        // Seed accumulator with active league's live matches (already fetched by pageFetcher)
        var activeLive = Api.filterLive(matches);
        if (activeLive.length > 0) {
            var name = Api.leagueName(activeLeague);
            for (var i = 0; i < activeLive.length; i++) {
                activeLive[i]._leagueCode = activeLeague;
                activeLive[i]._leagueName = name;
            }
        }
        _liveAccumulator = activeLive;

        // Only scan other leagues (skip active league)
        var codes = Object.keys(Api.leagueMap);
        var queue = [];
        for (var i = 0; i < codes.length; i++) {
            if (codes[i] !== activeLeague) queue.push(codes[i]);
        }
        _liveLeagueQueue = queue;
        _liveLeagueQueueIdx = 0;
        _fetchNextLiveLeague();
    }

    function _fetchNextLiveLeague() {
        if (liveFetcher.running) return;
        if (_liveLeagueQueueIdx >= _liveLeagueQueue.length) {
            // Scan complete
            liveMatches = _liveAccumulator;
            liveLoading = false;
            return;
        }
        var code = _liveLeagueQueue[_liveLeagueQueueIdx];
        _liveLeagueQueueIdx++;
        var url = Api.buildPageUrl(code);
        if (!url) { _fetchNextLiveLeague(); return; }
        liveFetcher.output = "";
        liveFetcher.command = _buildFetchCommand(url);
        liveFetcher.running = true;
    }

    function fetchPage(force) {
        if (!activeLeague || pageFetcher.running) return;
        if (!force && !_canFetch(_lastPageFetch, _minFetchIntervalMs)) return;

        var url = Api.buildPageUrl(activeLeague);
        if (!url) return;

        loading = true;
        _fetchingLeague = activeLeague;
        _lastPageFetch = _now();
        pageFetcher.output = "";
        pageFetcher.generation = _fetchGeneration;
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
                var result = Api.parsePageData(data);
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

    // === Fetch: standings from /tabelle ===
    Process {
        id: standingsFetcher
        property string output: ""
        stdout: SplitParser { onRead: line => { standingsFetcher.output += line + "\n"; } }

        onExited: (exitCode) => {
            root.standingsLoading = false;

            if (exitCode !== 0 && !standingsFetcher.output.trim()) {
                root.standingsError = "Failed to fetch standings";
                standingsFetcher.output = "";
                return;
            }

            var data = root._parseResponse(standingsFetcher.output);
            standingsFetcher.output = "";

            if (data.error) {
                root.standingsError = data.error;
                return;
            }

            try {
                root.standings = data.standings || [];
                root.standingsGroups = [];
                root.standingsError = "";
            } catch (e) {
                console.warn("[soccerResults] Standings parse error: " + e);
                root.standingsError = "Failed to parse standings";
            }
        }
    }

    function fetchStandings(force) {
        if (!activeLeague || standingsFetcher.running) return;
        if (!force && !_canFetch(_lastStandingsFetch, _standingsCacheMs)) return;

        var url = Api.buildStandingsUrl(activeLeague);
        if (!url) return;

        standingsLoading = true;
        _lastStandingsFetch = _now();
        standingsFetcher.output = "";
        standingsFetcher.command = _buildFetchCommand(url, "--standings");
        standingsFetcher.running = true;
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

    function navigateMatchday(delta) {
        var next = currentMatchday + delta;
        if (next < 1) return;
        currentMatchday = next;
        matchdayMatches = [];
        _lastMatchdayFetch = 0;
        fetchMatchday(true);
    }

    // === Polling timer ===
    readonly property bool _pinnedIsLive: _pinnedMatchData ? Api.isLive(_pinnedMatchData.status) : false
    readonly property bool _favoriteIsLive: _favoriteMatchData ? Api.isLive(_favoriteMatchData.status) : false

    Timer {
        id: pollTimer
        // Live (or pinned/favorite live): 60s, has matches: 5min, no matches: 15min
        interval: {
            if (root.hasLive || root._pinnedIsLive || root._favoriteIsLive) return 60000;
            if (root.matches.length > 0) return Math.max(root.refreshIntervalMinutes * 60 * 1000, 180000);
            return 900000; // 15min when no matches today
        }
        running: root.activeLeague !== ""
        repeat: true
        onTriggered: {
            root.fetchPage();
            if (root.liveMode) root.fetchLiveMatches();
            if (root.currentTab === 1) root.fetchMatchday();
            if (root.currentTab === 2) root.fetchStandings();
            // Re-queue live matches for goal updates
            if (root.hasLive) root._enqueueGoalFetches(root.matches, true);
            // Refresh pinned match if in different league
            root._fetchPinnedMatch();
            // Refresh favorite match if in different league
            root._fetchFavoriteMatch();
        }
    }

    // === Lazy fetch on live mode / tab change ===
    onLiveModeChanged: {
        if (liveMode) fetchLiveMatches();
    }

    onCurrentTabChanged: {
        if (currentTab === 1) {
            if (matchdayMatches.length === 0 && currentMatchday > 0) {
                // Reuse page matches if on default matchday, otherwise fetch
                if (currentMatchday === _defaultMatchday && matches.length > 0) {
                    matchdayMatches = matches;
                    matchdayError = "";
                } else if (_season) {
                    fetchMatchday(true);
                }
            }
        } else if (currentTab === 2) {
            if (standings.length === 0 || _canFetch(_lastStandingsFetch, _standingsCacheMs))
                fetchStandings(true);
        }
    }

    // When matchday is resolved, auto-fetch if the matchday tab is active
    onCurrentMatchdayChanged: {
        if (currentMatchday > 0 && currentTab === 1 && matchdayMatches.length === 0) {
            if (currentMatchday === _defaultMatchday && matches.length > 0) {
                matchdayMatches = matches;
                matchdayError = "";
            } else if (_season) {
                fetchMatchday(true);
            }
        }
    }

    // === React to favorite team setting changes ===
    onFavoriteTeamChanged: {
        _resetFavoriteState();
        if (favoriteTeam) _fetchFavoriteMatch();
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
        if (matches.length > 0) return matches.length + " matches today";
        return "No matches today";
    }
    ccWidgetIsActive: matches.length > 0

    // === Bar pills ===
    readonly property int pillCrestSize: Math.round(root.iconSize * 1.3)
    readonly property int pillScoreSize: Math.round(Theme.barTextSize(root.barThickness, root.barConfig?.fontScale) * 1.2)

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            Image {
                source: root.pillMatch ? root.pillMatch.homeCrest || "" : ""
                sourceSize.width: root.pillCrestSize
                sourceSize.height: root.pillCrestSize
                width: root.pillCrestSize
                height: root.pillCrestSize
                fillMode: Image.PreserveAspectFit
                visible: root.pillMatch && source !== ""
                anchors.verticalCenter: parent.verticalCenter
            }

            DankIcon {
                name: "sports_soccer"
                size: root.pillCrestSize
                color: root.pillLive ? Theme.primary : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.pillMatch || !root.pillMatch.homeCrest
            }

            StyledText {
                visible: root.pillMatch !== null
                text: root.pillMatch ? Api.scoreText(root.pillMatch) : ""
                font.pixelSize: root.pillScoreSize
                font.weight: Font.Bold
                color: root.pillLive ? Theme.primary : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            Image {
                source: root.pillMatch ? root.pillMatch.awayCrest || "" : ""
                sourceSize.width: root.pillCrestSize
                sourceSize.height: root.pillCrestSize
                width: root.pillCrestSize
                height: root.pillCrestSize
                fillMode: Image.PreserveAspectFit
                visible: root.pillMatch && source !== ""
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                visible: root.pillMatch ? Api.pillSuffix(root.pillMatch) !== "" : false
                width: 1
                height: root.pillCrestSize - 2
                radius: 0.5
                color: root.pillLive ? Theme.primary : Theme.surfaceVariantText
                opacity: 0.3
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: root.pillMatch ? Api.pillSuffix(root.pillMatch) !== "" : false
                text: root.pillMatch ? Api.pillSuffix(root.pillMatch) : ""
                font.pixelSize: root.pillScoreSize - 1
                font.weight: Font.Medium
                color: root.pillLive ? Theme.primary : Theme.surfaceVariantText
                opacity: 0.7
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                name: "sports_soccer"
                size: root.iconSize
                color: root.pillLive ? Theme.primary : Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !root.pillMatch
            }

            Image {
                source: root.pillMatch ? root.pillMatch.homeCrest || "" : ""
                sourceSize.width: root.pillCrestSize
                sourceSize.height: root.pillCrestSize
                width: root.pillCrestSize
                height: root.pillCrestSize
                fillMode: Image.PreserveAspectFit
                visible: root.pillMatch && source !== ""
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                visible: root.pillMatch !== null
                text: root.pillMatch ? Api.scoreText(root.pillMatch) : ""
                font.pixelSize: root.pillScoreSize
                font.weight: Font.Bold
                color: root.pillLive ? Theme.primary : Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Image {
                source: root.pillMatch ? root.pillMatch.awayCrest || "" : ""
                sourceSize.width: root.pillCrestSize
                sourceSize.height: root.pillCrestSize
                width: root.pillCrestSize
                height: root.pillCrestSize
                fillMode: Image.PreserveAspectFit
                visible: root.pillMatch && source !== ""
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                visible: root.pillMatch ? Api.pillSuffix(root.pillMatch) !== "" : false
                text: root.pillMatch ? Api.pillSuffix(root.pillMatch) : ""
                font.pixelSize: root.pillScoreSize - 2
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
            defaultMatchday: root._defaultMatchday
            standings: root.standings
            standingsGroups: root.standingsGroups
            activeLeague: root.activeLeague
            currentTab: root.currentTab
            liveMode: root.liveMode
            pinnedMatchId: root.pinnedMatchId
            matchGoals: root._matchGoals

            liveMatches: root.liveMatches
            liveLoading: root.liveLoading
            liveError: root.liveError

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
            onLiveModeToggled: { root.liveMode = !root.liveMode; }
            onMatchdayNavigated: function(delta) { root.navigateMatchday(delta); }
            onMatchPinned: function(matchId, leagueCode) {
                root.pinMatch(matchId, leagueCode);
            }
        }
    }
}
