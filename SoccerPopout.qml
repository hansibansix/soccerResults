import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "SoccerApi.js" as Api

PopoutComponent {
    id: popout

    // Today's matches
    required property var matches
    // Matchday
    required property var matchdayMatches
    required property int currentMatchday
    // Standings
    required property var standings
    required property var standingsGroups
    // Shared
    required property string activeLeague
    required property int currentTab

    required property bool loading
    required property bool matchdayLoading
    required property bool standingsLoading

    required property string errorMessage
    required property string matchdayError
    required property string standingsError

    required property string lastUpdated
    required property string pinnedMatchId
    required property var matchGoals

    signal refreshRequested()
    signal leagueSelected(string code)
    signal tabChanged(int tab)
    signal matchPinned(string matchId, string leagueCode)

    readonly property var leagueOptions: [
        { code: "PL",  label: "PL" },
        { code: "PD",  label: "Liga" },
        { code: "BL1", label: "BL" },
        { code: "SA",  label: "SA" },
        { code: "FL1", label: "L1" },
        { code: "CL",  label: "CL" }
    ]

    readonly property bool showBundesligaSubs: Api.isBundesliga(popout.activeLeague)

    readonly property var bundesligaSubOptions: [
        { code: "BL1", label: "1. BL" },
        { code: "BL2", label: "2. BL" },
        { code: "BL3", label: "3. Liga" }
    ]

    readonly property var tabOptions: [
        { icon: "today",          label: "Today" },
        { icon: "calendar_month", label: "Matchday" },
        { icon: "leaderboard",    label: "Table" }
    ]

    readonly property var todayMatches: Api.filterToday(popout.matches)
    readonly property bool anyLoading: loading || matchdayLoading || standingsLoading

    headerText: Api.leagueName(activeLeague)
    detailsText: {
        if (currentTab === 0) {
            if (loading) return "Updating...";
            if (todayMatches.length > 0) return todayMatches.length + " match" + (todayMatches.length !== 1 ? "es" : "") + " today";
            return "No matches today";
        }
        if (currentTab === 1) {
            if (matchdayLoading) return "Updating...";
            if (currentMatchday > 0) return "Matchday " + currentMatchday;
            return "Loading matchday...";
        }
        if (currentTab === 2) {
            if (standingsLoading) return "Updating...";
            return "Season standings";
        }
        return "";
    }
    showCloseButton: false

    headerActions: Component {
        Row {
            spacing: 4

            DankActionButton {
                iconName: "refresh"
                iconColor: popout.anyLoading ? Theme.primary : Theme.surfaceVariantText
                buttonSize: 28
                tooltipText: "Refresh"
                tooltipSide: "bottom"
                onClicked: popout.refreshRequested()

                RotationAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 800
                    loops: Animation.Infinite
                    running: popout.anyLoading
                }
            }
        }
    }

    // === Single wrapper — fixed height, absolute positioning ===
    Item {
        id: contentWrapper
        width: parent.width
        height: 550

        // === League selector pills ===
        Row {
            id: leaguePills
            y: 0
            width: parent.width
            height: 28
            spacing: Theme.spacingXS

            Repeater {
                model: popout.leagueOptions

                delegate: StyledRect {
                    required property var modelData
                    required property int index

                    readonly property bool selected: modelData.code === "BL1"
                        ? Api.isBundesliga(popout.activeLeague)
                        : popout.activeLeague === modelData.code

                    width: (parent.width - Theme.spacingXS * (popout.leagueOptions.length - 1)) / popout.leagueOptions.length
                    height: 28
                    radius: Theme.cornerRadius
                    color: selected
                        ? Theme.primaryContainer
                        : Theme.surfaceContainerHigh

                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }

                    StyledText {
                        anchors.centerIn: parent
                        text: modelData.label
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: selected ? Font.Bold : Font.Normal
                        color: selected ? Theme.surfaceText : Theme.surfaceVariantText
                    }

                    StateLayer {
                        enableRipple: false
                        onClicked: {
                            if (modelData.code === "BL1" && Api.isBundesliga(popout.activeLeague))
                                return; // already on a BL league, subtabs handle switching
                            popout.leagueSelected(modelData.code)
                        }
                    }
                }
            }
        }

        // === Bundesliga subtabs ===
        Row {
            id: blSubTabs
            visible: popout.showBundesligaSubs
            y: leaguePills.height + Theme.spacingXS
            width: parent.width
            height: visible ? 24 : 0
            spacing: Theme.spacingXS

            Repeater {
                model: popout.bundesligaSubOptions

                delegate: StyledRect {
                    required property var modelData
                    required property int index

                    readonly property bool selected: popout.activeLeague === modelData.code

                    width: (parent.width - Theme.spacingXS * (popout.bundesligaSubOptions.length - 1)) / popout.bundesligaSubOptions.length
                    height: 24
                    radius: Theme.cornerRadius - 2
                    color: selected
                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                        : "transparent"

                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }

                    StyledText {
                        anchors.centerIn: parent
                        text: modelData.label
                        font.pixelSize: Theme.fontSizeSmall - 1
                        font.weight: selected ? Font.Bold : Font.Normal
                        color: selected ? Theme.primary : Theme.surfaceVariantText
                    }

                    StateLayer {
                        enableRipple: false
                        onClicked: popout.leagueSelected(modelData.code)
                    }
                }
            }
        }

        // === Tab bar ===
        Row {
            id: tabBar
            y: leaguePills.height + (blSubTabs.visible ? blSubTabs.height + Theme.spacingXS : 0) + Theme.spacingXS
            width: parent.width
            height: 38
            spacing: Theme.spacingXS

            Repeater {
                model: popout.tabOptions

                delegate: StyledRect {
                    required property var modelData
                    required property int index

                    readonly property bool selected: popout.currentTab === index

                    width: (parent.width - Theme.spacingXS * (popout.tabOptions.length - 1)) / popout.tabOptions.length
                    height: 38
                    radius: Theme.cornerRadius
                    color: selected
                        ? Theme.primaryContainer
                        : Theme.surfaceContainerHigh

                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon {
                            name: modelData.icon
                            size: 16
                            color: selected ? Theme.surfaceText : Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: modelData.label
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: selected ? Font.Bold : Font.Normal
                            color: selected ? Theme.surfaceText : Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Rectangle {
                        visible: selected
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width * 0.5
                        height: 2
                        radius: 1
                        color: Theme.primary
                    }

                    StateLayer {
                        enableRipple: false
                        onClicked: popout.tabChanged(index)
                    }
                }
            }
        }

        // === Tab content ===
        DankFlickable {
            id: contentFlickable
            y: tabBar.y + tabBar.height + Theme.spacingS
            width: parent.width
            height: parent.height - y - 18
            contentHeight: contentLoader.item ? contentLoader.item.implicitHeight : height
            clip: true

            Connections {
                target: popout
                function onActiveLeagueChanged() { contentFlickable.contentY = 0; }
                function onCurrentTabChanged() { contentFlickable.contentY = 0; }
            }

            Loader {
                id: contentLoader
                width: parent.width

                readonly property var tabComponents: [todayTab, matchdayTab, standingsTab]
                sourceComponent: tabComponents[popout.currentTab] || standingsTab
            }
        }

        // === Footer ===
        StyledText {
            y: parent.height - 14
            width: parent.width
            text: popout.lastUpdated !== "" ? "Updated " + popout.lastUpdated : " "
            font.pixelSize: Theme.fontSizeSmall - 1
            color: Theme.surfaceVariantText
            horizontalAlignment: Text.AlignRight
            opacity: popout.lastUpdated !== "" ? 0.4 : 0
        }
    }

    // ==============================
    // === Tab content components ===
    // ==============================

    Component {
        id: todayTab

        ColumnLayout {
            width: parent ? parent.width : 0
            spacing: Theme.spacingS

            Loader {
                readonly property bool shouldShow: popout.errorMessage !== "" && popout.todayMatches.length === 0
                Layout.fillWidth: true
                Layout.preferredHeight: shouldShow ? -1 : 0
                active: shouldShow
                visible: shouldShow
                sourceComponent: stateCard
                onLoaded: {
                    item.iconName = "cloud_off";
                    item.iconColor = Theme.error;
                    item.title = "Unable to load matches";
                    item.subtitle = popout.errorMessage;
                    item.bgColor = Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.08);
                }
            }

            Loader {
                readonly property bool shouldShow: popout.errorMessage === "" && !popout.loading && popout.todayMatches.length === 0
                Layout.fillWidth: true
                Layout.preferredHeight: shouldShow ? -1 : 0
                active: shouldShow
                visible: shouldShow
                sourceComponent: stateCard
                onLoaded: {
                    item.iconName = "sports_soccer";
                    item.title = "No matches today";
                    item.subtitle = "Check back on a match day";
                }
            }

            Repeater {
                model: popout.todayMatches
                delegate: MatchCard {
                    required property var modelData
                    Layout.fillWidth: true
                    matchData: modelData
                    goals: matchData ? (popout.matchGoals[matchData.id] || []) : []
                    pinned: matchData ? matchData.id === popout.pinnedMatchId : false
                    onPinClicked: popout.matchPinned(matchData.id, popout.activeLeague)
                }
            }
        }
    }

    Component {
        id: matchdayTab

        ColumnLayout {
            width: parent ? parent.width : 0
            spacing: Theme.spacingXS

            Loader {
                readonly property bool shouldShow: popout.matchdayError !== "" && popout.matchdayMatches.length === 0
                Layout.fillWidth: true
                Layout.preferredHeight: shouldShow ? -1 : 0
                active: shouldShow
                visible: shouldShow
                sourceComponent: stateCard
                onLoaded: {
                    item.iconName = "cloud_off";
                    item.iconColor = Theme.error;
                    item.title = "Unable to load matchday";
                    item.subtitle = popout.matchdayError;
                    item.bgColor = Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.08);
                }
            }

            Loader {
                readonly property bool shouldShow: popout.matchdayError === "" && !popout.matchdayLoading && popout.matchdayMatches.length === 0
                Layout.fillWidth: true
                Layout.preferredHeight: shouldShow ? -1 : 0
                active: shouldShow
                visible: shouldShow
                sourceComponent: stateCard
                onLoaded: {
                    item.iconName = "calendar_month";
                    item.title = popout.currentMatchday > 0
                        ? "No matches for matchday " + popout.currentMatchday
                        : "Loading matchday...";
                    item.subtitle = popout.currentMatchday > 0 ? "" : "Fetching current matchday";
                }
            }

            Repeater {
                model: Api.groupByDate(popout.matchdayMatches)

                delegate: Loader {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true

                    sourceComponent: modelData.type === "header" ? dateHeader : matchDelegate

                    onLoaded: {
                        if (modelData.type === "header") {
                            item.dateLabel = modelData.dateLabel;
                        } else {
                            item.matchData = modelData;
                        }
                    }
                }
            }
        }
    }

    Component {
        id: standingsTab

        ColumnLayout {
            width: parent ? parent.width : 0
            spacing: Theme.spacingS

            Loader {
                readonly property bool shouldShow: popout.standingsError !== ""
                Layout.fillWidth: true
                Layout.preferredHeight: shouldShow ? -1 : 0
                active: shouldShow
                visible: shouldShow
                sourceComponent: stateCard
                onLoaded: {
                    item.iconName = "cloud_off";
                    item.iconColor = Theme.error;
                    item.title = "Unable to load standings";
                    item.subtitle = popout.standingsError;
                    item.bgColor = Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.08);
                }
            }

            Loader {
                readonly property bool shouldShow: popout.standingsError === "" && !popout.standingsLoading && popout.standings.length === 0 && popout.standingsGroups.length === 0
                Layout.fillWidth: true
                Layout.preferredHeight: shouldShow ? -1 : 0
                active: shouldShow
                visible: shouldShow
                sourceComponent: stateCard
                onLoaded: {
                    item.iconName = "leaderboard";
                    item.title = "No standings available";
                }
            }

            StyledRect {
                visible: popout.standings.length > 0
                Layout.fillWidth: true
                implicitHeight: leagueTableCol.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh

                Column {
                    id: leagueTableCol
                    anchors.fill: parent
                    anchors.topMargin: Theme.spacingM
                    anchors.bottomMargin: Theme.spacingM
                    spacing: 0

                    StandingRow { isHeader: true; rowData: null }

                    Repeater {
                        model: popout.standings
                        delegate: StandingRow {
                            required property var modelData
                            rowData: modelData
                            leagueCode: popout.activeLeague
                            totalTeams: popout.standings.length
                        }
                    }
                }
            }

            Repeater {
                model: popout.standingsGroups

                delegate: StyledRect {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: groupCol.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Column {
                        id: groupCol
                        anchors.fill: parent
                        anchors.topMargin: Theme.spacingM
                        anchors.bottomMargin: Theme.spacingM
                        spacing: 0

                        Item {
                            width: parent.width
                            height: 28
                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingS

                                DankIcon {
                                    name: "group"; size: 16; color: Theme.primary; opacity: 0.8
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: modelData.label || "Group"
                                    font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        StandingRow { isHeader: true; rowData: null }

                        Repeater {
                            id: groupRepeater
                            model: modelData.rows
                            delegate: StandingRow {
                                required property var modelData
                                rowData: modelData
                                leagueCode: popout.activeLeague
                                totalTeams: groupRepeater.count
                            }
                        }
                    }
                }
            }
        }
    }

    // === Date section header ===
    Component {
        id: dateHeader
        Item {
            property string dateLabel: ""
            width: parent.width
            implicitHeight: 32

            Row {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                Rectangle {
                    width: 3; height: 14; radius: 1.5
                    color: Theme.primary; opacity: 0.5
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: dateLabel
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // === Match delegate ===
    Component {
        id: matchDelegate
        MatchCard {
            matchData: null
            goals: matchData ? (popout.matchGoals[matchData.id] || []) : []
            pinned: matchData ? matchData.id === popout.pinnedMatchId : false
            onPinClicked: { if (matchData) popout.matchPinned(matchData.id, popout.activeLeague); }
        }
    }

    // === State card ===
    Component {
        id: stateCard
        StyledRect {
            property string iconName: "sports_soccer"
            property color iconColor: Theme.surfaceVariantText
            property string title: ""
            property string subtitle: ""
            property color bgColor: Theme.surfaceContainerHigh

            implicitHeight: stateCol.implicitHeight + Theme.spacingL * 2
            radius: Theme.cornerRadius
            color: bgColor

            Column {
                id: stateCol
                anchors.centerIn: parent
                width: parent.width - Theme.spacingL * 2
                spacing: Theme.spacingM

                DankIcon { anchors.horizontalCenter: parent.horizontalCenter; name: iconName; size: 40; color: iconColor; opacity: 0.4 }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS
                    StyledText { visible: title !== ""; width: parent.width; text: title; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Medium; color: Theme.surfaceText; horizontalAlignment: Text.AlignHCenter }
                    StyledText { visible: subtitle !== ""; width: parent.width; text: subtitle; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter; opacity: 0.6 }
                }
            }
        }
    }
}
