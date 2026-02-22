import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import "SoccerApi.js" as Api

StyledRect {
    id: card

    required property var matchData
    property var goals: []
    property bool pinned: false

    signal pinClicked()

    readonly property bool live: matchData ? Api.isLive(matchData.status) : false
    readonly property bool finished: matchData ? Api.isFinished(matchData.status) : false
    readonly property int crestSize: 32
    readonly property color teamTextColor: finished ? Theme.surfaceVariantText : Theme.surfaceText
    readonly property var homeGoals: _filterGoals("home")
    readonly property var awayGoals: _filterGoals("away")
    readonly property bool hasGoals: goals.length > 0

    function _filterGoals(side) {
        var result = [];
        for (var i = 0; i < goals.length; i++) {
            if (goals[i].side === side) result.push(goals[i]);
        }
        return result;
    }

    width: parent.width
    implicitHeight: hasGoals ? 88 + goalsSection.height + Theme.spacingS : 88
    radius: Theme.cornerRadius
    color: live ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.06)
                : Theme.surfaceContainerHigh

    border.color: live ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : "transparent"
    border.width: live ? 1 : 0

    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }

    // Left status strip
    Rectangle {
        width: 3
        height: parent.height - 16
        radius: 1.5
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        color: {
            if (live) return Theme.primary;
            if (finished) return Theme.surfaceVariantText;
            return "transparent";
        }
        opacity: live ? 1.0 : 0.25

        SequentialAnimation on opacity {
            running: live
            loops: Animation.Infinite
            NumberAnimation { from: 1; to: 0.3; duration: 800; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.3; to: 1; duration: 800; easing.type: Easing.InOutSine }
        }
    }

    // Pin button
    DankIcon {
        id: pinIcon
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 6
        anchors.rightMargin: 6
        name: "push_pin"
        filled: pinned
        size: 13
        color: pinned ? Theme.primary : Theme.surfaceVariantText
        opacity: {
            if (pinned) return 1.0;
            if (pinArea.containsMouse) return 0.7;
            if (live || finished) return 0.25;
            return 0;
        }

        Behavior on opacity { NumberAnimation { duration: 150 } }

        MouseArea {
            id: pinArea
            anchors.fill: parent
            anchors.margins: -8
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.pinClicked()
        }
    }

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Theme.spacingM + 2
        anchors.rightMargin: Theme.spacingM
        height: 88
        spacing: 0

        // Home team
        TeamDisplay {
            Layout.fillWidth: true
            Layout.fillHeight: true
            teamName: matchData ? matchData.homeTeam : ""
            crestUrl: matchData ? matchData.homeCrest || "" : ""
            crestSize: card.crestSize
            dimmed: finished
            maxNameWidth: card.width / 2 - 72
            nameColor: teamTextColor
        }

        // Score / status center
        Item {
            Layout.preferredWidth: 100
            Layout.fillHeight: true

            // Score pill background
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -2
                width: 80
                height: 52
                radius: 10
                color: {
                    if (live) return Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10);
                    var a = finished ? 0.04 : 0.03;
                    return Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, a);
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -2
                spacing: 3

                StyledText {
                    width: 100
                    text: matchData ? Api.scoreText(matchData) : ""
                    font.pixelSize: live ? 20 : 17
                    font.weight: Font.Bold
                    color: live ? Theme.primary : (finished ? Theme.surfaceVariantText : Theme.surfaceText)
                    horizontalAlignment: Text.AlignHCenter
                }

                StyledText {
                    width: 100
                    text: {
                        if (!matchData) return "";
                        if (live) {
                            return matchData.minute ? matchData.minute + "'" : "Live";
                        }
                        return Api.matchStatusLabel(matchData.status);
                    }
                    font.pixelSize: 11
                    font.weight: live ? Font.Bold : Font.Normal
                    color: live ? Theme.primary : Theme.surfaceVariantText
                    horizontalAlignment: Text.AlignHCenter
                    opacity: live ? 0.9 : 0.5
                }
            }
        }

        // Away team
        TeamDisplay {
            Layout.fillWidth: true
            Layout.fillHeight: true
            teamName: matchData ? matchData.awayTeam : ""
            crestUrl: matchData ? matchData.awayCrest || "" : ""
            crestSize: card.crestSize
            dimmed: finished
            maxNameWidth: card.width / 2 - 72
            nameColor: teamTextColor
        }
    }

    // === Goals section ===
    Item {
        id: goalsSection
        visible: card.hasGoals
        anchors.top: parent.top
        anchors.topMargin: 84
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.spacingM + 2
        anchors.rightMargin: Theme.spacingM
        height: visible ? goalsContent.implicitHeight + Theme.spacingXS : 0

        // Subtle separator line
        Rectangle {
            id: goalsSeparator
            width: parent.width * 0.6
            height: 1
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.surfaceVariantText
            opacity: 0.12
        }

        Row {
            id: goalsContent
            anchors.top: goalsSeparator.bottom
            anchors.topMargin: Theme.spacingXS
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 0

            // Home goals column — right-aligned
            Column {
                id: homeGoalsCol
                width: (parent.width - 100) / 2
                spacing: 3

                Repeater {
                    model: card.homeGoals
                    delegate: Row {
                        required property var modelData
                        anchors.right: parent.right
                        spacing: Theme.spacingXS

                        StyledText {
                            text: modelData.player
                            font.pixelSize: Theme.fontSizeSmall - 1
                            color: Theme.surfaceVariantText
                            opacity: 0.8
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, homeGoalsCol.width - minuteHome.width - goalIconHome.width - Theme.spacingXS * 2)
                        }

                        StyledText {
                            id: minuteHome
                            text: modelData.minute + "'"
                            font.pixelSize: Theme.fontSizeSmall - 1
                            font.weight: Font.Medium
                            color: Theme.surfaceVariantText
                            opacity: 0.5
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        DankIcon {
                            id: goalIconHome
                            name: "sports_soccer"
                            size: 10
                            color: card.live ? Theme.primary : Theme.surfaceVariantText
                            opacity: card.live ? 0.8 : 0.4
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            // Center spacer (matches score column width)
            Item { width: 100; height: 1 }

            // Away goals column — left-aligned
            Column {
                id: awayGoalsCol
                width: (parent.width - 100) / 2
                spacing: 3

                Repeater {
                    model: card.awayGoals
                    delegate: Row {
                        required property var modelData
                        anchors.left: parent.left
                        spacing: Theme.spacingXS

                        DankIcon {
                            id: goalIconAway
                            name: "sports_soccer"
                            size: 10
                            color: card.live ? Theme.primary : Theme.surfaceVariantText
                            opacity: card.live ? 0.8 : 0.4
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            id: minuteAway
                            text: modelData.minute + "'"
                            font.pixelSize: Theme.fontSizeSmall - 1
                            font.weight: Font.Medium
                            color: Theme.surfaceVariantText
                            opacity: 0.5
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: modelData.player
                            font.pixelSize: Theme.fontSizeSmall - 1
                            color: Theme.surfaceVariantText
                            opacity: 0.8
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, awayGoalsCol.width - minuteAway.width - goalIconAway.width - Theme.spacingXS * 2)
                        }
                    }
                }
            }
        }
    }
}
